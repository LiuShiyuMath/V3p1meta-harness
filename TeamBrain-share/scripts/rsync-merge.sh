#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/common.sh"

ensure_index
STAGING="${CACHE_DIR}/merge-staging"
ONLY="${1:-}"
mkdir -p "${STAGING}" "${RAW_DIR}"

if [[ ! -f "${CONFIG}" ]]; then
  log_line "no teammates config at ${CONFIG}"
  exit 0
fi

JQ_MERGE='
  {
    insights: (
      (.[0].insights + .[1].insights)
      | group_by(.content_hash)
      | map(
          (sort_by(.created_at // "")[0]) as $base
          | $base + {
              topic_slug: ([.[] | .topic_slug] | map(select(. != null and . != "")) | (first // null)),
              raw_hashes: ([.[] | (.raw_hashes // [])] | add | unique)
            }
        )
      | sort_by(.created_at // "")
    )
  }
'

TEAMMATES="$(jq -r '.teammates[] | @base64' "${CONFIG}" 2>/dev/null || true)"
[[ -z "${TEAMMATES}" ]] && exit 0

for entry in ${TEAMMATES}; do
  NAME="$(echo "${entry}" | base64 -d | jq -r '.name')"
  IP="$(echo "${entry}" | base64 -d | jq -r '.ip')"
  USERNAME="$(echo "${entry}" | base64 -d | jq -r '.username // "m1"')"
  [[ -n "${ONLY}" && "${ONLY}" != "${NAME}" ]] && continue

  REMOTE_INDEX="${STAGING}/${NAME}.index.json"
  MERGED="${STAGING}/${NAME}.merged.json"

  if ! rsync -az --timeout=30 "${USERNAME}@${IP}:.claude-teambrain-share/insights/index.json" "${REMOTE_INDEX}" 2>/dev/null; then
    log_line "peer unreachable name=${NAME} ip=${IP}"
    continue
  fi
  [[ ! -s "${REMOTE_INDEX}" ]] && printf '{"insights":[]}\n' > "${REMOTE_INDEX}"

  if ! jq -s "${JQ_MERGE}" "${INDEX}" "${REMOTE_INDEX}" > "${MERGED}" 2>/dev/null; then
    log_line "merge failed name=${NAME}"
    continue
  fi

  LOCAL_HASH="$(shasum -a 256 "${INDEX}" | awk '{print $1}')"
  REMOTE_HASH="$(shasum -a 256 "${REMOTE_INDEX}" | awk '{print $1}')"
  MERGED_HASH="$(shasum -a 256 "${MERGED}" | awk '{print $1}')"
  TS="$(date +%Y%m%d-%H%M%S)"

  rsync -az --ignore-existing --timeout=30 "${RAW_DIR}/" "${USERNAME}@${IP}:.claude-teambrain-share/insights/raw/" 2>/dev/null || true
  rsync -az --ignore-existing --timeout=30 "${USERNAME}@${IP}:.claude-teambrain-share/insights/raw/" "${RAW_DIR}/" 2>/dev/null || true

  if [[ "${LOCAL_HASH}" != "${MERGED_HASH}" ]]; then
    cp "${INDEX}" "${INDEX}.bak-merge-${TS}"
    cp "${MERGED}" "${INDEX}"
  fi

  if [[ "${REMOTE_HASH}" != "${MERGED_HASH}" ]]; then
    ssh -o ConnectTimeout=10 "${USERNAME}@${IP}" "mkdir -p ~/.claude-teambrain-share/insights/raw && cp ~/.claude-teambrain-share/insights/index.json ~/.claude-teambrain-share/insights/index.json.bak-merge-${TS} 2>/dev/null || true" 2>/dev/null || true
    rsync -az --timeout=30 "${MERGED}" "${USERNAME}@${IP}:.claude-teambrain-share/insights/index.json" 2>/dev/null || true
  fi

  rm -f "${REMOTE_INDEX}" "${MERGED}"
  log_line "merged peer=${NAME}"
done
