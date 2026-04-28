# Setup

## Install TeamAgent

```bash
npm install -g teamagent
teamagent init
teamagent doctor
```

## Install Plugin

```bash
ln -s /Users/m1/projects/V3p1meta-harness/TeamBrain-share ~/.claude/plugins/teambrain-share
```

## Configure Teammates

```bash
mkdir -p ~/.claude-teambrain-share/config
cp /Users/m1/projects/V3p1meta-harness/TeamBrain-share/config/teammates.example.json ~/.claude-teambrain-share/config/teammates.json
```

Edit IPs and usernames in `~/.claude-teambrain-share/config/teammates.json`.

## Validate

```bash
bash /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/doctor.sh
```

## Add Insight

```bash
bash /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/add-insight.sh \
  --name "Avoid destructive rsync push" \
  --when "Syncing peer knowledge indexes" \
  --description "Use merge with backups instead of overwrite push."
```
