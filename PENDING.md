# PENDING.md — aesop-xi

Durable cross-session backlog. Not rewritten each session — items persist until resolved or explicitly dropped.

## Added 2026-10-02

- **npu-serve:** tool calls (OpenAI `tools`) not wired; only the first image per message is used; InternVL 2B (8 Elite and X Elite bundles, both unpacked in Models/installed) not in models.json yet — X Elite build ran 27.5 tok/s here. Kokoro TTS script `deploy/phone/tts_speak.py` fails on the multi-lang v1.0 model (needs lexicon/lang) — operator said leave it for now.
- **Hooks for other agents:** Hermes / dsh don't get H1–H7 (grill topic).

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

## 2026-10-24
- **ECC entries in `.claude/settings.json`** (two PostToolUse hooks: `session-activity-tracker.js || true` and an LLM `prompt` hook on every Bash call): ECC is not installed, so one is a no-op and the other spends a model call per Bash command for nothing. Operator decides whether to remove them (nothing is turned off without the operator naming it).
- **gitleaks in cloud sessions:** the cloud container has no `gitleaks` binary, so the pre-commit secret scan (`git-hooks/dispatch`) and the two ship test suites cannot run there. Add it to the cloud environment setup script, or accept CI as the only secret gate for cloud commits.
- **Stale references to the dropped stack** (OmniRoute, mem0, Terrestrial Brain): `deploy/gcp-vm/`, `deploy/jetson/`, `profiles/nav.yaml`, `ARCHITECTURE.md`, `tools/omniroute/`, and `PENDING.md` "Blocking / Wiring work" items above. Mark superseded or delete (operator).
- **Hook 3** (newest sessions across projects at SessionStart) still undecided; the opening ledger (`state/opening-<sid>.tsv`) now gives a place to record it if built.
- **Plugin/skill cross-comparison** (2026-10-24, vault `audit/`): 13+ memory plugins, 5 wiki plugins, 3 task-observer copies and 2 pge copies overlap the aesop-xi discipline; consolidation list awaits the operator's choices.

## 2026-10-23
- mem0, OmniRoute, Terrestrial Brain and ECC items above are moot for mem0/OmniRoute/TB (dropped by the operator 2026-10-23).
- Hook 3 (list newest sessions across all `~/.claude/projects/*` at SessionStart; vault obs 0012): operator undecided, not built.
- Checks proposed by vault observations 0038-0041: value review before offering deletes; never bundle a turn-off; subagent scope clause or a touched-files check at SubagentStop; encode delete ordering inside commands.
- `run-hook.sh` cloud allowlist does not include the #76/#77 hooks (left out on purpose; decide whether cloud sessions need them).
## 2026-10-28
- Re-engineer the hooks before turning any back on (operator order; all stubbed 2026-10-28). Start with resume-gate (obs 0051). Decide whether the gitleaks git hook stays on.
- Install the `intake` skill after merge (link `skills/intake` into `~/.claude/skills`) and run it on a real dictated prompt.
- Build pipeline stages 1-4 (context fan-out, orchestrator with Jev, proposal, auditor) per `docs/intake-pipeline-spec.md`.
