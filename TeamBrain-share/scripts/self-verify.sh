#!/bin/bash
# self-verify.sh — external-observer verification wrapper (L0/L1/L2/L5)
#
# 不信任 actor 自报 (L0)。用 4 个独立观察者交叉验证：
#   L0  actor stdout / exit code              (untrusted)
#   L1  stat + sha256        per-file diff    (kernel)
#   L2  find -newer marker   write events     (kernel mtime)
#   L5  lsof -i before/after socket diff      (kernel sockets)
#
# Contract-driven verdict:
#   - if contract has "must" clause and L2 == 0 events → FAIL
#   - if actor exit != 0 → FAIL
#   - else PASS
#
# (L4 LLM judge intentionally removed — it added 25-30s per run with
#  no extra coverage beyond the contract heuristic above.)
#
# Usage:
#   self-verify.sh --actor 'CMD' [options]
#
# Exit:
#   0  PASS
#   1  FAIL
#   2  bad args / setup error

set -u

usage() {
  cat <<'EOF'
Usage: self-verify.sh --actor 'CMD' [options]

Required:
  --actor CMD          Actor command to verify (quoted)

Options:
  --watch DIR          Directory to watch (default: ~/.claude-teambrain-share)
  --contract FILE      JSON contract describing must / must_not (optional)
  --output DIR         Artifacts directory (default: /tmp/self-verify-$$)
  --net-pattern REGEX  Process name regex for L5 (default: rsync|ssh|teamagent)
  --no-network         Skip L5 (lsof network diff)
  --quiet              Suppress phase headers, only print final report
  -h, --help           This help
EOF
}

# ---------- arg parsing ----------
ACTOR=""
WATCH_DIR="${HOME}/.claude-teambrain-share"
CONTRACT=""
OUTDIR=""
DO_NETWORK=1
QUIET=0
NET_PATTERN='rsync|ssh|teamagent'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)        ACTOR="$2"; shift 2 ;;
    --watch)        WATCH_DIR="$2"; shift 2 ;;
    --contract)     CONTRACT="$2"; shift 2 ;;
    --output)       OUTDIR="$2"; shift 2 ;;
    --net-pattern)  NET_PATTERN="$2"; shift 2 ;;
    --no-network)   DO_NETWORK=0; shift ;;
    --quiet)        QUIET=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -z "$ACTOR" ]]    && { echo "ERROR: --actor required" >&2; exit 2; }
[[ ! -d "$WATCH_DIR" ]] && { echo "ERROR: watch dir not found: $WATCH_DIR" >&2; exit 2; }

OUTDIR="${OUTDIR:-/tmp/self-verify-$$}"
mkdir -p "$OUTDIR"

say() { [[ $QUIET -eq 0 ]] && echo "$@"; }

# ---------- helpers ----------
snapshot_files() {
  find "$WATCH_DIR" -type f 2>/dev/null | sort | while IFS= read -r f; do
    local mt sz sha
    mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
    sz=$(stat -f %z "$f" 2>/dev/null || echo 0)
    sha=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
    printf '%s|%s|%s|%s\n' "$mt" "$sz" "$sha" "$f"
  done > "$1"
}

snapshot_sockets() {
  lsof -i -n -P 2>/dev/null \
    | awk 'NR>1 {print $1"|"$8"|"$9}' \
    | sort -u > "$1"
}

# ---------- Phase 0: BEFORE ----------
say "[L1] snapshot BEFORE..."
snapshot_files "$OUTDIR/before.tsv"
say "  files tracked: $(wc -l < "$OUTDIR/before.tsv" | tr -d ' ')"

# ---------- Phase 1: install marker (L2 anchor) ----------
touch "$OUTDIR/marker"
sleep 1   # ensure mtime granularity gap

# ---------- Phase 2: BEFORE sockets ----------
if [[ $DO_NETWORK -eq 1 ]]; then
  say "[L5] snapshot sockets BEFORE..."
  snapshot_sockets "$OUTDIR/sockets.before"
fi

# ---------- Phase 3: run ACTOR (L0) ----------
say "[L0] running actor..."
T0=$(date +%s)
eval "$ACTOR" > "$OUTDIR/stdout.log" 2> "$OUTDIR/stderr.log"
ACTOR_EXIT=$?
T1=$(date +%s)
WALL=$((T1 - T0))
say "  exit=$ACTOR_EXIT wall=${WALL}s"

# ---------- Phase 4: AFTER snapshots ----------
if [[ $DO_NETWORK -eq 1 ]]; then
  snapshot_sockets "$OUTDIR/sockets.after"
  comm -13 "$OUTDIR/sockets.before" "$OUTDIR/sockets.after" \
    | grep -E "^(${NET_PATTERN})\|" > "$OUTDIR/sockets.new" || true
fi

say "[L1] snapshot AFTER..."
snapshot_files "$OUTDIR/after.tsv"

# ---------- Phase 5: harvest L2 events + L1 diff ----------
find "$WATCH_DIR" -newer "$OUTDIR/marker" -type f 2>/dev/null \
  | sort > "$OUTDIR/events.log"

diff "$OUTDIR/before.tsv" "$OUTDIR/after.tsv" > "$OUTDIR/diff.txt" || true

L2_EVENTS=$(wc -l < "$OUTDIR/events.log" | tr -d ' ')
L5_NEW_SOCKETS=0
if [[ $DO_NETWORK -eq 1 ]]; then
  L5_NEW_SOCKETS=$(wc -l < "$OUTDIR/sockets.new" 2>/dev/null | tr -d ' ' || echo 0)
fi
ADDED=$(awk '/^>/{c++} END{print c+0}' "$OUTDIR/diff.txt")
REMOVED=$(awk '/^</{c++} END{print c+0}' "$OUTDIR/diff.txt")

# ---------- Phase 6: per-layer verdicts ----------
L0_VERDICT="exit=${ACTOR_EXIT}"

L1_VERDICT="PASS (added=$ADDED removed=$REMOVED)"
[[ $ADDED -eq 0 && $REMOVED -eq 0 ]] && L1_VERDICT="NOOP (no file change)"

L2_VERDICT="PASS (${L2_EVENTS} write events)"
[[ $L2_EVENTS -eq 0 ]] && L2_VERDICT="NOOP (0 fs events)"

L5_VERDICT="SKIPPED"
if [[ $DO_NETWORK -eq 1 ]]; then
  L5_VERDICT="PASS (0 new ${NET_PATTERN} sockets)"
  [[ $L5_NEW_SOCKETS -gt 0 ]] && L5_VERDICT="FAIL (${L5_NEW_SOCKETS} unexpected sockets)"
fi

# ---------- Phase 7: contract-driven OVERALL ----------
CONTRACT_HAS_MUST=0
if [[ -n "$CONTRACT" && -f "$CONTRACT" ]]; then
  MUST_COUNT=$(jq -r '.must // [] | length' "$CONTRACT" 2>/dev/null || echo 0)
  [[ "$MUST_COUNT" != "0" ]] && CONTRACT_HAS_MUST=1
fi

OVERALL="PASS"
RATIONALE="actor exit=0; observed effects consistent with no must-clause violations"

if [[ "$ACTOR_EXIT" != "0" ]]; then
  OVERALL="FAIL"
  RATIONALE="actor exit_code=${ACTOR_EXIT} (non-zero)"
elif [[ $CONTRACT_HAS_MUST -eq 1 && $L2_EVENTS -eq 0 ]]; then
  OVERALL="FAIL"
  RATIONALE="contract has 'must' clauses but L2 observed 0 fs events — actor likely did nothing"
elif [[ $L5_NEW_SOCKETS -gt 0 ]]; then
  OVERALL="FAIL"
  RATIONALE="L5 detected ${L5_NEW_SOCKETS} unexpected ${NET_PATTERN} socket(s)"
fi

# ---------- final report ----------
{
echo ""
echo "================================================================"
echo "  SELF-VERIFY REPORT  (L0/L1/L2/L5)"
echo "================================================================"
printf "  actor:       %s\n" "$ACTOR"
printf "  watch_dir:   %s\n" "$WATCH_DIR"
printf "  contract:    %s\n" "${CONTRACT:-<none>}"
printf "  artifacts:   %s\n" "$OUTDIR"
printf "  wall_time:   %ss\n" "$WALL"
echo ""
printf "  | %-3s | %-50s |\n" "Lyr" "Result"
printf "  |-----|----------------------------------------------------|\n"
printf "  | L0  | %-50s |\n" "actor self-report  ${L0_VERDICT}"
printf "  | L1  | %-50s |\n" "${L1_VERDICT}"
printf "  | L2  | %-50s |\n" "${L2_VERDICT}"
printf "  | L5  | %-50s |\n" "${L5_VERDICT}"
echo ""
printf "  OVERALL:   %s\n" "$OVERALL"
printf "  rationale: %s\n" "$RATIONALE"
echo ""
echo "  artifacts in $OUTDIR/:"
ls "$OUTDIR/" | sed 's/^/    /'
}

[[ "$OVERALL" == "PASS" ]] && exit 0 || exit 1
