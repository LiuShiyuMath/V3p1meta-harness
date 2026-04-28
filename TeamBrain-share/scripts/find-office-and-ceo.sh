#!/bin/bash
# find-office-and-ceo.sh — detect gstack install + project usage of plan-ceo-review/office-hours.
# Outputs JSON to stdout: {"gstack_installed":bool, "project_uses_gstack":bool, "evidence":[...]}
# Usage: find-office-and-ceo.sh [project_dir]   (default: $PWD)

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { echo '{"error":"bad project dir"}'; exit 1; }

evidence=()

# ---- 1. gstack INSTALLED at user level? ----
# Strongest signal: both core skills exist as user-level skills.
gstack_installed=false
if [[ -d "$HOME/.claude/skills/plan-ceo-review" ]] \
   && [[ -d "$HOME/.claude/skills/office-hours" ]]; then
  gstack_installed=true
  evidence+=("user-skills:~/.claude/skills/{plan-ceo-review,office-hours}")
fi
# Backup signal: marketplace cache.
if [[ "$gstack_installed" == "false" ]]; then
  if compgen -G "$HOME/.claude/plugins/cache/*/gstack*" >/dev/null 2>&1 \
     || compgen -G "$HOME/.claude/plugins/marketplaces/*/gstack*" >/dev/null 2>&1; then
    gstack_installed=true
    evidence+=("plugin-cache:gstack-found")
  fi
fi

# ---- 2. PROJECT actually USED gstack? ----
# Signals (ANY of these = used):
#   a. project has .gstack/ marker dir
#   b. project has docs/gstack/ dir with content
#   c. project has docs/gstack/ceo-plans/ or office-hours-design-*.md artefacts
#   d. session jsonl for this project mentions plan-ceo-review or office-hours
project_uses_gstack=false

# (a) .gstack marker
if [[ -d "$PROJECT_DIR/.gstack" ]]; then
  project_uses_gstack=true
  evidence+=("project-marker:.gstack/")
fi

# (b) docs/gstack dir
if [[ -d "$PROJECT_DIR/docs/gstack" ]]; then
  project_uses_gstack=true
  evidence+=("project-docs:docs/gstack/")
fi

# (c) artefacts inside docs/gstack
if compgen -G "$PROJECT_DIR/docs/gstack/ceo-plans/*" >/dev/null 2>&1; then
  project_uses_gstack=true
  evidence+=("project-artefact:docs/gstack/ceo-plans/")
fi
if compgen -G "$PROJECT_DIR/docs/gstack/office-hours-design-*.md" >/dev/null 2>&1; then
  project_uses_gstack=true
  evidence+=("project-artefact:office-hours-design-*.md")
fi

# (d) session jsonl evidence — Claude Code stores per-project sessions at
# ~/.claude/projects/-Users-<user>-projects-<NAME>/*.jsonl
proj_slug="$(echo "$PROJECT_DIR" | sed 's|^/||; s|/|-|g')"
session_dir="$HOME/.claude/projects/-${proj_slug}"
if [[ -d "$session_dir" ]]; then
  if grep -lE "plan-ceo-review|office-hours" "$session_dir"/*.jsonl 2>/dev/null | head -1 | grep -q .; then
    project_uses_gstack=true
    evidence+=("session-history:$session_dir/*.jsonl")
  fi
fi

# ---- emit JSON ----
ev_json="$(printf '%s\n' "${evidence[@]:-}" | jq -R . | jq -cs '. | map(select(. != ""))')"
jq -cn \
  --arg pd "$PROJECT_DIR" \
  --argjson gi "$gstack_installed" \
  --argjson pu "$project_uses_gstack" \
  --argjson ev "$ev_json" \
  '{project_dir:$pd, gstack_installed:$gi, project_uses_gstack:$pu, evidence:$ev}'
