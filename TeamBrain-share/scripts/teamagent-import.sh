#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/common.sh"

ensure_index

if ! have_teamagent; then
  log_line "teamagent not found; import skipped"
  exit 0
fi

PROJECT_DIR="$(project_cwd)"
mkdir -p "${PROJECT_DIR}"

EXPORT_PATH="${CACHE_DIR}/teamagent-insights-$(date +%Y%m%d-%H%M%S).json"
"${PLUGIN_DIR}/scripts/export-teamagent-insights.sh" "${EXPORT_PATH}" >/dev/null

COUNT="$(jq '.insights | length' "${EXPORT_PATH}" 2>/dev/null || echo 0)"
if [[ "${COUNT}" == "0" ]]; then
  log_line "no insights to import"
  exit 0
fi

(
  cd "${PROJECT_DIR}"
  if [[ ! -f ".teamagent/knowledge.db" ]]; then
    teamagent init --skip-import >/dev/null 2>>"${LOG_DIR}/teamagent-import.err" || true
  fi
  teamagent ingest --from-insights "${EXPORT_PATH}" >>"${LOG_DIR}/teamagent-import.log" 2>>"${LOG_DIR}/teamagent-import.err" || true
)

log_line "import attempted count=${COUNT} project=${PROJECT_DIR}"
