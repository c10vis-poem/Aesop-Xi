# Phone hooks

Installed on the phone 2026-10-01. Sources live here; the live copies are in `~/.claude/hooks/` and `~/.config/git/hooks/`.

| File | Where it runs | What it does |
|---|---|---|
| `git-hooks/dispatch` (+ symlinks) | every git repo, via global `core.hooksPath` = `~/.config/git/hooks` | gitleaks on pre-commit and pre-push. A secret blocks the commit or push. Then it runs the repo's own `.git/hooks/<name>`. Exceptions only through the repo's `.gitleaksignore`. |
| `secret-guard.sh` | Claude Code PreToolUse, matcher `Bash\|Read` | refuses printing secret files unless values are redacted; refuses git hook skipping or hooksPath changes |
| `resume-gate.sh` | Claude Code PreToolUse, matcher `*` | every tool is blocked until the session has Read RESUME.md (the repo's, else the vault's) |
| `context-diff.sh` | Claude Code SessionStart | shows lines changed in CLAUDE.md and MEMORY.md since the last session |

Install: `pkg install gitleaks`, copy the files to the paths above, set the global hooksPath, then add the three entries to `~/.claude/settings.json` under `hooks`.
