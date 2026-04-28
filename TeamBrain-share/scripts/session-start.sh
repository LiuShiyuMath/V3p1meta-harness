#!/bin/bash

set -u
source "$(dirname "$0")/common.sh"

ensure_index

"${PLUGIN_DIR}/scripts/rsync-merge.sh" >/dev/null 2>>"${LOG_DIR}/rsync-merge.err" || true
"${PLUGIN_DIR}/scripts/teamagent-import.sh" >/dev/null 2>>"${LOG_DIR}/teamagent-import.err" || true

exit 0
