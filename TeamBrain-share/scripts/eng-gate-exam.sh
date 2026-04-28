#!/bin/bash
# eng-gate-exam.sh — Stop hook. Mirrors laziness-self-report.sh structure.
# Parses the <teambrain-eng-gate> schema in last assistant message and runs
# a deterministic decision tree. Trusts schema bools; does not classify NL.

set -uo pipefail

LOG_DIR="${HOME}/.claude-teambrain-share/logs"
LOG_FILE="${LOG_DIR}/eng-gate.jsonl"
mkdir -p "$LOG_DIR"

input="$(cat 2>/dev/null || true)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
state_file="/tmp/teambrain-eng-gate-${session_id}.state"

TEMPLATE='<teambrain-eng-gate>
session_type: <PLAN|EXPLAIN|ACTION_HIGH_LEVEL|ACTION_LOW_LEVEL>
prompt_has_acceptance_criteria: <true|false>
gstack_installed: <true|false>
project_uses_gstack: <true|false>
user_said_go_to_insist: <true|false>
is_subagent_inner_call: <true|false>
my_response_complies_with_gate: <true|false>
</teambrain-eng-gate>'

mark_blocked() {
  printf 'last_blocked=true\nblocked_at=%s\nreason=%s\n' "$ts" "$1" > "$state_file"
}
mark_approved() {
  printf 'last_blocked=false\napproved_at=%s\n' "$ts" > "$state_file"
}

emit_block() {
  local reason="$1"
  local sysmsg="$2"
  local action="$3"
  mark_blocked "$action"
  jq -cn --arg ts "$ts" --arg sid "$session_id" --arg act "$action" \
    '{ts:$ts, session_id:$sid, action:$act}' >> "$LOG_FILE"
  jq -n --arg reason "$reason" --arg sysmsg "$sysmsg" \
    '{decision:"block", reason:$reason, systemMessage:$sysmsg}'
  exit 0
}

emit_approve() {
  local action="$1"
  mark_approved
  jq -cn --arg ts "$ts" --arg sid "$session_id" --arg act "$action" \
    '{ts:$ts, session_id:$sid, action:$act}' >> "$LOG_FILE"
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
}

# --- Read last assistant text from transcript (race-condition guard) ---
if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
  emit_block \
    "transcript_path missing/unreadable. Append the gate schema:\n\n${TEMPLATE}" \
    "[teambrain-eng-gate] BLOCKED: no transcript" \
    "block_no_transcript"
fi

extract_last_text() {
  jq -rs '
    [.[] | select(.type == "assistant")
          | select((.message.content // []) | any(.type == "text"))]
    | last
    | (.message.content // [])
    | map(select(.type == "text") | .text)
    | join("\n")
  ' "$transcript_path" 2>/dev/null
}

last_text=""
sleep 0.3
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  candidate="$(extract_last_text || echo "")"
  if [[ -n "$candidate" ]]; then
    last_text="$candidate"
    if echo "$candidate" | grep -q '<teambrain-eng-gate>'; then
      break
    fi
  fi
  sleep 0.3
done

if [[ -z "$last_text" ]]; then
  emit_block \
    "no text content in last assistant message. Append the gate schema:\n\n${TEMPLATE}" \
    "[teambrain-eng-gate] BLOCKED: empty assistant message" \
    "block_empty_msg"
fi

# --- Find <teambrain-eng-gate> block ---
report_body="$(echo "$last_text" | awk '
  /<teambrain-eng-gate>/ { found=1; next }
  /<\/teambrain-eng-gate>/ { found=0; exit }
  found { print }
')"

if [[ -z "$report_body" ]]; then
  emit_block \
    "Your last message is missing the <teambrain-eng-gate> block. Append this exact block at the END of every message:\n\n${TEMPLATE}" \
    "[teambrain-eng-gate] BLOCKED: schema missing" \
    "block_schema_missing"
fi

# --- Parse fields ---
parse_field() {
  echo "$report_body" \
    | grep -iE "^[[:space:]]*$1[[:space:]]*:" \
    | head -1 \
    | sed -E 's/^[^:]*:[[:space:]]*([A-Za-z_]+).*/\1/' \
    | tr '[:upper:]' '[:lower:]'
}

session_type="$(parse_field session_type)"
has_ac="$(parse_field prompt_has_acceptance_criteria)"
gstack_installed="$(parse_field gstack_installed)"
project_uses_gstack="$(parse_field project_uses_gstack)"
go_insist="$(parse_field user_said_go_to_insist)"
is_subagent="$(parse_field is_subagent_inner_call)"
complies="$(parse_field my_response_complies_with_gate)"

# Validate enum + bools.
case "$session_type" in
  plan|explain|action_high_level|action_low_level) ;;
  *)
    emit_block \
      "session_type='$session_type' invalid. Must be PLAN|EXPLAIN|ACTION_HIGH_LEVEL|ACTION_LOW_LEVEL.\n\n${TEMPLATE}" \
      "[teambrain-eng-gate] BLOCKED: bad session_type" \
      "block_bad_session_type"
    ;;
esac

for pair in "has_ac:$has_ac" "gstack_installed:$gstack_installed" "project_uses_gstack:$project_uses_gstack" "go_insist:$go_insist" "is_subagent:$is_subagent" "complies:$complies"; do
  v="${pair#*:}"
  if [[ "$v" != "true" && "$v" != "false" ]]; then
    emit_block \
      "field '${pair%%:*}' has invalid value '$v' (must be true|false).\n\n${TEMPLATE}" \
      "[teambrain-eng-gate] BLOCKED: malformed field" \
      "block_malformed"
  fi
done

# --- Decision tree ---
# 1. subagent → approve
if [[ "$is_subagent" == "true" ]]; then
  emit_approve "approve_subagent"
fi

# 2. insist override → approve
if [[ "$go_insist" == "true" ]]; then
  emit_approve "approve_insist"
fi

# 3. self-admitted non-compliance → block
if [[ "$complies" == "false" ]]; then
  emit_block \
    "You self-attested my_response_complies_with_gate=false. Replace your last response with the appropriate canned refusal (see UserPromptSubmit injected rules) and re-emit with my_response_complies_with_gate=true." \
    "[teambrain-eng-gate] BLOCKED: self-admitted violation" \
    "block_self_admit"
fi

# 4. PLAN / EXPLAIN → approve
if [[ "$session_type" == "plan" || "$session_type" == "explain" ]]; then
  emit_approve "approve_${session_type}"
fi

# 5. ACTION_LOW_LEVEL → block
if [[ "$session_type" == "action_low_level" ]]; then
  emit_block \
    "session_type=ACTION_LOW_LEVEL is forbidden. Replace your last response with ONLY:\n\n  禁止 fine-grained engineer-level 指令。\n  ❌ BAD: 引用具体文件/行号/函数/步骤\n  ✅ GOOD: 我要这个 outcome + 怎么算完成（直到/为止）\n  请重写为高层级 prompt。要跳过此门请只回一个字：go\n\nDo NOT touch files. Then re-emit with my_response_complies_with_gate=true." \
    "[teambrain-eng-gate] BLOCKED: ACTION_LOW_LEVEL" \
    "block_low_level"
fi

# 6. ACTION_HIGH_LEVEL → check preconditions
if [[ "$session_type" == "action_high_level" ]]; then
  if [[ "$gstack_installed" == "false" ]]; then
    emit_block \
      "gstack not installed. Replace your last response with ONLY:\n\n  gstack 未安装。请先装：\n    /plugin marketplace add garrytan/gstack\n    /plugin install gstack@gstack\n  GitHub: https://github.com/garrytan/gstack\n  装完后重启 Claude。要跳过此门请只回一个字：go\n\nDo NOT proceed. Then re-emit with my_response_complies_with_gate=true." \
      "[teambrain-eng-gate] BLOCKED: gstack not installed" \
      "block_no_gstack"
  fi
  if [[ "$project_uses_gstack" == "false" ]]; then
    emit_block \
      "project never used gstack. Replace your last response with ONLY:\n\n  本项目尚未走 gstack 流程（无 .gstack/、无 docs/gstack/、无 plan-ceo-review/office-hours 历史）。\n  请先跑 /office-hours 或 /plan-ceo-review。\n  要跳过此门请只回一个字：go\n\nDo NOT make code changes. Then re-emit with my_response_complies_with_gate=true." \
      "[teambrain-eng-gate] BLOCKED: project never used gstack" \
      "block_no_project_use"
  fi
  if [[ "$has_ac" == "false" ]]; then
    emit_block \
      "prompt lacks acceptance criteria. Replace your last response with ONLY:\n\n  你的请求缺少『跑到什么程度才算完』的验收条件。\n  请补充完成判定（直到/until/verify/为止/done when ...）。\n  要跳过此门请只回一个字：go\n\nDo NOT start work. Then re-emit with my_response_complies_with_gate=true." \
      "[teambrain-eng-gate] BLOCKED: no acceptance criteria" \
      "block_no_ac"
  fi
  emit_approve "approve_action_high_level"
fi

# Should not reach here.
emit_block \
  "decision tree fell through unexpectedly (session_type=$session_type)." \
  "[teambrain-eng-gate] BLOCKED: tree fall-through" \
  "block_fallthrough"
