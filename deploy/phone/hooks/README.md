# Phone hooks

Sources live in `aesop-xi/deploy/phone/hooks/`. Live copies are in `~/.claude/hooks/` and `~/.config/git/hooks/`. Rules registry: `~/.claude/ENFORCEMENTS.md`.

| File | Event | What it does |
|---|---|---|
| `git-hooks/dispatch` (+ symlinks) | git, every repo (global hooksPath `~/.config/git/hooks`) | gitleaks on pre-commit / pre-push. A secret blocks it. Then runs the repo's own hook. Exceptions only through the repo's `.gitleaksignore`. |
| `secret-guard.sh` | PreToolUse `Bash\|Read` | refuses printing secret files unless the values are redacted; refuses git hook skipping or hooksPath changes |
| `resume-gate.sh` | PreToolUse `*` | no tool runs until RESUME.md (the repo's, else the vault's) has been read |
| `enforce-gate.sh` | PreToolUse `*` | no tool runs until this prompt's ENFORCEMENTS requirements are met |
| `branch-current-gate.sh` | PreToolUse `Bash\|Edit\|Write` | no edits or `git commit` in a c10vis-poem repo whose branch doesn't contain the latest `origin/<default>` (fetches once per repo per session). Fix: start a worktree from current main. Vault exempt (GitSync) |
| `sync-on-use.sh` | PreToolUse `Bash\|Edit\|Write\|Read` | first use of a `~/repos/<fork>` in a session: background `gh repo sync` + ff-pull if clean |
| `session-ledger.sh` | PostToolUse `Edit\|Write\|Bash` | logs repos touched, files written and git actions to the vault `_recaps/<date>-<sid>.md` (git-ignored) |
| `enforce-prompt.sh` + `classify.sh` | UserPromptSubmit | works out the required skill / read / script per prompt (keyword rows, or `CLASSIFY_URL` backend) |
| `context-diff.sh` | SessionStart | shows CLAUDE.md / MEMORY.md lines changed since the last session |
| `housekeeping-check.sh` | SessionStart | "HOUSEKEEPING DUE" when PENDING.md `last-housekeeping` is 7+ days old or it's the end of the week |
| `ship-session.sh` | SessionEnd | ships only repos this session touched, only files changed this session: branch → commit (gitleaks) → PR → auto-merge; writes `## Shipped` into the recap |
| `archive-scratchpad.sh` | SessionEnd / PreCompact | copies the session scratchpad to `~/.claude/scratchpad-archive/` |
| `stop-gate.sh` (H1 Stop) | Stop | turn can't end until RESUME was read, every RESUME "START HERE" item has a status (`~/bin/resume-item <n> done\|blocked "<note>"`), task-observer loaded + session-start scan written, no ENFORCEMENTS pending. `#skip-enforce` skips (logged). |

Operator override for enforcement (user-typed only): `#skip-enforce` in a prompt (logged).

## Git workflow (always on)
1. Repo current with main before any edit/commit (`branch-current-gate.sh`; H2 sync-on-use syncs forks).
2. Every change logged as it happens (H3 session ledger → vault `_recaps/`).
3. Secrets scanned on every commit and push (H5 gitleaks).
4. Ship: push → PR → auto-merge (squash) → branch deleted after MERGED (H4 ship-session), on "push now" or `/wrapup`.
5. Keep a branch: type `#keep-branch <name>` → ship pushes a `saved/<name>` copy before merging.
6. `/wrapup` can't finish with uncommitted session work in any repo (Stop gate).
