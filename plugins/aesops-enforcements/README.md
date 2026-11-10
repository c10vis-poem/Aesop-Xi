# aesops-enforcements

The ten rules as one plugin, all on, on any device. `RULES.md` is the only rule text: ten rules, 14 hooks, 25 wirings on 9 lifecycle events. Enable the plugin and they run; nothing starts off.

## How it runs

`hooks/hooks.json` has one entry per lifecycle event, all `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-gate.sh" --event <Event>`. `run-gate.sh` reads `scripts/gates.tsv` and runs the matching hooks in order under a watchdog. A blocked tool call stops at the first block; every Stop hook gets its say.

| Event | Hooks |
|---|---|
| SessionStart (2) | session-start, observe-event |
| UserPromptSubmit (2) | enforce-prompt, observe-event |
| PreToolUse (9) | direction-gate, secret-guard, guard, push-gate, answer-gate, repo-gate, task-gate, session-log |
| PostToolUse (2) | session-log, task-gate |
| PostToolUseFailure (1), PermissionDenied (1) | observe-event |
| Stop (2) | stop-gate, answer-gate |
| SubagentStop (1) | stop-gate |
| SessionEnd (2) | session-log, ship-session |

## Operator controls

- `gate status` (also lists any repo whose settings turn hooks off), `gate off <hook>|all`, `gate on <hook>|all`. `bin/` is on the Bash tool's PATH while the plugin is enabled, so `! gate off stop-gate` works at the Claude prompt. In a plain terminal use the full path every block message prints.
- Kill switches, checked first: `~/.nvaex-hooks-off`, `~/.claude/state/off/aesops-enforcements`, `~/.claude/state/off/<hook>`, `~/.claude/state/off/aesops-enforcements.<hook>`.
- In a prompt: the rule's verb (`RULES.md`), an override phrase (`scripts/override-phrases.txt`, whole turn), `#hooks-off` / `#hooks-on`, `/ok`, `/defer`, `/reject`, `/write`, `/wrapup`, `/ok push`, `#no-ship`.
- `housekeeping report` and `/housekeeping` run the weekly routine; a report builds in the background when it is due, and `/wrapup` is held until it is done or `#housekeeping-defer`.
- `resume-item`, `observe-dismiss`, `review-changes`, `ship-session`, `vault-ship`, `plugin-fork-sync` are in `bin/`.

Logs: `~/.claude/state/hooks.log` (MISSING, ERROR, CRASH, TIMEOUT, LOOP-BREAKER, DEGRADE), `~/.claude/logs/ship-session.log`.

## Blocks

| Hook | Blocks |
|---|---|
| direction-gate | every tool until the operator opens the job with `#`, okay or yes, except the opening reads, task-observer and asking |
| secret-guard | Read or print of secret files; `--no-verify` and `core.hooksPath` changes |
| guard | writes to `~/.claude/settings*.json`, `~/.claude.json`, enforcement state and the off switches; `gate off/on` by the agent; writing `disableAllHooks` true in any repo or starting a session with it |
| answer-gate | a menu with a question that has no write-in option; ending on a "not found" claim with no search; ending on a yes/no or either/or question (phrase match; blocks once) |
| task-gate | any tool until the prompt's ENFORCEMENTS rows are met; installs and builds before the build doc was Read; Explore/Plan spawns that must keep a progress file |
| stop-gate | ending the turn with opening or wrap-up steps or owed work missing; a pushed branch with no PR, no auto-merge, or merged but not deleted (`#no-merge`, `#keep-branch <name>`); a subagent finishing with its progress file missing, plan unchecked, or writes outside its scope |
| repo-gate | first touch of a c10vis-poem repo in `~/repos` when the fork sync fails; edits and commits on a branch behind `origin/<default>` |
| push-gate | push, `gh pr create/merge/ready` mid-session; `gh pr merge --auto` when the repo has no workflow, no run, or no required checks |

## ship-session at SessionEnd

The hook returns at once and a detached worker runs for up to 10 minutes, then exits.

1. Stops if the operator typed `#no-ship` this session, or has not approved the change review with `/ok push`. Without `/ok push` nothing leaves the device: the recap says so and `ship-session --now <sid>` ships it later.
2. Looks only at repos under "Repos touched" in the session recap. It never scans `~/repos` or worktrees. Repos reached with `git -C` or `cd` in a git command are listed by session-log.
3. In each touched repo with a c10vis-poem origin: commits leftovers onto `session/<date>-<sid8>` (files in the ledger plus dirty files newer than the session start, never `git add -A`); then for every local non-default branch with unpushed commits made since the session start: gitleaks scan, push, PR, ci-ready preflight, `gh pr merge --auto --squash --delete-branch` (private free-plan repo: waits for green, then merges). Never pushes the default branch. No gitleaks or no gh: not shipped, and it says so. Branches are deleted only after MERGED.
4. Copies the recap to NvAEx-Recaps on its own branch and ships that branch the same way.
5. Runs `vault-ship` and the `vault-sync` to `main` PR only if the session touched the vault.

Known limit: inside a touched repo it cannot tell this session's branches from a parallel session's branches committed in the same window. `/ok push` is the guard.

## Cloud and other devices

Everything runs from the plugin root. The table names the checks inside the hooks. A rule that can be met still blocks in the cloud; a need only the phone can meet degrades to one `DEGRADE` line in `hooks.log` (once per session) and the call goes on.

| Hook | Needs | Without it |
|---|---|---|
| all | `jq` | nothing runs, each event logs DEGRADE; `gate status` says MISSING jq |
| enforce-prompt | `read:` targets on phone paths (npu, naming, bench rows) | row dropped |
| stop-gate | vault `skill-observations/`, gh | O5/W2/W6 reported as a NOTE, not a block |
| housekeeping-check | vault PENDING.md | skipped |
| staged-updates | Termux and the vault manifest | skipped |
| context-diff | `~/.claude/CLAUDE.md`, home-project MEMORY.md | that file skipped |
| observe-event | vault checkpoints.log | compaction scan count starts at 0 |
| sync-on-use (repo-gate) | gh, network, `~/repos` | logged, not blocked (on the phone a failed sync blocks) |
| ci-ready | gh, GitHub reachable | preflight skipped |
| save-session-log | the NvAEx-Recaps checkout | logged, session log not saved |
| ship-session | gitleaks, gh | repo reported NOT SHIPPED, nothing pushed |
| vault-ship | a vault checkout | says so, ships nothing |

Session recaps live in `~/.claude/state/recaps/`, not the vault (CONTRACT rule 8), so the ledger works the same everywhere. In a cloud session that directory goes with the container; ship-session's copy to NvAEx-Recaps is what lasts.

## Cost

Measured on the phone through the dispatcher: about 0.55 s per Read, 0.7 s per Bash, 0.8 s per Edit, plus up to 60 s on the first touch of a repo (sync-on-use). The old set ran hooks in parallel; here they run in order so results are deterministic and the contract's one entry per event holds.

## Tested on device

Moto Razr, Termux, 2026-11-05, Claude Code 2.1.318. `bash tests/selftest.sh`, about 7 minutes. Only gh is stubbed.

```
absence-gate.test.sh                11 passed   0 failed rc=0
agent-type-gate.test.sh              7 passed   0 failed rc=0
branch-current.test.sh               4 passed   0 failed rc=0
build-doc-gate.test.sh              15 passed   0 failed rc=0
carryover.test.sh                   16 passed   0 failed rc=0
change-log.test.sh                  22 passed   0 failed rc=0
ci-ready.test.sh                     4 passed   0 failed rc=0
cloud-run.test.sh                   13 passed   0 failed rc=0
delegation-tripwire.test.sh          9 passed   0 failed rc=0
enforce.test.sh                     26 passed   0 failed rc=0
gitgate.test.sh                     17 passed   0 failed rc=0
h7-mention.test.sh                   8 passed   0 failed rc=0
housekeeping.test.sh                 6 passed   0 failed rc=0
observe.test.sh                     35 passed   0 failed rc=0
settings-guard.test.sh              19 passed   0 failed rc=0
ship-gaps.test.sh                   14 passed   0 failed rc=0
staged-updates.test.sh               9 passed   0 failed rc=0
state-guard.test.sh                 19 passed   0 failed rc=0
stop-sequence.test.sh               22 passed   0 failed rc=0
subagent-stop-gate.test.sh          14 passed   0 failed rc=0
sync-on-use.test.sh                 16 passed   0 failed rc=0
test-ledger.sh                      12 passed   0 failed rc=0
test-ship-v2.sh                     18 passed   0 failed rc=0
test-ship.sh                        22 passed   0 failed rc=0
gates.test.sh                      325 passed   0 failed rc=0
TOTAL 756 passed, 0 failed
SELFTEST OK
```

Real round trip, same day: `claude -p ... --plugin-dir <this folder>` (haiku, throwaway state dir and vault). All events fired through hooks.json. With a RESUME in the vault: resume-gate blocked, the model Read RESUME and went on, checkin-gate blocked its Bash, stop-gate blocked three times, LOOP-BREAKER yielded, the session ended.

`claude plugin validate` does not run on this device (it falls through to the print-mode error), so the manifest is proven only by that load.
