#!/data/data/com.termux/files/usr/bin/bash
# H4 ship-session.sh end-to-end against local bare remotes + stub gh + fake vault.
source "$(dirname "$0")/lib.sh"
SID=22222222-aaaa-bbbb-cccc-000000000000
B="session/$(date +%F)-22222222"
for r in ra rb rs rn; do mkrepo $r; done
W=$T/work

# Pre-existing state (before the session): dirty tracked file + untracked file in ra, dirty file in rb.
echo pre >> "$W/ra/b.txt"; echo old > "$W/ra/old.txt"; echo pre >> "$W/rb/a.txt"
touch -d '-1 hour' "$W/ra/b.txt" "$W/ra/old.txt" "$W/rb/a.txt"

# Session: first hook call creates the start marker; back-date it so later writes are clearly newer.
ledger "$(bash_ev 'git status' "$W/rn")"
touch -d '-1 minute' "$STATE_DIR/session-$SID.start"
echo session >> "$W/ra/a.txt";  ledger "$(write_ev "$W/ra/a.txt")"          # ledger file
echo new > "$W/ra/c.txt"                                                     # Bash-made, mtime-new
ledger "$(bash_ev 'git commit -m wip' "$W/ra")"
printf 'token = "ghp_%s"\n' "$(head -c 400 /dev/urandom | tr -dc A-Za-z0-9 | head -c 36)" > "$W/rs/conf.txt"
ledger "$(write_ev "$W/rs/conf.txt")"                                        # fake secret
echo note > "$VAULT/note.md"; ledger "$(write_ev "$VAULT/note.md")"          # vault
echo '{"type":"ai-title","aiTitle":"Test session title","sessionId":"'$SID'"}' > "$PROJECTS_DIR/p/$SID.jsonl"
L=$(ls "$VAULT"/_recaps/*-22222222.md)

# Dry run: reports, changes nothing.
dry=$(bash "$HOOKS/ship-session.sh" --dry-run "$SID" 2>&1); echo "$dry"
check "dry-run reports plan" 'grep -q "DRY-RUN: would commit 2 file(s) on $B" <<<"$dry"'
check "dry-run creates no branch" '[ -z "$(git -C "$W/ra" branch --list "session/*")" ]'
check "dry-run leaves recap alone" '! grep -q "## Shipped" "$L"'

# Real run via hook entry: must return fast (detached), then finish in background.
s=$(date +%s); jq -nc --arg s "$SID" '{session_id:$s,hook_event_name:"SessionEnd"}' | bash "$HOOKS/ship-session.sh"
check "hook returns in <2s (detached)" '[ $(( $(date +%s) - s )) -lt 2 ]'
for _ in $(seq 120); do grep -q "=== done" "$SHIP_LOG" 2>/dev/null && break; sleep 0.5; done
cat "$SHIP_LOG"; echo ----; cat "$L"; echo ----; cat "$T/gh.log"

# ra: only session files committed, on a new branch, pushed; pre-existing dirt untouched.
files=$(git -C "$W/ra" show --name-only --format= "$B" 2>/dev/null | sort | tr '\n' ' ')
check "ra: branch created from default + pushed" 'git -C "$T/remotes/ra.git" rev-parse -q --verify "refs/heads/$B" >/dev/null'
check "ra: commit has exactly a.txt c.txt" '[ "$files" = "a.txt c.txt " ]'
check "ra: commit message + trailer" 'git -C "$W/ra" log -1 --format=%B "$B" | grep -q "^Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && git -C "$W/ra" log -1 --format=%s "$B" | grep -qx "chore: session $(date +%F) changes"'
check "ra: back on main" '[ "$(git -C "$W/ra" branch --show-current)" = main ]'
check "ra: pre-existing b.txt still dirty, old.txt still untracked" 'git -C "$W/ra" status --porcelain | grep -q "^ M b.txt" && git -C "$W/ra" status --porcelain | grep -q "^?? old.txt"'
check "ra: main not advanced on remote" '[ "$(git -C "$T/remotes/ra.git" rev-list --count main)" = 1 ]'
# rb: untouched -> not in ledger, nothing done.
check "rb: untouched repo skipped (no branch, dirt intact)" '[ -z "$(git -C "$T/remotes/rb.git" branch --list "session/*")" ] && git -C "$W/rb" status --porcelain | grep -q "^ M a.txt" && ! grep -q "/rb:" "$L"'
# rs: secret -> commit refused, nothing pushed, repo restored.
check "rs: reported BLOCKED: secret found" 'grep -q "/rs: BLOCKED: secret found" "$L"'
check "rs: nothing pushed, no local branch" '[ -z "$(git -C "$T/remotes/rs.git" branch --list "session/*")" ] && [ -z "$(git -C "$W/rs" branch --list "session/*")" ]'
check "rs: back on main, file unstaged" '[ "$(git -C "$W/rs" branch --show-current)" = main ] && git -C "$W/rs" status --porcelain | grep -q "^?? conf.txt"'
# rn: touched (Bash cwd) but nothing new -> skipped; vault skipped.
check "rn: nothing to ship" 'grep -q "/rn: skipped: nothing to ship" "$L"'
check "vault skipped" 'grep -q "/vault: skipped: vault (GitSync)" "$L"'
# gh: one create + one merge, for ra's PR only.
check "gh: single pr create for ra branch" '[ "$(grep -c "^pr create" "$T/gh.log")" = 1 ] && grep -q -- "--head $B" "$T/gh.log"'
check "gh: PR body ends with Claude Code line" 'grep -q "Generated with \[Claude Code\](https://claude.com/claude-code)" "$T/gh.log"'
check "gh: auto-merge only that PR" '[ "$(grep -c "^pr merge" "$T/gh.log")" = 1 ] && grep -qx "pr merge https://github.com/stub/repo/pull/1 --auto --squash" "$T/gh.log"'
check "recap: Shipped has ra branch/sha/PR/auto-merge on" 'grep -qE "/ra: branch $B, commit [0-9a-f]+, PR https://github.com/stub/repo/pull/1, auto-merge on" "$L"'
check "recap: all sections" '[ "$(grep "^## " "$L" | tr "\n" "|")" = "## Repos touched|## Files written|## Git actions|## Shipped|## Title|" ]'
check "recap: title from transcript" 'grep -qx "Test session title" "$L"'
finish
