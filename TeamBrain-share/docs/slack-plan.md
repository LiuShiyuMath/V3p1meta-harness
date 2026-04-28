# TeamAgent + LAN Share Plan

## Decision

Use TeamAgent CLI to replace most local knowledge-engine logic, but keep LAN sync in the plugin.

```text
TeamAgent = brain
TeamBrain-share = LAN propagation
```

This should replace about 70% of our custom logic: digest, structured rules, semantic retrieval, prompt injection, tool-call guardrails, calibration, and diagnostics.

## Evidence

TeamAgent already provides `init`, `doctor`, `stats`, `analyze --commit`, `compile`, `pitfall`, and `review`.

It has stronger hook coverage than the current plugin:

- `PreToolUse`: semantic matcher with keyword fallback.
- `UserPromptSubmit`: embedding + sqlite-vec retrieval + context injection.
- `PostToolUse`: feedback event logging.
- `Stop`: analyze, calibrate, compile pipeline.

Verified locally in `/tmp/TeamBrain`:

```text
pnpm typecheck  pass
pnpm test       147 files / 1390 tests passed
pnpm build      pass
pnpm verify     5/5 scenarios, PRR 100.0, KP 5.00/5
```

TeamAgent should not replace LAN sync yet. Its `DualLayerStore` supports personal and global layers, but team-scoped entries are still Phase 4 and currently throw.

The current plugin's unique value is LAN sharing:

- teammate config
- rsync transfer
- source attribution
- raw content preservation
- peer-to-peer operation without a server

## Architecture

```text
manual insight / session digest
        ↓
TeamBrain-share index.json
        ↓
rsync merge with teammates
        ↓
TeamAgent ingest adapter
        ↓
.teamagent/knowledge.db + ~/.teamagent/global.db
        ↓
TeamAgent hooks
```

## Phases

1. Normalize index schema to `{ "insights": [] }`.
2. Add adapter exporting LAN insights to TeamAgent `--from-insights`.
3. Import after upload, digest, and sync.
4. Keep query fallback for machines without TeamAgent.
5. Enable TeamAgent hooks through `teamagent init`.
6. Later, revisit full merge if TeamAgent team scope becomes stable.

## Success Criteria

- LAN insight sync still works.
- Synced insight imports into TeamAgent DB.
- User prompts can receive semantic TeamAgent matches.
- High-confidence rules can warn or block in `PreToolUse`.
- Plugin doctor and TeamAgent verify both pass.
