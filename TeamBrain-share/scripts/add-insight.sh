#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/common.sh"

NAME=""
WHEN=""
DESC=""
RAW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --when) WHEN="$2"; shift 2 ;;
    --description) DESC="$2"; shift 2 ;;
    --raw) RAW="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "${NAME}" || -z "${DESC}" ]] && {
  echo "usage: add-insight.sh --name NAME --when WHEN --description DESC [--raw RAW]" >&2
  exit 2
}

ensure_index

UPLOADER="$(whoami)"
UPLOADER_IP="$(hostname)"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RAW="${RAW:-${NAME}\n${WHEN}\n${DESC}}"
RAW_HASH="$(printf '%s' "${RAW}" | shasum -a 256 | awk '{print $1}')"
CONTENT_HASH="$(printf '%s|%s|%s' "${NAME}" "${WHEN}" "${DESC}" | shasum -a 256 | awk '{print $1}')"

jq -n --arg raw "${RAW}" --arg u "${UPLOADER}" --arg ip "${UPLOADER_IP}" --arg t "${CREATED_AT}" \
  '{original_message:$raw,uploader:$u,uploader_ip:$ip,created_at:$t}' > "${RAW_DIR}/${RAW_HASH}.json"

TMP="$(mktemp)"
jq --arg n "${NAME}" --arg w "${WHEN}" --arg d "${DESC}" --arg u "${UPLOADER}" --arg ip "${UPLOADER_IP}" \
   --arg ch "${CONTENT_HASH}" --arg rh "${RAW_HASH}" --arg t "${CREATED_AT}" '
  if (.insights | any(.content_hash == $ch)) then .
  else .insights += [{
    name:$n, when_to_use:$w, description:$d, uploader:$u, uploader_ip:$ip,
    content_hash:$ch, raw_hashes:[$rh], created_at:$t, topic_slug:"team-shared"
  }]
  end
' "${INDEX}" > "${TMP}" && mv "${TMP}" "${INDEX}"

"${PLUGIN_DIR}/scripts/rsync-merge.sh" >/dev/null 2>>"${LOG_DIR}/rsync-merge.err" || true
"${PLUGIN_DIR}/scripts/teamagent-import.sh" >/dev/null 2>>"${LOG_DIR}/teamagent-import.err" || true

echo "[teambrain-share] added ${CONTENT_HASH}"
