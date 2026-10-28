# RESUME.md — Aesop-Xi (orchestration repo)

**Last updated: 2026-10-24** (cloud session, Claude Code, Fable 5.1, session `01XvfbJ2`; branch `hooks/cloud-write-checklists`). Vault-wide plan: `NovAExorpus/RESUME.md` START HERE.

## STATE
- **Hooks** (`hooks/`, live copies in `~/.claude/hooks/` on the phone): H1-H9, auditor, absence-gate, state-guard, settings-guard, build-doc-gate, agent-type-gate, delegation-tripwire, SubagentStop progress-file + scope gate, observer event enforcement, staged-updates notice, change-log + review + `/ok push`. **New 2026-10-24:** `hooks/lib/env.sh` (shared paths, cloud flag, advise-once), `run-hook.sh` watchdog + fail-open (no stand-down anywhere), `/write` check-in verb, Opening O1-O6 and Wrap-up W1-W8 checklists in the Stop gate, RESUME drift + date checks, change-log and observe-event registered. 30 test suites; 28 pass in the cloud container, the two ship suites need `gitleaks` (CI installs it).
- **Ship path:** repos ship through `ship-session.sh`; the vault through `vault-ship.sh`; the Stop gate (W6) refuses to close with an uncommitted vault.
- **Phone install pending:** the phone's `~/.claude/hooks/` copies are the pre-#78 versions until the operator copies `hooks/*.sh` + `hooks/lib/` over and merges the two new `settings.hooks.json` groups (change-log, observe-event) into `~/.claude/settings.json` as `!` commands (settings-guard).
- **Dropped by the operator 2026-10-23:** OmniRoute, mem0, Terrestrial Brain, OpenWiki, Qwen3-VL. Stale references listed in PENDING.md 2026-10-24.
- **NPU:** GenieX v0.9.3 proof run recorded in `AEthX-AEsc/docs/npu-proof/2026-10-23.md`, not here.

## WHAT LANDED 2026-10-24
- Hook rebuild for cloud sessions and the operator's check-in verbs (this branch, PR to main): lib/env.sh, run-hook.sh, resume-gate.sh, checkin-gate.sh, enforce-prompt.sh, stop-gate.sh, subagent-stop-gate.sh, state-guard.sh, settings.hooks.json, .claude/settings.json, tests (cloud-run, checkin-gate, resume-gate, stop-sequence, extended checkin/subagent/state-guard), CI `hook-tests` job, README/WRAP-UP/ENFORCEMENTS/AGENTS/MEMORY/PENDING.
- Companion deliverables in the vault (`NovAExorpus`, branch of the same date): assets-and-capabilities audit, plugin/skill cross-comparison, Fable orchestrator agent, wiki-admin agent + skill, 3-APK Compose stack design, recursive cognitive pipeline and enterprise config.

## NEXT
1. Operator: install the new hook copies on the phone (see STATE) and decide the ECC `PostToolUse` entries and the stale-stack files (PENDING.md 2026-10-24).
2. Operator: `/write` acceptance: try `/write 1 <text>` on a real START HERE plan and confirm the `OPERATOR WROTE:` line and the rewritten snapshot behave as wanted.
3. Add `gitleaks` to the cloud environment setup script so cloud commits get the pre-commit scan (PENDING.md).
4. npu-serve: tool calls, multiple images per message, InternVL 2B in `models.json` (PENDING.md 2026-10-02).

## Sources read for this file
This repo: AGENTS.md, RESUME.md (old), PENDING.md, MEMORY.md, hooks/README.md, hooks/WRAP-UP.md, hooks/ENFORCEMENTS.md, every hook source under `hooks/`, every test under `hooks/tests/`, `.claude/settings.json`, `.github/workflows/ci.yml`, deploy/phone/bin/resume-item and observe-dismiss. Vault: AGENTS.md, RESUME.md, PENDING.md, observations 0038-0044, handoff/2026-10-23 (via subagent). Drive: the `_#building-the-dumbass…` and `_PENDING.md` folders (directly and via four reader subagents). Not read: `docs/`, `deploy/` beyond `phone/bin`, `skills/`, `tools/`, the auditor hook sources.
