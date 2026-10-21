# Phone hooks

Sources live in `aesop-xi/hooks/`. Live copies are in `~/.claude/hooks/` and `~/.config/git/hooks/`. Rules registry: `~/.claude/ENFORCEMENTS.md`.

| File | Event | What it does |
|---|---|---|
| `git-hooks/dispatch` (+ symlinks) | git, every repo (global hooksPath `~/.config/git/hooks`) | gitleaks on pre-commit / pre-push. A secret blocks it. Then runs the repo's own hook. Exceptions only through the repo's `.gitleaksignore`. |
| `checkin-gate.sh` | PreToolUse `*` | after RESUME is read: no changes (edits, state-changing Bash) until the operator checks in with `#ok` / `#ok 1,3` / `#defer 2` / `#reject 2`. Reading, read-only Bash, the observer checkpoint and `resume-item plan` stay allowed. Only for sessions started with the RESUME snapshot |
| `secret-guard.sh` | PreToolUse `Bash\|Read` | refuses printing secret files unless the values are redacted; refuses git hook skipping or hooksPath changes |
| `resume-gate.sh` | PreToolUse `*` | no tool runs until RESUME.md (the repo's, else the vault's) has been read |
| `enforce-gate.sh` | PreToolUse `*` | no tool runs until this prompt's ENFORCEMENTS requirements are met |
| `branch-current-gate.sh` | PreToolUse `Bash\|Edit\|Write` | no edits or `git commit` in a c10vis-poem repo whose branch doesn't contain the latest `origin/<default>` (fetches once per repo per session). Fix: start a worktree from current main. Vault exempt (GitSync) |
| `sync-on-use.sh` | PreToolUse `Bash\|Edit\|Write\|Read` | BLOCKING: the first touch of a `~/repos/<fork>` (path, cwd, or a path in a Bash command; worktrees count as their repo) waits for `gh repo sync` + fetch + ff of the default branch; a failed sync blocks the call |
| `session-ledger.sh` | PostToolUse `Edit\|Write\|Bash` | logs repos touched, files written and git actions to the vault `_recaps/<date>-<sid>.md` (git-ignored) |
| `enforce-prompt.sh` + `classify.sh` | UserPromptSubmit | works out the required skill / read / script per prompt (keyword rows, or `CLASSIFY_URL` backend) |
| `context-diff.sh` | SessionStart | shows CLAUDE.md / MEMORY.md lines changed since the last session |
| `housekeeping-check.sh` | SessionStart | "HOUSEKEEPING DUE" when PENDING.md `last-housekeeping` is 7+ days old or it's the end of the week |
| `ship-session.sh` | SessionEnd | ships only repos this session touched, only files changed this session: branch → commit (gitleaks) → PR → auto-merge; writes `## Shipped` into the recap. Also: ships session worktrees the ledger never listed (`~/repos/.wt-*`, repos with 2+ worktrees); copies the recap to `NvAEx-Recaps/recaps/<repo>/` for every repo touched (own branch, shipped last); a repo with no origin is reported `NO REMOTE, NOT SHIPPED` |
| `vault-ship.sh` (+ `~/bin/vault-ship`) | wrap-up (from ship-session) or by hand | uploads the vault (replaces GitSync's upload): merges what GitHub has, commits, pushes `vault-sync`, opens the PR to `main` with auto-merge. `--dry-run` previews. Never switches branches; stops on empty git objects; restores files emptied by failed writes |
| `archive-scratchpad.sh` | SessionEnd / PreCompact | copies the session scratchpad to `~/.claude/scratchpad-archive/` |
| `stop-gate.sh` (H1 Stop) | Stop | turn can't end until RESUME was read, every RESUME "START HERE" item has a status (`~/bin/resume-item <n> done\|blocked "<note>"`), task-observer loaded + session-start scan written (again after a compaction), every friction event logged as an observation or dismissed, no ENFORCEMENTS pending. In `/wrapup`: task-observer weekly review not 7+ days overdue while observations are open; parked observations whose `parked_until` fork branch is now merged are reported. `#skip-enforce` skips (logged). |
| `subagent-stop-gate.sh` | SubagentStop | a subagent whose spawn prompt names `~/.claude/session-work/<date>/agent-<topic>.md` can't finish while that file is missing or a `- [ ]` step in `## Plan` isn't listed under `## Blocked`. Blocks once (`stop_hook_active` allows). Feedback goes to the subagent only; touches no main-session state or observer queue. |
| `observe-event.sh` (+ `observe-corrections.txt`, `~/bin/observe-dismiss`) | SessionStart `compact`, PostToolUseFailure, PermissionDenied, UserPromptSubmit | compaction: clears `satisfied-<sid>.tsv` and records it, so the Stop gate wants task-observer loaded and a new session-start scan. Tool failures, auto-mode classifier denials, operator-correction prompts (regexes in `observe-corrections.txt`) and gate BLOCK lines (imported by the Stop gate) queue friction events in `state/observe-queue-<sid>.tsv`. Close one by writing an observation, or `observe-dismiss <id> "<reason>"` (`observe-dismiss list` shows them) |
| `run-hook.sh` | (launcher) | aesop-xi `.claude/settings.json` registers every hook above through this, so any session started in aesop-xi gets H1–H7 on any device. Stands down when `~/.claude/hooks/<name>` exists (global copy already fires), so nothing runs twice. |

Operator override for enforcement (user-typed only): `#skip-enforce` in a prompt (logged).

## Git workflow (always on)
1. Repo current with main before any edit/commit (`branch-current-gate.sh`; H2 sync-on-use syncs forks).
2. Every change logged as it happens (H3 session ledger → vault `_recaps/`).
3. Secrets scanned on every commit and push (H5 gitleaks).
4. Ship: push → PR → auto-merge (squash) → branch deleted after MERGED (H4 ship-session), on "push now" or `/wrapup`.
5. Keep a branch: type `#keep-branch <name>` → ship pushes a `saved/<name>` copy before merging.
6. `/wrapup` can't finish with uncommitted session work in any repo (Stop gate).

## Session start / end (operator check-off)
1. RESUME read → snapshot + fingerprint saved (resume-gate).
2. Agent posts the START HERE plan (each item, what it will do, tools/skills), runs `resume-item plan`, ends the turn.
3. Operator replies `/ok 1,3`, `/defer 2`, `/reject 2` (or the `#` forms) to the plan. At the end of the session a bare `/ok` confirms everything as marked: done → confirmed, blocked → deferred. Until then: no changes (checkin-gate).
4. Agent marks finished items `resume-item <n> done "<evidence>"`; they count only after the operator's `#ok <n>`. `#reject <n>` clears a proposal.
5. `/wrapup`: every item must be operator-confirmed done or deferred (deferred ones in PENDING.md), RESUME rewritten, session work committed.
