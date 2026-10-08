# INVENTORY — existing scripts, hooks, skills (check BEFORE building anything new)

Audited 2026-10-01 (read-only: syntax checks and code reads, nothing executed). Full tables:
- Device scripts, git hooks, ~/bin: `~/.claude/session-work/2026-10-01/inventory-code.md` (~57 rows)
- Vault scripts: `~/.claude/session-work/2026-10-01/inventory-vault-scripts.md` (74 rows)
- Skills: `~/.claude/session-work/2026-10-01/inventory-skills.md` (61 skills)
- Live Claude hooks: `~/.claude/hooks/README.md` (also `aesop-xi/hooks/`)

## Rule
Before writing a new hook, script, skill or tool: search these tables for one that already does the job, overlaps it, or that the new one would break. Reuse or fix it first. Add a row here when something new is created.

## Already-built capabilities (don't rebuild)
| Capability | Use this | Old/overlapping (don't use) |
|---|---|---|
| Fork sync | `hooks/sync-on-use.sh` | `~/bin/sync-forks.old`, bootstrap.sh git-sync step |
| Ship / PR / merge | `hooks/ship-session.sh` (v2) + `WRAP-UP.md` | `~/bin/ship-session.old`, `merge-mem0` (`--admin` bypass), `fix-tb-check` |
| Secret scanning | `~/.config/git/hooks/dispatch` (gitleaks) + `hooks/secret-guard.sh` | — |
| Tool / rule enforcement | `hooks/enforce-*.sh` + `ENFORCEMENTS.md`, `hooks/git-gate.sh` | `tool_call_interceptor.py`, `divergence_detector.py` (never wired) |
| Session handoff | `hooks/resume-gate.sh`, `context-diff.sh`, `session-ledger.sh` | — |
| Voice | `vv`, `speak` | `v-listen`, `v-speak`, `voicebot` |
| NPU inference | GenieX `~/tools/geniex-bench` (see `NPU-ON-DEVICE.md`) | `~/tools/llama-hexagon`, `~/tools/llama-mixed` (CPU fallback) |

## Known broken / stale (fix list, 2026-10-01)
- Dead path `~/novae-xorpus`: `~/bin/nx`, `aesop-xi/tools/run_audit.sh`, NovAExopia/aesop-xi .py tools, skills corpus-verify and corpus-batch-processing
- Dead path `~/aesop` (dangling symlink): `~/bin/voice-transcribe.sh`, `aesop-xi/deploy/phone/boot.sh`, `install-daemons.sh`
- Deleted clone `~/repos/NovAExorpus`: aesop-xi `post-commit` hook, `aesop-tmux.sh`, `setup-graph-pipeline.sh` (vault tools/launch.sh, vm-reconnect.sh and .gemini hooks fixed 2026-10-01)
- Gone ECC cache 2.2.0: `~/.local/bin/ecc-dashboard`, `~/.local/bin/nanoclaw`
- `~/bin/ax`: missing `aesop-xi/config/stack-manifest.sh`
- Vault `run_audit.sh` copies have CRLF line endings
- `smart-grep-hook.sh` claims to be in settings.json but isn't
- Skills: corpus-verify frontmatter (`trigger:` → `description:`); duplicate cleanmyharness / clean-my-ai-harness; vault task-observer copy is an older fork; vault skills triplicated
