#!/bin/bash

set -u
source "$(dirname "$0")/common.sh"

ensure_index

RAW="$(cat 2>/dev/null || true)"
PROMPT="${1:-}"
if [[ -z "${PROMPT}" && -n "${RAW}" ]]; then
  PROMPT="$(printf '%s' "${RAW}" | jq -r '.prompt // .message // empty' 2>/dev/null || true)"
fi
[[ -z "${PROMPT}" ]] && exit 0

RESULTS="$(jq --arg p "$(printf '%s' "${PROMPT}" | tr "[:upper:]" "[:lower:]")" -r '
  .insights[]
  | select([.name, .description, .when_to_use, .topic_slug] | any((. // "" | ascii_downcase) | contains($p)))
  | "### " + (.name // "Untitled") + "\nWhen: " + (.when_to_use // "") + "\nSource: " + (.uploader // "unknown") + " @ " + (.uploader_ip // "unknown") + "\nLesson: " + (.description // "") + "\n"
' "${INDEX}" 2>/dev/null | head -c 3000)"

if [[ -n "${RESULTS}" ]]; then
  jq -n --arg msg "TeamBrain-share LAN insights matched:\n\n${RESULTS}" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$msg},systemMessage:"TeamBrain-share: LAN insights injected"}'
fi

exit 0
