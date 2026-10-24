#!/data/data/com.termux/files/usr/bin/bash
# Shared test setup: throwaway sandbox under tests/, fake vault, local bare remotes, stub gh.
HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d "$HOOKS/tests/tmp.XXXXXX")
trap 'rm -rf "$T"' EXIT
export RECAPS_REPO=$T/no-recaps-repo REPOS_DIR=$T/repos
export VAULT=$T/vault STATE_DIR=$T/state PROJECTS_DIR=$T/projects SHIP_LOG=$T/ship.log
export ORIGIN_RE="^$T/remotes/"
# The phone sets core.hooksPath globally to the gitleaks dispatcher; give the sandbox the same so
# pre-commit / pre-push gitleaks run for real here and in CI (a `git -c core.hooksPath=` still wins).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$HOOKS/git-hooks"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$T/bin" "$T/remotes" "$T/work" "$PROJECTS_DIR/p" "$VAULT"
cat > "$T/bin/gh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "\$*" >> "$T/gh.log"
[ "\$1 \$2" = "pr create" ] && echo "https://github.com/stub/repo/pull/1"
case "\$*" in
  api\ repos/*contents/*) printf 'jobs:\n  check:\n    runs-on: x\n' ;;
  api\ repos/*actions/workflows*workflows\[\]*) echo .github/workflows/ci.yml ;;
  api\ repos/*actions/workflows*) echo 1 ;;
  api\ repos/*required_status_checks*length*) echo 1 ;;
  api\ repos/*required_status_checks*) echo check ;;
esac   # ci-ready.sh: CI plus a required status check named check that a job produces
exit 0
EOF
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
git init -q "$VAULT"

pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
finish() { echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]; }

# mkrepo NAME -> clone at $T/work/NAME with a.txt b.txt committed on main, origin = local bare repo
mkrepo() {
  git init -q --bare -b main "$T/remotes/$1.git"
  git clone -q "$T/remotes/$1.git" "$T/work/$1" 2>/dev/null
  ( cd "$T/work/$1" && git switch -q -c main 2>/dev/null; echo a > a.txt; echo b > b.txt
    git add . && git commit -q -m init && git push -q -u origin main && git remote set-head origin main ) >/dev/null 2>&1
}

# hook EVENT-JSON -> run the ledger hook, returns its exit code
ledger() { bash "$HOOKS/session-ledger.sh" <<<"$1"; }
write_ev() { jq -nc --arg s "$SID" --arg p "$1" '{session_id:$s,cwd:"/",tool_name:"Write",tool_input:{file_path:$p},tool_response:{}}'; }
bash_ev() { jq -nc --arg s "$SID" --arg c "$1" --arg d "$2" '{session_id:$s,cwd:$d,tool_name:"Bash",tool_input:{command:$c},tool_response:{}}'; }
