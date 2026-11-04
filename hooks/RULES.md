# RULES — the whole list

Ten rules. Each is enforced by exactly one hook, each hook has an override verb and a kill switch.
Nothing here is advisory prose; if it is not in this table it is not a rule.

| # | Rule | Hook (event) | Override (operator types it) | Revoke |
|---|------|--------------|------------------------------|--------|
| 1 | Read RESUME.md before any tool runs | resume-gate (PreToolUse *) | `#skip-resume` | `gate off resume-gate` |
| 2 | No state change before the operator checks in: `/ok`, `/ok 1-4`, `/defer N`, `/reject N`, `/write N text` | checkin-gate (PreToolUse *) | any check-in verb, or `#skip-checkin` | `gate off checkin-gate` |
| 3 | Secrets never printed unredacted; git hooks never skipped | secret-guard (PreToolUse Bash,Read) | `#show-secret <path>` for one call | `gate off secret-guard` |
| 4 | Agent cannot edit `~/.claude/settings*.json`, `~/.claude.json`, or `~/.claude/state` | settings-guard + state-guard (PreToolUse Bash,Edit,Write) | none for the agent; operator edits with a `!` line | `gate off settings-guard` |
| 5 | No edits or commits on a branch behind `origin/<default>` | branch-current-gate (PreToolUse Bash,Edit,Write) | `#skip-branch` | `gate off branch-current-gate` |
| 6 | ENFORCEMENTS.md rows must be satisfied for the prompt before other tools run | enforce-gate (PreToolUse *) | `#skip-enforce` | `gate off enforce-gate` |
| 7 | Turn cannot end with opening (O1-O6) or wrap-up (W1-W8) steps missing | stop-gate (Stop) | `#skip-stop` or `/wrapup-defer N why: ...` | `gate off stop-gate` |
| 8 | No "not found / doesn't exist" answer without a search this turn | absence-gate (Stop) | `#skip-absence` | `gate off absence-gate` |
| 9 | Every repo touch, file write and commit is logged to the session ledger | session-ledger (PostToolUse) | n/a (log only, never blocks) | `gate off session-ledger` |
| 10 | Scratchpad archived and session shipped to NvAEx-Recaps at end | archive-scratchpad + ship-session (SessionEnd, PreCompact) | `#no-ship` | `gate off ship-session` |

## Three guarantees every hook honors

1. **Immutable to the agent.** Hooks live in settings.json (user scope, synced). Rule 4 stops the agent from touching that file. Only the operator changes it.
2. **Never a bare yes/no.** A block message always names: what was blocked, why, the override verb for this one call, and the revoke command. The operator picks.
3. **Revocable any time, mid-session.** `gate off <name>` creates `~/.claude/state/off/<name>`; `gate on <name>` removes it; `gate off all` / `gate on all`; `gate status` lists. Hooks check that directory first and exit 0 if their file exists. No restart, no settings edit.

## What is NOT a rule any more (dropped from the 27-hook set)

sync-on-use, build-doc-gate, agent-type-gate, delegation-tripwire, change-log, context-diff, housekeeping-check, staged-updates, observe-event (×5 registrations), subagent-stop-gate, enforce-prompt, ci-ready, carryover. They stay in `hooks/` as scripts; they are not wired. Re-add one by adding a row here first.

## Known defect before enabling rule 1

obs 0051: resume-gate loops when subagents run in other repos (compares vault RESUME against repo hash). Fix: snapshot per agent and per RESUME path, content hash, never block Read. Until fixed, rule 1 ships `gate off resume-gate` by default.
