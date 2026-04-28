# Verification

## 2026-04-28 claudefast Plugin Load Check

Help command:

```bash
claudefast -h
```

Relevant options confirmed:

- `-p, --print`
- `--output-format stream-json`
- `--include-hook-events`
- `--plugin-dir <path>`
- `--verbose`

Important CLI behavior:

```text
When using --print, --output-format=stream-json requires --verbose
```

Working command:

```bash
claudefast -p \
  --verbose \
  --output-format stream-json \
  --include-hook-events \
  --plugin-dir /Users/m1/projects/V3p1meta-harness/TeamBrain-share \
  '请只回答一行 JSON：{"plugin":"teambrain-share","loaded":true,"skills":["upload-teambrain-insight","sync-teambrain-share","import-teamagent-insights","query-teambrain-share"]}'
```

Observed stream-json evidence:

- `plugins` included `teambrain-share` with path `/Users/m1/projects/V3p1meta-harness/TeamBrain-share`.
- `slash_commands` included:
  - `teambrain-share:import-teamagent-insights`
  - `teambrain-share:query-teambrain-share`
  - `teambrain-share:sync-teambrain-share`
  - `teambrain-share:upload-teambrain-insight`
- `skills` included the same four TeamBrain-share skills.
- `agents` included `teambrain-share:teambrain-router`.
- Final result returned:

```json
{"plugin":"teambrain-share","loaded":true,"skills":["upload-teambrain-insight","sync-teambrain-share","import-teamagent-insights","query-teambrain-share"]}
```

Note: A user-level Stop hook appended a laziness self-report request during the test. That was external to this plugin; it did not prevent plugin loading or skill discovery.
