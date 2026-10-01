# MEMORY.md — aesop-xi
Durable facts about this repo. Dated; newest first. Updated at session wrap-up.

## 2026-10-01
- Canonical home of the phone's Claude Code hooks: `deploy/phone/hooks/` (gitleaks dispatcher, secret-guard, resume-gate, ENFORCEMENTS, git-gate, ship-session v2, session-ledger, sync-on-use, housekeeping-check). Live copies: `~/.claude/hooks/`.
- Shortcuts `deploy/phone/bin/` (npu-ask, models, ai-web, ai-stop, talk); guide `docs/LOCAL-AI-GUIDE.md`; NPU facts `docs/NPU-ON-DEVICE.md`; tooling audit `docs/INVENTORY.md`.
- Temporary home for the operator's custom skills (`skills/obsidian-vault`, `skills/corpus-*`, termux-helper, aesop-voice-pipeline); final home decided at the grill.
- Git flow: commit on local branches mid-session; everything ships at wrap-up; PR branches are deleted after merge (repo auto-delete on). CLAUDE.md updated accordingly.
- Port plan: NPU app 8080, geniex serve 18181, llama-server 8081, media 8091, aesopd bridge 8765, MemVault 8092.
- The dead `Novus-Agenti` submodule link was removed (the repo is 404; local copy in the operator's salvage yard).
- PR #18 (orchestration contract v0.1) is held for the grill session.
- The local `.git/hooks/post-commit` runs the vault's `tools/regenerate_masters.sh` (the old `~/repos/NovAExorpus` clone is gone).
