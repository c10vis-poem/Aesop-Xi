# PENDING.md — aesop-xi

Durable cross-session backlog. Not rewritten each session — items persist until resolved or explicitly dropped.

## Blocking / decisions needed

- **[P0] OmniRoute deploy to Google Cloud VM.** Operator decided 2026-09-15: Google Cloud VM is the target. Needs: OmniRoute installed + configured on VM, port 20128 reachable from phone, `tools/omniroute/start.sh` updated to point at VM endpoint instead of localhost, env var `OMNIROUTE_URL` set in `~/.omniroute/.env`.

## Wiring work

- **[P1] OmniRoute runtime code** into `tools/omniroute/` + `skills/omniroute/` — config pointing at Google Cloud VM once deployed.
- ~~**[P1] terrestrial-brain server bring-up.**~~ **DONE 2026-09-15.** Database `terrestrial_brain` created, 23 migrations applied (22 clean, 1 non-fatal warning on postgres role grant), MCP server running on `localhost:8000/mcp` via system deno. Env vars `TB_MCP_URL` and `TB_MCP_KEY` set in `~/repos/NovA-terrestrial-brain/local-mcp/.env.local`.
- **[P1] Obsidian plugin** pointed at localhost terrestrial-brain endpoint (`localhost:8000`) — kicks off vault ingestion (7,307 files in `Documents/NovAExorpus/`).
- **[P1] Hook scripts per engine** — `~/.claude/hooks/` (Claude Code PreToolUse/PostToolUse), `~/.codex/hooks/` (Codex), dsh Cordis plugin. Source from `aesop-xi/skills/omniroute/hooks/{claude-code,codex,dsh}/`.
- **[P2] Reasoning Bank ledger scripts** under `tools/reasoning_bank/`. Trajectories flush to `NovAExorpus/05_episodic_logs/`.
- **[P2] Continual Harness** supervisor scripts under `tools/continual_harness/`.

## Deferred to post-grill

- **Novus-Agenti nested checkout at `~/repos/aesop-xi/Novus-Agenti/`.** Not a registered git submodule (no `.gitmodules`), just a dirty embedded `.git`. Upstream repo (`c10vis-poem/Novus-Agenti`) deleted from GitHub. No touching until post-grill.
- **Any repo-shape decisions** — deferred to post-grill.

## Other

- **ECC plugin never installed** (`~/repos/ECC-aesop`) — ready-to-go `.claude-plugin/plugin.json`, not active. Deferred.
- **novus-aeyre PR 6** (memory reference + bootstrap wrapper) queued auto-merge — verify it landed next session.
- **mem0 CLI plugin API key** was broken from Sep 9–15 (key written to wrong dir). Fixed: key now at `~/.claude/plugins/data/mem0-mem0-plugins/api-key`. Verify with `mem0:status` every session.
