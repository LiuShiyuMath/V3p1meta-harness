#!/bin/bash

set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_DIR="${TEAMBRAIN_SHARE_DIR:-${HOME}/.claude-teambrain-share}"
CONFIG="${TEAM_DIR}/config/teammates.json"
INSIGHTS_DIR="${TEAM_DIR}/insights"
RAW_DIR="${INSIGHTS_DIR}/raw"
INDEX="${INSIGHTS_DIR}/index.json"
CACHE_DIR="${TEAM_DIR}/cache"
LOG_DIR="${TEAM_DIR}/logs"

ensure_dirs() {
  mkdir -p "${TEAM_DIR}/config" "${RAW_DIR}" "${CACHE_DIR}" "${LOG_DIR}"
}

ensure_index() {
  ensure_dirs
  if [[ ! -f "${INDEX}" ]]; then
    printf '{"insights":[]}\n' > "${INDEX}"
    return
  fi

  local t
  t="$(mktemp)"
  if jq -e 'type == "array"' "${INDEX}" >/dev/null 2>&1; then
    jq '{insights: .}' "${INDEX}" > "${t}" && mv "${t}" "${INDEX}"
  elif jq -e 'type == "object" and (.insights | type == "array")' "${INDEX}" >/dev/null 2>&1; then
    rm -f "${t}"
  else
    cp "${INDEX}" "${INDEX}.bak-malformed-$(date +%Y%m%d-%H%M%S)"
    printf '{"insights":[]}\n' > "${INDEX}"
    rm -f "${t}"
  fi
}

project_cwd() {
  printf '%s\n' "${CLAUDE_PROJECT_DIR:-${PWD}}"
}

have_teamagent() {
  command -v teamagent >/dev/null 2>&1
}

log_line() {
  ensure_dirs
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "${LOG_DIR}/teambrain-share.log"
}
