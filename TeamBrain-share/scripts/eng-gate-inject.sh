#!/bin/bash
# eng-gate-inject.sh — UserPromptSubmit hook.
# Computes gstack truth values, detects 'go' insist override, injects gate
# rules + schema requirement into Claude's context. Schema is examined later
# by eng-gate-exam.sh on Stop.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${PLUGIN_DIR}/scripts/find-office-and-ceo.sh"

input="$(cat 2>/dev/null || true)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || true)"
project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -z "$project_dir" ]] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

state_file="/tmp/teambrain-eng-gate-${session_id}.state"

# 'go' insist override — strict: prompt trimmed+lowered must equal exactly "go",
# AND a previous Stop must have logged a block in this session.
trimmed="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
insist=false
if [[ "$trimmed" == "go" ]] && [[ -f "$state_file" ]] && grep -q '^last_blocked=true' "$state_file" 2>/dev/null; then
  insist=true
  # Clear the block flag so subsequent prompts must pass the gate again.
  printf 'last_blocked=false\ninsist_used_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$state_file"
fi

# Detect gstack install + project usage.
detect_json="$("$DETECT" "$project_dir" 2>/dev/null || echo '{"gstack_installed":false,"project_uses_gstack":false,"evidence":["detect-failed"]}')"
gstack_installed="$(printf '%s' "$detect_json" | jq -r '.gstack_installed')"
project_uses_gstack="$(printf '%s' "$detect_json" | jq -r '.project_uses_gstack')"
evidence="$(printf '%s' "$detect_json" | jq -r '.evidence | join(", ")')"

# Build the additionalContext payload.
ctx=$(cat <<EOF
[teambrain-eng-gate]

Computed by hook (DO NOT change these — copy verbatim into your schema):
  gstack_installed: ${gstack_installed}
  project_uses_gstack: ${project_uses_gstack}
  user_said_go_to_insist: ${insist}
  evidence: ${evidence}

You MUST end EVERY assistant message with this schema block (exact tag, exact field names):

<teambrain-eng-gate>
session_type: <PLAN|EXPLAIN|ACTION_HIGH_LEVEL|ACTION_LOW_LEVEL>
prompt_has_acceptance_criteria: <true|false>
gstack_installed: ${gstack_installed}
project_uses_gstack: ${project_uses_gstack}
user_said_go_to_insist: ${insist}
is_subagent_inner_call: <true|false>
my_response_complies_with_gate: <true|false>
</teambrain-eng-gate>

Classification rules:
- PLAN: user invoked /plan-ceo-review, /office-hours, /plan-eng-review, /plan-design-review, or asked you to plan/review without code changes.
- EXPLAIN: user asked "what is", "how does", "why", "explain ..." — no code changes expected.
- ACTION_HIGH_LEVEL: user wants a feature/fix and provided acceptance criteria (until/verify/stop when/done when/直到/为止/完成判定).
- ACTION_LOW_LEVEL: user gave fine-grained step-by-step instructions citing specific file/line/function, OR demanded an action without any acceptance criteria.

Acceptance criteria (prompt_has_acceptance_criteria=true) requires at least one of:
  english: until | stop when | done when | verify | success criteria | acceptance
  chinese: 直到 | 何时停止 | 完成判定 | 验收 | 跑到 .* 为止

DECISION TREE — refuse the request and reply with ONLY the canned message when:
1. is_subagent_inner_call=true → ignore gate, do normal work, fill schema honestly.
2. user_said_go_to_insist=true → gate bypassed, do the work, fill schema honestly.
3. session_type in {PLAN, EXPLAIN} → proceed normally.
4. session_type=ACTION_LOW_LEVEL → REFUSE. Reply ONLY with:

   禁止 fine-grained engineer-level 指令。
   ❌ BAD: 引用具体文件/行号/函数/步骤
   ✅ GOOD: 我要这个 outcome + 怎么算完成（直到/为止）
   请重写为高层级 prompt。要跳过此门请只回一个字：go

   Then append the schema with my_response_complies_with_gate=true.

5. session_type=ACTION_HIGH_LEVEL AND gstack_installed=false → REFUSE. Reply ONLY with:

   gstack 未安装。请先装：
     /plugin marketplace add garrytan/gstack
     /plugin install gstack@gstack
   GitHub: https://github.com/garrytan/gstack
   装完后重启 Claude。要跳过此门请只回一个字：go

   Then append the schema with my_response_complies_with_gate=true.

6. session_type=ACTION_HIGH_LEVEL AND project_uses_gstack=false → REFUSE. Reply ONLY with:

   本项目尚未走 gstack 流程（无 .gstack/、无 docs/gstack/、无 plan-ceo-review/office-hours 历史）。
   请先跑 /office-hours 或 /plan-ceo-review。
   要跳过此门请只回一个字：go

   Then append the schema with my_response_complies_with_gate=true.

7. session_type=ACTION_HIGH_LEVEL AND prompt_has_acceptance_criteria=false → REFUSE. Reply ONLY with:

   你的请求缺少『跑到什么程度才算完』的验收条件。
   请补充完成判定（直到/until/verify/为止/done when ...）。
   要跳过此门请只回一个字：go

   Then append the schema with my_response_complies_with_gate=true.

8. ACTION_HIGH_LEVEL with all preconditions met → do the work, run to acceptance criteria, do not stop early.

If you cannot honestly fill the schema, fill my_response_complies_with_gate=false and stop.
EOF
)

jq -cn \
  --arg msg "$ctx" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$msg}}'

exit 0
