---
name: sync-teambrain-share
description: Sync TeamBrain-share LAN insights with teammates and import merged insights into TeamAgent. Trigger when user says "sync teambrain", "同步 TeamBrain", or "sync shared insights".
---

# Sync TeamBrain Share

Run:

```bash
bash /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/rsync-merge.sh
bash /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/teamagent-import.sh
```

This preserves LAN propagation while TeamAgent handles local retrieval and enforcement.
