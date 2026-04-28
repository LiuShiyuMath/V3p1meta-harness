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

---

## 2026-04-28 GateGuard PreToolUse Hook E2E (worktree --plugin-dir)

```text
                 ┌─────────────────────────────────┐
                 │  claudefast --plugin-dir <DIR>  │
                 └─────────────┬───────────────────┘
                               │
                               ▼
            CLAUDE_PLUGIN_ROOT = <DIR>  (env injected by Claude Code)
                               │
                               ▼
   hooks.json command "node ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/gateguard-fact-force.js"
                               │
                               ▼
                  PreToolUse on Edit|Write|MultiEdit
                               │
              first time on a file ─┴── second time same session
                       │                        │
                       ▼                        ▼
              {permissionDecision: deny}    rawInput (allow)
              [Fact-Forcing Gate]           file gets written
```

### Lesson: `--plugin-dir` accepts ANY path that contains a valid plugin layout

A worktree path is a fully valid `--plugin-dir` argument. You do NOT need to:

- merge the branch into `main`,
- register the plugin in `~/.claude/plugins/installed_plugins.json`,
- publish to a marketplace.

As long as the directory has `.claude-plugin/plugin.json` and the hooks/skills
referenced in it, Claude Code loads it for that session only.

### The portable path convention

`hooks/hooks.json` MUST use `${CLAUDE_PLUGIN_ROOT}` instead of hardcoded absolute paths.
Claude Code sets `CLAUDE_PLUGIN_ROOT` in each hook subprocess's env to the plugin's
install directory; the shell expands it at exec time.

```jsonc
// good — portable across users, machines, and worktree vs. main checkout
"command": "node ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/gateguard-fact-force.js"

// bad — locks the hook to one filesystem path; breaks under worktrees
"command": "node /Users/m1/projects/V3p1meta-harness/TeamBrain-share/scripts/hooks/gateguard-fact-force.js"
```

### Reproducing the e2e test

```bash
# Use the worktree's TeamBrain-share directly (no merge / install needed):
cd /Users/m1/projects/V3p1meta-harness/.claude/worktrees/force-hooks
claudefast --plugin-dir "$PWD/TeamBrain-share" \
           --permission-mode acceptEdits \
           --dangerously-skip-permissions \
           -p "Use the Write tool to create /tmp/test.py whose content is exactly: hello-word"
```

### What you should observe

| signal                                                | where to look                              |
|-------------------------------------------------------|--------------------------------------------|
| Plugin loaded as `teambrain-share@0.1.0`              | startup banner / `/plugins`                |
| PreToolUse fired on the first Write                   | `~/.gateguard/state-<sid>.json` lists path |
| First write attempt denied with `[Fact-Forcing Gate]` | model's response or `--debug hooks` log    |
| Second write same session allows                      | file appears with the requested bytes      |

### Run #1 (cold gate) — observed behavior

The PreToolUse hook fires correctly and writes the gateguard state file:

```json
// /tmp/gateguard-e2e/state-<session-uuid>.json after run #1
{
  "checked": ["/tmp/test.py", "__bash_session__"],
  "last_active": 1777358585673
}
```

But `-p` print-mode agents do NOT always retry after the deny — they may
report the gate as a permission failure to the user instead of presenting
the four facts and re-issuing the Write. This is a property of the agent
loop, not of the hook.

### Run #2 (pre-warmed gate) — file gets created

To force the gate to allow the first attempt, pre-seed the state file with a
fixed session id:

```bash
SID=e2e-prewarmed-session
mkdir -p /tmp/gateguard-e2e
cat > /tmp/gateguard-e2e/state-${SID}.json <<JSON
{"checked":["/tmp/test.py","__bash_session__"],"last_active":$(date +%s)000}
JSON

GATEGUARD_STATE_DIR=/tmp/gateguard-e2e \
CLAUDE_SESSION_ID=$SID \
claudefast --plugin-dir /Users/m1/projects/V3p1meta-harness/.claude/worktrees/force-hooks/TeamBrain-share \
           --permission-mode acceptEdits \
           --dangerously-skip-permissions \
           -p "Use the Write tool to create /tmp/test.py whose content is exactly: hello-word"
```

Observed:

```text
$ xxd /tmp/test.py
00000000: 6865 6c6c 6f2d 776f 7264                 hello-word
```

10 bytes, exactly `hello-word`, no newline. Plugin loads, hook fires, gate
allows, file gets written.

### macOS gotcha — `date +%s%3N` does not yield milliseconds on BSD `date`

On macOS the `%3N` token is left literal (`17773586913N` instead of
`1777358691300`). Either use `$(date +%s)000` or `python3 -c 'import time; print(int(time.time()*1000))'`
when seeding `last_active`. The gate tolerates a malformed timestamp by
falling through to a fresh-state default, which is why run #2 still passed.
