# RESUME.md — Aesop-Xi (orchestration repo)

**Last updated: 2026-10-23** (phone, Claude Code; wrap-up of session 7cb1c8c0, 2026-10-18 to 2026-10-23). Vault-wide plan: `NovAExorpus/RESUME.md` START HERE.

## STATE
- **Hooks** (`hooks/`, live copies in `~/.claude/hooks/` on the phone, equal to main): H1-H9, auditor (`hooks/auditor/`, Stop `type: agent`, reads the transcript 8 lines at a time), absence-gate, state-guard, settings-guard, build-doc-gate, agent-type-gate, delegation-tripwire, SubagentStop progress-file gate, observer event enforcement, staged-updates notice. All 22 hook test suites pass at #77. `hooks/README.md` is the table of every hook.
- **Ship path:** repos ship through `ship-session.sh` (branch, commit, gitleaks, PR, auto-merge); the vault ships through `vault-ship.sh` (commits, pushes `vault-sync`, PR to `main` with auto-merge). ship-session never ships the vault.
- **No open PRs.** PR #18 (orchestration contract v0.1) merged 2026-10-22.
- **Dropped by the operator 2026-10-23:** OmniRoute, mem0, Terrestrial Brain, OpenWiki, Qwen3-VL. AGENTS.md runtime-memory sections point to the vault instead.
- **NPU:** GenieX v0.9.3 proof run 2026-10-23 is recorded in the Æsc repo (`AEthX-AEsc/docs/npu-proof/2026-10-23.md`), not here.

## WHAT LANDED 2026-10-18 to 2026-10-23 (all merged to main)
- Gates: #53 H9 stop gate refuses re-deferring a carried-over START HERE item; #54 run-hook stands down phone-only gates in cloud sessions; #57 and #61 git-gate (quoted text ignored; "push now" lasts the session, "hold push" revokes); #62 branch-current-gate allows the merge that brings main in; #64 and #67 check-in parsing and reporting; #71 H7 tells a mention from a command.
- New hooks: #56 observer event enforcement; #59 SubagentStop progress-file gate; #69 staged skill updates surfaced at session start; #72, #74, #75 Stop auditor; #76 absence-gate; #77 state-guard, settings-guard, build-doc-gate, agent-type-gate, delegation-tripwire.
- Other: #55 and #66 tests; #58 change-log classifies the keep under any spelling; #60 NvAEx- repo names; #63 terrestrial-brain is not OB1; #65 stale VM IP dropped; #68 Kokoro TTS lexicons and WAV via sherpa-onnx; #70 aesopd/llamad token and Origin auth, frame cap, localhost bind; #73 Qwen3-VL dropped as the example model; #78 AGENTS, MEMORY, PENDING for 2026-10-23.

## NEXT
1. Checks proposed by vault observations 0038-0041 (see PENDING.md 2026-10-23).
2. Decide whether cloud sessions need the #76/#77 hooks (`run-hook.sh` allowlist leaves them out on purpose).
3. npu-serve: tool calls, multiple images per message, InternVL 2B in `models.json` (PENDING.md 2026-10-02).

## Sources read for this file
This repo's RESUME.md (old), PENDING.md, MEMORY.md (2026-10-01 to 2026-10-23 sections), `hooks/` listing, the merged PR titles #53-#78 (`gh search prs`), `gh pr list --state open` (none). Vault: `RESUME.md`, `~/.claude/hooks/README.md`, observations 0042 and 0043. Not read: AGENTS.md this session, the PR bodies and diffs, `hooks/` sources, `docs/`, `deploy/`, `skills/`, `tools/`.
