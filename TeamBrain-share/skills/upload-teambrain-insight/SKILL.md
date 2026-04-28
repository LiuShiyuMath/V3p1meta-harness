---
name: upload-teambrain-insight
description: Add a team insight to TeamBrain-share and import it into TeamAgent. Trigger when the user says "记录这个坑", "share this insight", or "upload teambrain insight".
---

# Upload TeamBrain Insight

Use this when the user wants to capture a lesson for teammates.

Run:

```bash
bash /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/add-insight.sh \
  --name "..." \
  --when "..." \
  --description "..."
```

The script updates the LAN index, attempts peer merge, then attempts TeamAgent import.
