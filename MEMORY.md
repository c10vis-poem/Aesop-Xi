# MEMORY.md — aesop-xi
Durable facts about this repo. Dated; newest first. Updated at session wrap-up.

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
