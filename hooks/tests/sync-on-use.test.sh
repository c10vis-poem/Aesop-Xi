#!/data/data/com.termux/files/usr/bin/bash
# Fake HOME, stub gh + git fetch/merge. No network, no real repo.
# H2 is blocking: first touch of a c10vis-poem repo waits for the sync; a failed sync blocks (exit 2).
HOOK=$(cd "$(dirname "$0")/.." && pwd)/sync-on-use.sh
REALGIT=$(command -v git)
T=$(mktemp -d); export HOME=$T/home; mkdir -p "$HOME/repos" "$T/bin" "$T/other"
cat >"$T/bin/gh" <<'E'
#!/data/data/com.termux/files/usr/bin/bash
echo "gh $*" >>"$STUBLOG"
case "$*" in
  "repo view"*) echo true ;;
  "repo sync"*) if [ -e "$GHFAIL" ]; then echo "HTTP 502: network down"; exit 1; fi ;;
esac
E
cat >"$T/bin/git" <<E
#!/data/data/com.termux/files/usr/bin/bash
case "\$*" in *" fetch "*|*" merge --ff-only "*) echo "git \$*" >>"\$STUBLOG"; exit 0 ;; esac
exec $REALGIT "\$@"
E
chmod +x "$T/bin/gh" "$T/bin/git"
export PATH=$T/bin:$PATH STUBLOG=$T/stub.log GHFAIL=$T/ghfail; : >"$STUBLOG"

mk() { "$REALGIT" init -q -b main "$1"; "$REALGIT" -C "$1" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i; "$REALGIT" -C "$1" remote add origin "$2"; }
mk "$HOME/repos/FAKE" https://github.com/c10vis-poem/FAKE.git
mk "$HOME/repos/OTHER" https://github.com/someone/OTHER.git
mk "$HOME/repos/DIRTY" https://github.com/c10vis-poem/DIRTY.git; touch "$HOME/repos/DIRTY/x"
mk "$HOME/repos/BR" https://github.com/c10vis-poem/BR.git; "$REALGIT" -C "$HOME/repos/BR" checkout -q -b feat
"$REALGIT" -C "$HOME/repos/FAKE" worktree add -q -b wt "$HOME/repos/.wt-fake" 2>/dev/null

run() {  # sid tool cwd fp [command]
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg f "$4" --arg k "${5:-ls}" \
    '{session_id:$s,cwd:$c,tool_name:$t,tool_input:{file_path:$f,command:$k}}' | bash "$HOOK" 2>>"$T/err"; echo $?
}
syncs() { awk -v r="$1" '$0 ~ "repo sync c10vis-poem/"r"$"' "$STUBLOG" | wc -l | tr -d ' '; }
fails=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got '$2' want '$3')"; fails=$((fails+1)); fi; }

chk "edit in fork: allowed after sync" "$(run S1 Edit "$T/other" "$HOME/repos/FAKE/a.txt")" 0
chk "fork synced once" "$(syncs FAKE)" 1
chk "local fast-forwarded" "$(awk '/merge --ff-only/' "$STUBLOG" | wc -l | tr -d ' ')" 1
run S1 Read "$T/other" "$HOME/repos/FAKE/b.txt" >/dev/null
chk "second touch same session: no resync" "$(syncs FAKE)" 1
chk "worktree resolves to its repo (already synced)" "$(run S1 Bash "$HOME/repos/.wt-fake" "")" 0
chk "worktree did not resync" "$(syncs FAKE)" 1
chk "repo named inside a bash command is synced" "$(run S2 Bash "$T/other" "" "git -C ~/repos/DIRTY status")" 0
chk "DIRTY synced" "$(syncs DIRTY)" 1
chk "dirty clone not fast-forwarded" "$(awk '/DIRTY.* merge --ff-only/' "$STUBLOG" | wc -l | tr -d ' ')" 0
chk "feature-branch clone allowed" "$(run S3 Bash "$HOME/repos/BR" "")" 0
chk "non-operator repo ignored" "$(run S4 Bash "$HOME/repos/OTHER" "")" 0
chk "OTHER never synced" "$(syncs OTHER)" 0
chk "outside ~/repos ignored" "$(run S5 Edit "$T/other" "$T/other/z")" 0
touch "$GHFAIL"
chk "sync failure BLOCKS" "$(run S6 Edit "$T/other" "$HOME/repos/FAKE/a.txt")" 2
chk "blocked repo not marked synced" "$([ -e "$HOME/.claude/state/synced-S6-FAKE" ] && echo yes || echo no)" no
rm -f "$GHFAIL"
chk "retry after fix: allowed" "$(run S6 Edit "$T/other" "$HOME/repos/FAKE/a.txt")" 0

echo "== $((17-fails)) passed, $fails failed"; rm -rf "$T"; [ "$fails" = 0 ]
