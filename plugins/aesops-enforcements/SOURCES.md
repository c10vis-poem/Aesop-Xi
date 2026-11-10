# Sources

All from `c10vis-poem/Aesop-Xi` at origin/main 9867c79 (the operator's own repo; no LICENSE file there, this package is MIT per CONTRACT) unless noted. No media, lockfiles, telemetry or network calls added.

| Package file | Origin | Changed |
|---|---|---|
| scripts/{absence-gate,agent-type-gate,branch-current-gate,build-doc-gate,carryover,change-log,checkin-gate,ci-ready,classify,context-diff,delegation-tripwire,enforce-gate,enforce-prompt,git-gate,housekeeping-check,observe-event,plugin-fork-sync,review-changes,secret-guard,session-ledger,settings-guard,ship-session,staged-updates,state-guard,stop-gate,subagent-stop-gate,sync-on-use,vault-ship}.sh | hooks/ | shebang, phone paths to lib/env.sh; hook-specific changes below |
| scripts/direction-gate.sh | new, 2026-11-06 | Rule 1 in the operator's words; replaces resume-gate and checkin-gate |
| scripts/run-gate.sh | hooks/run-gate.sh + run-hook.sh + PR #84 run-hook.sh safety net | rewritten: event dispatcher, MISSING loud, exit 2 needs a block message, same-call loop breaker, hard guards |
| scripts/override-phrases.txt | PR #84 hooks/override-phrases.txt | `#skip-enforce` line removed so it stays rule 6's verb, not a lift of every gate |
| scripts/lib/env.sh | hooks/lib/env.sh | degrade(), RECAPS_DIR, plugin bin on PATH, no absolute phone path in vault_find |
| scripts/ENFORCEMENTS.md, WRAP-UP.md, observe-corrections.txt | hooks/ | paths |
| scripts/git-hooks/ | hooks/git-hooks/ | `#!/bin/sh` (git execs it; Termux has no /usr/bin/env) |
| scripts/killswitch.sh | tools/plugin-shared/killswitch.sh | none |
| bin/gate | hooks/gate | hook list from gates.tsv, unknown names refused, `on all` keeps other packages' switches, status reports missing and crashes |
| bin/resume-item, bin/observe-dismiss | deploy/phone/bin/ | `#!/bin/sh` re-exec into bash, STATE_DIR |
| commands/{ok,defer,reject,wrapup}.md | deploy/phone/commands/ | wrapup path |
| extras/auditor/settings-snippet.json | hooks/auditor/ | not wired (RULES.md) |
| tests/hooks/* | hooks/tests/ | paths; changes below |
| RULES.md | hooks/RULES.md | extended to every hook |

Not copied: hooks/settings.hooks.json and settings.hooks.v2.json (replaced by gates.tsv), hooks/README.md (replaced by README.md and RULES.md), hooks/auditor/install-auditor.sh and tests/auditor.test.sh (the installer edits settings.json), hooks/run-hook.sh (merged into run-gate.sh).

## Behaviour changes to the vendored hooks

- ship-session: the worktree scan is gone (touched repos only); `/ok push` always required; own gitleaks scan; no gitleaks or gh means not shipped; vault steps only when touched; `#no-ship` honoured. tests/hooks/ship-gaps.test.sh check 1 is inverted to match.
- session-ledger: recaps in `~/.claude/state/recaps/`, not vault `_recaps/` (CONTRACT rule 8); repos reached by `git -C` or `cd` in a git action are listed. stop-gate and review-changes read from there.
- state-guard: also covers run-gate state, the off switches, `~/.nvaex-hooks-off`, and `gate off/on` from the agent.
- ci-ready: hook entry for `gh pr merge --auto`; also requires a workflow that has run (obs 0026).
- carryover: hook entry (report at RESUME read, record at SessionEnd).
- subagent-stop-gate: progress files in subfolders of session-work/<date>/ now match.
- enforce-prompt: `/wrapup-defer` (named in RULES.md, never implemented) and `/aesops-enforcements:ok` forms; rows whose `read:` file is not on the device are dropped with a log line.
- sync-on-use: `--sync` mode (plugin-fork-sync called it, it did not exist); cloud or no gh degrades.
- absence-gate: message starts `BLOCKED (absence-gate):` like every gate.
- RULES.md verbs that run-gate.sh did not implement now work: `#show-secret <path>` (it checked `#skip-secret`), `#no-ship` (it checked `#skip-ship`).

## Sizes

- Source: hooks/ 241 KB, 78 files (with tests). Package: see below; nothing was trimmed from hook logic, by order ("nothing is dropped"). Removed: 2 settings files, run-hook.sh, auditor installer and test, hooks/README.md (14 KB).

## Missing

Nothing named was missing on the phone.
