# MEMORY.md — aesop-xi
Durable facts about this repo. Dated; newest first. Updated at session wrap-up.

## 2026-10-24
- **Cloud rule (operator):** the hooks are never disabled anywhere; cloud sessions run every gate with the same rules. `run-hook.sh` no longer stands phone-only gates down; it runs each hook under a watchdog (`AESOP_HOOK_TIMEOUT`, 8 s) and fails open on a crash or timeout, logged to `~/.claude/state/hooks.log`. `hooks/lib/env.sh` resolves `VAULT`/`ST`/tool bins on both devices (vault found by origin URL in the cloud; cached in `state/vault-path`).
- **Operator check-in has a third verb:** `/write N <text>` rewrites item N in the session snapshot with the operator's words (recorded in `state/written-<sid>.tsv`, surfaced as `OPERATOR WROTE:`); `/write <text>` adds a new item; ranges `/ok 1-4` and `/ok all` work. `/edit` and `/rewrite` are aliases.
- **Stop gate is two named checklists** (Opening O1-O6, Wrap-up W1-W8); each missing step is named in the block reason. Fixed: RESUME "rewritten" compared the vault file against the repo's hash (never matched) — now the file that was read, plus today's date required in its first 40 lines, plus the vault RESUME; deferred items accepted in the repo's PENDING.md as well as the vault's; the "vault exempt: GitSync" rule is gone (uncommitted vault → vault-ship, obs 0043); `#skip-enforce`/`#staged-defer` inside a subagent hand-back no longer count.
- **resume-gate** re-checks RESUME's hash on every call and blocks once when another session rewrote it (obs 0044), records opening reads (AGENTS/PENDING/MEMORY/WRAP-UP) in `state/opening-<sid>.tsv`, and reports RESUME's own date (missing / future / older than 14 days).
- **checkin-gate** judges Bash by the commands that run (quotes, heredocs and comments stripped, obs 0042), allows StructuredOutput/task tools/AskUserQuestion/Explore+Plan subagents, and counts interpreter runs as changes (obs 0044). **subagent-stop-gate** enforces a declared scope (obs 0040). **state-guard** also blocks interpreter / `sh -c` runs that name the state dir.
- `change-log.sh` and `observe-event.sh` were never registered in either settings file; both are now (repo `.claude/settings.json` also gained SubagentStop). The two ECC `PostToolUse` entries in `.claude/settings.json` are dead weight (ECC uninstalled 2026-09-09; one is an LLM `prompt` hook per Bash call) — left in place, operator decides.
- Tests: 30 suites; CI now runs them (`hook-tests` job: Termux-shebang shim + gitleaks). Locally the two ship suites need the `gitleaks` binary; the cloud container has none, so they fail there for that reason only.
- Operator tooling decision 2026-10-24: Jev (TypeSafe Jev Router) with REA will strip the forked repos into asset-based marketplaces; `api.typesafe.ai` is a proxy-injected host in cloud sessions.

## 2026-10-05
- **AGENTS.md is the only instruction file** (CLAUDE.md content merged in and deleted; Claude Code reads AGENTS.md natively). Merged rule conflicts: newest wins (delete branches after merge).
- **The local `.git/hooks/post-commit` was removed** (operator). It made the vault's `MASTER-*.md` with only paths + a timestamp, which caused GitSync conflict copies. The master files are now built on GitHub (vault `master-files.yml`); this repo's `.github/workflows/notify-vault.yml` pings it when AGENTS.md/RESUME.md change on main (secret `VAULT_DISPATCH_TOKEN`).
- `hooks/stop-gate.sh`: in wrap-up mode it also checks each touched base repo for an updated MEMORY.md, an AGENTS.md, no tracked CLAUDE.md, and a changed vault PENDING.md (content compare vs origin).
- The subagent standing order (parallel spawn, model sizing, live progress files) is in AGENTS.md.

## 2026-10-02
- `deploy/phone/geniex-serve/`: npu-serve has a VLM path (`shim_load_vlm` / `shim_vlm_chat`, GenieX v0.7.1). models.json entries with `mmproj` or `"vlm": true` load as VLMs; OpenAI `image_url` parts (path, file://, data:, http) are accepted. QAIRT bundles: `path` must be `<bundle>/genie_config.json` (the plugin uses the parent dir), n_ctx and ngl 0.
- `deploy/phone/bin/npu-serve`: only the server is backgrounded (a backgrounded `cd && …` subshell used to hold the caller's stdout open); waits 240 s for big models. Default model path is `Models/gguf/Qwen3.5-2B-Q4_0.gguf` (npu-ask, ai-web too).
- `.claude/settings.json` registers H1–H7 via `hooks/run-hook.sh` (stands down when the global copy exists). Run hooks with `bash <script>` — Termux has no `/usr/bin/env` for hook processes.
- Wiki/doc toolkit lives in `~/wiki-admin` (not in this repo); guide in the vault `docs/WIKI-ADMIN-GUIDE.md`.

## 2026-10-01
- Canonical home of the phone's Claude Code hooks: `hooks/` (gitleaks dispatcher, secret-guard, resume-gate, ENFORCEMENTS, git-gate, ship-session v2, session-ledger, sync-on-use, housekeeping-check). Live copies: `~/.claude/hooks/`.
- Shortcuts `deploy/phone/bin/` (npu-ask, models, ai-web, ai-stop, talk); guide `docs/LOCAL-AI-GUIDE.md`; NPU facts `docs/NPU-ON-DEVICE.md`; tooling audit `docs/INVENTORY.md`.
- Temporary home for the operator's custom skills (`skills/obsidian-vault`, `skills/corpus-*`, termux-helper, aesop-voice-pipeline); final home decided at the grill.
- Git flow: commit on local branches mid-session; everything ships at wrap-up; PR branches are deleted after merge (repo auto-delete on). Recorded in AGENTS.md (was CLAUDE.md).
- Port plan: NPU app 8080, geniex serve 18181, llama-server 8081, media 8091, aesopd bridge 8765, MemVault 8092.
- The dead `Novus-Agenti` submodule link was removed (the repo is 404; local copy in the operator's salvage yard).
- PR #18 (orchestration contract v0.1) is held for the grill session.
- ~~The local `.git/hooks/post-commit` runs the vault's `tools/regenerate_masters.sh`~~ (removed 2026-10-05).

## 2026-10-08
- Hooks moved: `deploy/phone/hooks/` → `hooks/` (`git-hooks/`, `tests/` kept). `.claude/settings.json` runs them via `hooks/run-hook.sh`.
- New/changed hooks: H2 `sync-on-use.sh` blocks until the fork is synced; `change-log.sh` + `review-changes.sh` + `/ok push` gate every push; H8 `ci-ready.sh` (CI + required checks); `documents-guard` merged into change-log. Tests: change-log 20, sync-on-use 17, enforce 16.
- `hooks/tests/test-ship-v2.sh` fails 14/18 on origin/main as well (pre-existing, not yet fixed).
- `unresolved.md` retired; backlog home is `PENDING.md`. `raw/` got two condensed files from NovA-Corpus.

## 2026-10-23
- New hooks: auditor (`hooks/auditor/`, Stop `type: agent`; reads the transcript 8 lines at a time, 30 exceeded Read's 25k-token cap), absence-gate (#76), state-guard, settings-guard, build-doc-gate, agent-type-gate, delegation-tripwire (#77). All live on the phone. Installer used: `session-work/2026-10-23/install-new-hooks.sh` (idempotent; adds entries by command name, not by list position).
- settings-guard: agents cannot edit Claude Code settings files, so any future installer that registers hooks is run by the operator as a `!` command.
- The `test-ship-v2` note above is stale: all 22 hook test suites pass at #77.
- Dropped by the operator: OmniRoute, mem0, Terrestrial Brain, OpenWiki. The AGENTS.md runtime-memory sections were replaced with a pointer.
- Operator rule: nothing in any repo or config is turned off without the operator naming it (11 fork workflows were disabled and re-enabled the same day).
