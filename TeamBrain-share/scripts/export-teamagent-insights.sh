#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/common.sh"

ensure_index

OUT="${1:-${CACHE_DIR}/teamagent-insights.json}"
mkdir -p "$(dirname "${OUT}")"

jq '
  {
    insights: [
      .insights[]
      | {
          type: (.topic_slug // "team-shared"),
          weight: 0.8,
          text: (
            "title: " + (.name // "") + "\n" +
            "when: " + (.when_to_use // "") + "\n" +
            "lesson: " + (.description // "") + "\n" +
            "source: " + (.uploader // "unknown") + " @ " + (.uploader_ip // "unknown") + "\n" +
            "content_hash: " + (.content_hash // "")
          )
        }
      | select(.text | length > 20)
    ]
  }
' "${INDEX}" > "${OUT}"

printf '%s\n' "${OUT}"
