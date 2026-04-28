#!/bin/bash

set -u
source "$(dirname "$0")/common.sh"

ensure_index

echo "TeamBrain-share doctor"
echo "plugin_dir=${PLUGIN_DIR}"
echo "team_dir=${TEAM_DIR}"
echo "index=${INDEX}"
echo "insights=$(jq '.insights | length' "${INDEX}" 2>/dev/null || echo 0)"

if have_teamagent; then
  echo "teamagent=$(command -v teamagent)"
  (cd "$(project_cwd)" && teamagent doctor 2>/dev/null || true)
else
  echo "teamagent=missing"
fi

if [[ -f "${CONFIG}" ]]; then
  echo "teammates=$(jq '.teammates | length' "${CONFIG}" 2>/dev/null || echo 0)"
else
  echo "teammates=missing-config"
fi
