# Old gates: feature list (for porting into aesops-enforcements)

The old rules plugin (shell gates) was replaced by the contract plugin. PR #90 carried commit 98e89e6, which
deleted it without the owner's review. Owner, 2026-11-12: a replacement carries every feature still in use,
and nothing is deleted without the owner's approval of the list. Below is every old file not in main, its own
description, and where to get it back (`git show <tag>:<path>`; the tags are on GitHub). The owner marks each: port, or strike.

| Mark | File | What it did (its own header) | Get it from |
|---|---|---|---|
| [ ] | `hooks/ENFORCEMENTS.md` | ENFORCEMENTS — what must be used, per task / repo / skill | tag `old-gates/fix-h7-mention-vs-command` |
| [ ] | `hooks/README.md` | Phone hooks | tag `old-gates/feat-stop-auditor` |
| [ ] | `hooks/auditor/install-auditor.sh` | Optional/experimental: add (or --uninstall) the per-task Stop auditor in ~/.claude/settings.json. | tag `old-gates/feat-stop-auditor` |
| [ ] | `hooks/auditor/settings-snippet.json` | { | tag `old-gates/feat-stop-auditor` |
| [ ] | `hooks/classify.sh` | H7 classifier. Contract: Aesop-Xi/protocol/classify.md | tag `old-gates/fix-h7-mention-vs-command` |
| [ ] | `plugins/aesops-enforcements/README.md` | aesops-enforcements | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/SOURCES.md` | Sources | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/asset-manifest` | [ -n "$BASH_VERSION" ] // exec bash "$0" "$@"   # /usr/bin/env is absent on Termux without termux-exec | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/gate` | [ -n "$BASH_VERSION" ] // exec bash "$0" "$@"   # /usr/bin/env is absent on Termux without termux-exec | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/housekeeping` | [ -n "$BASH_VERSION" ] // exec bash "$0" "$@"   # /usr/bin/env is absent on Termux without termux-exec | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/observe-dismiss` | [ -n "$BASH_VERSION" ] // exec bash "$0" "$@"   # /usr/bin/env is absent on Termux without termux-exec | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/plugin-fork-sync` | exec bash "$(dirname "$(realpath "$0")")/../scripts/plugin-fork-sync.sh" "$@ | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/resume-item` | [ -n "$BASH_VERSION" ] // exec bash "$0" "$@"   # /usr/bin/env is absent on Termux without termux-exec | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/review-changes` | exec bash "$(dirname "$(realpath "$0")")/../scripts/review-changes.sh" "$@ | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/ship-session` | exec bash "$(dirname "$(realpath "$0")")/../scripts/ship-session.sh" "$@ | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/bin/vault-ship` | exec bash "$(dirname "$(realpath "$0")")/../scripts/vault-ship.sh" "$@ | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/commands/defer.md` | Operator check-off for RESUME START HERE items (/defer or /defer 1,3). Recorded by the enforce-prompt hook. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/commands/housekeeping.md` | Run weekly housekeeping - report, act on each routine with the operator, then mark it done | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/commands/ok.md` | Operator check-off for RESUME START HERE items (/ok or /ok 1,3). Recorded by the enforce-prompt hook. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/commands/reject.md` | Operator check-off for RESUME START HERE items (/reject or /reject 1,3). Recorded by the enforce-prompt hook. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/commands/wrapup.md` | End the session — run the wrap-up protocol (commit, observations, memory, PENDING, per-repo docs, RESUME rewrite, ship) | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/extras/auditor/settings-snippet.json` | { | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/ENFORCEMENTS.md` | ENFORCEMENTS — what must be used, per task / repo / skill | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/WRAP-UP.md` | Session wrap-up protocol | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/absence-gate.sh` | Absence-claim gate (Stop, decision 56; obs 0007/0016/0024/0034). A final answer that says something is | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/agent-type-gate.sh` | PreToolUse (Agent), obs 0023: a read-only subagent (Explore, Plan) cannot write the progress file | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/answer-gate.sh` | Rules 5 and 8 (operator numbering: 5 and 9; claim-gate is the rest of 9). PreToolUse AskUserQuestion: a menu needs a write-in option. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/branch-current-gate.sh` | PreToolUse (Bash/Edit/Write): no edits or commits in a c10vis-poem repo whose branch doesn't contain | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/build-doc-gate.sh` | obs 0005. PostToolUse Read: a Read of a checkout's install/build doc (README, INSTALL, BUILD, | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/carryover.sh` | H9 carry-over ledger (observation 0030). A START HERE item that a session leaves unfinished is | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/change-log.sh` | PreToolUse (Write, Edit, NotebookEdit, Bash): record every write, move, copy, delete and script run | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/ci-ready.sh` | ci-ready.sh <owner/repo> <branch>: exit 0 when the repo can ship through the full pipeline: | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/claim-gate.sh` | Rule 9, read and verify before saying it (Stop). Two checks on the final answer, besides absence-gate's | tag `old-gates/fix-opening-deadlock-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/classify.sh` | H7 classifier. Contract: Aesop-Xi/protocol/classify.md | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/context-diff.sh` | SessionStart: show what changed in CLAUDE.md and MEMORY.md since the last session. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/direction-gate.sh` | Rule 1, the operator's words: no actions, no reading, no tool use without explicit permission or direction. | tag `old-gates/fix-opening-deadlock-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/enforce-gate.sh` | H6, PreToolUse "*": refuse tool calls until this prompt's requirements are met. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/enforce-prompt.sh` | H6, UserPromptSubmit: work out what this prompt requires and write it to state. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/gates.tsv` | The wiring. event, matcher (regex on tool_name, * = all), hook, timeout s, override verb, Bash prefilter. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-gate.sh` | PreToolUse (Bash): no push / PR / merge mid-session. Commit on local branches; | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/dispatch` | Global git hook (core.hooksPath). Runs gitleaks on pre-commit / pre-push, then | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/post-checkout` | dispatch | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/post-commit` | dispatch | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/post-merge` | dispatch | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/pre-commit` | dispatch | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/git-hooks/pre-push` | dispatch | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/guard.sh` | Rule 4, PreToolUse (Bash, Edit, Write): the agent cannot change settings, enforcement state or the switches, | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/housekeeping-check.sh` | H1b, SessionStart: remind when weekly housekeeping is due. | tag `old-gates/fix-opening-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/killswitch.sh` | Frankenstein kill switch. Usage: killswitch.sh <package> [hook-name] | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/lib/env.sh` | Shared environment for every aesops-enforcements hook. Sourced, never run. Works on the phone (Termux) and in | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/lib/opening.sh` | Sourced by stop-gate.sh and direction-gate.sh. One source for the opening steps (observation 0090): | tag `old-gates/fix-opening-deadlock-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/lib/parts.sh` | Sourced by the merged hooks. run_parts A B C: runs each check in order on the event in $in. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/lib/subagent.sh` | Sourced by subagent-stop-gate.sh and subagent-task-gate.sh. Needs $in (the hook's JSON). | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/menu-gate.sh` | PreToolUse (AskUserQuestion), rule 5: a menu is allowed only if every question offers a way for the | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/observe-corrections.txt` | Operator-correction patterns for observe-event.sh (UserPromptSubmit): one extended regex per line, | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/observe-event.sh` | Observer events (SessionStart, PostToolUseFailure, PermissionDenied, UserPromptSubmit). Always exits 0. | tag `old-gates/fix-short-blocks-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/override-phrases.txt` | Operator override phrases (case-insensitive extended regex, one per line). | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/plugin-fork-sync.sh` | By hand (bin/plugin-fork-sync; never wired: RULES.md): every plugin marketplace backed by a c10vis-poem fork gets | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/push-gate.sh` | Rule 10, PreToolUse Bash: no push, PR or merge mid-session, and no auto-merge without CI. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/question-gate.sh` | Stop, the operator's Rule 5: a turn cannot end on a closed question: yes/no, either/or, or a menu with no write-in. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/repo-gate.sh` | Rule 10, PreToolUse: a fork is synced before it is touched, and no work on a branch behind main. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/review-changes.sh` | Wrap-up change review: summarise everything change-log.sh recorded this session, write it into the | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/run-gate.sh` | The one launcher. hooks/hooks.json calls `run-gate.sh --event <Event>`; rows of gates.tsv run in order. | tag `old-gates/fix-short-blocks-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/save-session-log.sh` | Rule 7 (operator numbering), the session log, written at SessionEnd (the wrap-up's last step). Two parts, one place: | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/secret-guard.sh` | PreToolUse (Bash, Read): refuse printing secret files and skipping git hooks. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/session-ledger.sh` | PostToolUse (Edit/Write/Bash): append this session's repos / files / git actions to | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/session-log.sh` | Rule 9, the one session log. Before a call: the action (change-log). After: repos, files and git actions | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/session-start.sh` | Rule 7, SessionStart: what changed, whether housekeeping is due, staged skill updates. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/settings-guard.sh` | PreToolUse (Bash/Edit/Write): the agent may not change the operator's Claude Code configuration: | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/ship-session.sh` | SessionEnd: the operator's GitHub rule (Rule 8), in one pass. Forks touched are synced first (repo-gate); | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/source-gate.sh` | Rule 12 (operator, 2026-11-10): read the source first. Working with a fork, an install or any asset, no claim | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/staged-updates.sh` | SessionStart (Termux only): staged skill updates waiting in the vault skill-updates/PENDING.md, plus a | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/state-guard.sh` | PreToolUse (Bash/Write/Edit), obs 0017: the agent may not delete, move, truncate or write the | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/stop-gate.sh` | H1 Stop gate. The turn cannot end while a required step of the session is missing. Two checklists: | tag `old-gates/fix-opening-deadlock-2026-11-10` |
| [ ] | `plugins/aesops-enforcements/scripts/subagent-stop-gate.sh` | Rule 10, SubagentStop: the write-to-task stop gate for every subagent that can write. A subagent cannot stop while: | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/subagent-task-gate.sh` | Rule 10, PreToolUse for subagents only: write to task as you work (operator's spec, Documents/Read this | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/subagent_audit.py` | subagent_audit.py -- Rule 10 audit of one sub-agent, from its own transcript (operator, 2026-11-10). | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/sync-on-use.sh` | H2, PreToolUse (Bash/Edit/Write/Read): a c10vis-poem repo under ~/repos is not touched until it is | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/task-gate.sh` | Rule 6: what the task requires comes first. PreToolUse: subagent type, build docs, ENFORCEMENTS rows | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/scripts/vault-ship.sh` | vault-ship: upload the vault (replaces GitSync's upload) and open the vault-sync -> main PR. | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/skills.json` | { | tag `old-gates/rules-fix-2026-11-09` |
| [ ] | `plugins/aesops-enforcements/skills/gates/SKILL.md` | gates | tag `old-gates/rules-fix-2026-11-09` |

Tests for these (37 files) come back with the feature they test: `auditor.test.sh`, `h7-mention.test.sh`, `gates.test.sh`, `absence-gate.test.sh`, `agent-type-gate.test.sh`, `branch-current.test.sh`, `build-doc-gate.test.sh`, `carryover.test.sh`, `change-log.test.sh`, `ci-ready.test.sh`, `claim-gate.test.sh`, `cloud-run.test.sh`, `direction-gate.test.sh`, `enforce.test.sh`, `gitgate.test.sh`, `h7-mention.test.sh`, `housekeeping.test.sh`, `lib.sh`, `menu-question.test.sh`, `observe.test.sh`, `opening-e2e.test.sh`, `owed-work.test.sh`, `pushed-branch.test.sh`, `rule4-direction.test.sh`, `save-session-log.test.sh`, `settings-guard.test.sh`, `ship-gaps.test.sh`, `source-gate.test.sh`, `staged-updates.test.sh`, `state-guard.test.sh`, `stop-sequence.test.sh`, `subagent-stop-gate.test.sh`, `sync-on-use.test.sh`, `test-ledger.sh`, `test-ship-v2.sh`, `test-ship.sh`, `selftest.sh`.
