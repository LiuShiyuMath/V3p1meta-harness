# Architecture

## Responsibilities

TeamBrain-share owns peer-to-peer transport and attribution. TeamAgent owns local reasoning and enforcement.

## Data Flow

```text
add-insight.sh
  -> ~/.claude-teambrain-share/insights/index.json
  -> rsync-merge.sh
  -> teamagent-import.sh
  -> teamagent ingest --from-insights
```

Session start runs a best-effort sync and import. User prompt submit runs a lightweight LAN index fallback query. TeamAgent's own hooks should be installed with `teamagent init` for semantic injection and tool guardrails.

## Why Not Full Replacement

TeamAgent team scope is not mature yet. The plugin keeps LAN sync because peer-to-peer sharing is the part TeamAgent does not currently replace.

## Failure Policy

All hook scripts are best effort. Missing TeamAgent, unreachable peers, malformed remote indexes, and import failures are logged without blocking Claude Code.
