#!/data/data/com.termux/files/usr/bin/bash
# Staging test: fake HOME, stub gh + git pull. No network, no real repo.
HOOK=$(cd "$(dirname "$0")/.." && pwd)/sync-on-use.sh
REALGIT=$(command -v git)
T=$(mktemp -d); export HOME=$T/home; mkdir -p "$HOME/repos" "$T/bin" "$T/other"
cat >"$T/bin/gh" <<'E'
#!/data/data/com.termux/files/usr/bin/bash
echo "gh $*" >>"$STUBLOG"
case "$*" in "repo view"*) echo true ;; esac
E
cat >"$T/bin/git" <<E
#!/data/data/com.termux/files/usr/bin/bash
case "\$*" in *" pull "*) echo "git \$*" >>"\$STUBLOG"; exit 0 ;; esac
exec $REALGIT "\$@"
E
chmod +x "$T/bin/gh" "$T/bin/git"
export PATH=$T/bin:$PATH STUBLOG=$T/stub.log; : >"$STUBLOG"

mk() { git init -q -b main "$1"; git -C "$1" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i; git -C "$1" remote add origin "$2"; }
mk "$HOME/repos/FAKE" https://github.com/c10vis-poem/FAKE.git
mk "$HOME/repos/OTHER" https://github.com/someone/OTHER.git
mk "$HOME/repos/DIRTY" https://github.com/c10vis-poem/DIRTY.git; touch "$HOME/repos/DIRTY/x"
mk "$HOME/repos/BR" https://github.com/c10vis-poem/BR.git; git -C "$HOME/repos/BR" checkout -q -b feat

run() {  # sid tool cwd fp
  printf '{"session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s","command":"ls"}}' "$1" "$3" "$2" "$4" | bash "$HOOK"; echo $?
}
n() { sleep 1.5; wc -l <"$STUBLOG" | tr -d ' '; }
fails=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got '$2' want '$3')"; fails=$((fails+1)); fi; }

rc=$(run sessAAAA1111 Bash "$HOME/repos/FAKE" ""); chk "first call exit0" "$rc" 0
chk "first call launches sync (gh view,sync,git pull=3 lines)" "$(n)" 3
grep -q "gh repo sync c10vis-poem/FAKE" "$STUBLOG"; chk "gh repo sync args" $? 0
grep -q "pull --ff-only" "$STUBLOG"; chk "pull --ff-only" $? 0
rc=$(run sessAAAA1111 Read "" "$HOME/repos/FAKE/sub/f.txt"); chk "second call exit0" "$rc" 0
chk "second call same session no-op" "$(n)" 3
rc=$(run sessBBBB2222 Edit "" "$HOME/repos/FAKE/f"); chk "other session exit0" "$rc" 0
chk "different session relaunches" "$(n)" 6
rc=$(run sessAAAA1111 Bash "$T/other" ""); chk "non-repo exit0" "$rc" 0
rc=$(run sessAAAA1111 Bash "$HOME/repos/OTHER" ""); chk "non-c10vis exit0" "$rc" 0
chk "non-repo and non-c10vis no-op" "$(n)" 6
rc=$(run sessAAAA1111 Bash "$HOME/repos/DIRTY" ""); chk "dirty exit0" "$rc" 0
rc=$(run sessAAAA1111 Bash "$HOME/repos/BR" ""); chk "branch exit0" "$rc" 0
sleep 1.5
chk "dirty+branch: no pull" "$(grep -c pull "$STUBLOG")" 2
grep -q "not pulled: dirty" "$HOME/.claude/logs/sync-on-use.log"; chk "log dirty" $? 0
grep -q "not pulled: branch feat" "$HOME/.claude/logs/sync-on-use.log"; chk "log branch" $? 0
grep -q " sessAAAA FAKE synced" "$HOME/.claude/logs/sync-on-use.log"; chk "log line format" $? 0
rc=$(printf 'garbage' | bash "$HOOK"; echo $?); chk "garbage stdin exit0" "$rc" 0

s=$(date +%s%N); for i in 1 2 3 4 5 6 7 8 9 10; do run sessAAAA1111 Read "" "$HOME/repos/FAKE/f" >/dev/null; done
echo "no-op latency: $(( ($(date +%s%N)-s)/10000000 ))e-1 ms avg (incl. printf/bash spawn)"
rm -rf "$T"; echo "fails=$fails"; exit $fails
