# TeamBrain-share

LAN knowledge sharing plugin that keeps `insights-share` style teammate sync and uses TeamAgent CLI as the local rule engine.

## Positioning

TeamAgent is the brain:

- local SQLite knowledge base
- semantic retrieval
- prompt injection
- PreToolUse warn/block
- PostToolUse feedback
- Stop-time learning and calibration

TeamBrain-share is the propagation layer:

- LAN teammate config
- bidirectional rsync merge
- uploader and source attribution
- import adapter into TeamAgent

## Setup

```bash
mkdir -p ~/.claude-teambrain-share/config
cp TeamBrain-share/config/teammates.example.json ~/.claude-teambrain-share/config/teammates.json
npm install -g teamagent
teamagent init
```

Install this plugin by linking or copying `TeamBrain-share` into your Claude Code plugins directory.

## Main Commands

```bash
bash TeamBrain-share/scripts/doctor.sh
bash TeamBrain-share/scripts/add-insight.sh --name "Title" --when "Situation" --description "Lesson"
bash TeamBrain-share/scripts/rsync-merge.sh
bash TeamBrain-share/scripts/teamagent-import.sh
```

## Data

```text
~/.claude-teambrain-share/
  config/teammates.json
  insights/index.json
  insights/raw/
  cache/
  logs/
```

`index.json` is normalized to:

```json
{ "insights": [] }
```

## Integration Contract

LAN sync owns shared transport. TeamAgent owns local intelligence. The adapter exports LAN insights to TeamAgent's `--from-insights` ingest format.
