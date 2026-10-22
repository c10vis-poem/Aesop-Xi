#!/data/data/com.termux/files/usr/bin/bash
# SessionStart hook: every plugin marketplace backed by a c10vis-poem fork gets
# `gh repo sync` (+ ff pull for local clones), then the marketplace and its enabled
# plugins are refreshed. sync-on-use.sh only covers ~/repos clones touched by a tool;
# plugin caches never pass through it. Detached; always exit 0.

run() {
  local log="$HOME/.claude/logs/plugin-fork-sync.log" C="$HOME/.local/bin/claude" sid=${1:0:8}
  mkdir -p "${log%/*}"
  say() { echo "$(date '+%F %T') $sid $*" >>"$log"; }
  python3 - "$HOME/.claude/plugins/known_marketplaces.json" "$HOME/.claude/settings.json" <<'EOF' |
import json, os, sys
mk = json.load(open(sys.argv[1]))
on = [k for k, v in json.load(open(sys.argv[2])).get("enabledPlugins", {}).items() if v]
repos = os.path.expanduser("~/repos/")
for name, v in mk.items():
    s = v.get("source", {})
    if s.get("source") == "github" and s.get("repo", "").startswith("c10vis-poem/"):
        repo, d = s["repo"].split("/", 1)[1], ""
    elif s.get("source") == "directory" and s.get("path", "").startswith(repos):
        d = s["path"].rstrip("/"); repo = d[len(repos):].split("/")[0]; d = repos + repo
    else:
        continue
    plugins = ",".join(k for k in on if k.endswith("@" + name))
    print(f"{name}|{repo}|{d}|{plugins}")
EOF
  while IFS='|' read -r name repo dir plugins; do
    if [ -n "$dir" ]; then
      bash "$HOME/.claude/hooks/sync-on-use.sh" --sync "$1" "$dir" "$repo"   # gh sync + ff pull, logs to sync-on-use.log
    elif out=$(gh repo sync "c10vis-poem/$repo" 2>&1); then say "$repo synced"
    else say "$repo sync FAILED: ${out//$'\n'/ }"; fi
    "$C" plugin marketplace update "$name" >/dev/null 2>&1 && say "$name marketplace updated" || say "$name marketplace update FAILED"
    IFS=, read -ra ps <<<"$plugins"
    for p in "${ps[@]}"; do "$C" plugin update "$p" >/dev/null 2>&1 && say "$p updated" || say "$p update FAILED"; done
  done
  # Every other fork on the account: sync on GitHub, ff-pull the local clone if one exists.
  gh repo list c10vis-poem --fork --limit 1000 --json name --jq '.[].name' | while read -r repo; do
    if [ -d "$HOME/repos/$repo/.git" ]; then bash "$HOME/.claude/hooks/sync-on-use.sh" --sync "$1" "$HOME/repos/$repo" "$repo"
    elif out=$(gh repo sync "c10vis-poem/$repo" 2>&1); then say "$repo synced"
    elif [[ $out == *diverging* ]]; then
      # Same policy as sync-on-use.sh: never force; bring upstream in by PR.
      read -r head base < <(gh api "repos/c10vis-poem/$repo" --jq '"\(.parent.owner.login):\(.parent.default_branch) \(.default_branch)"')
      [ "$(gh pr list --repo "c10vis-poem/$repo" --head "${head#*:}" --state open --json number --jq length)" -gt 0 ] \
        || gh pr create --repo "c10vis-poem/$repo" --base "$base" --head "$head" --title "sync: merge upstream $head" --body "Fork diverged; upstream brought in by PR (never force-synced)." >/dev/null 2>&1
      say "$repo diverged: upstream PR ensured"
    else say "$repo sync FAILED: ${out//$'\n'/ }"; fi
  done
}

if [ "$1" = --run ]; then run "$2"; exit 0; fi
sid=$(jq -r '.session_id // ""' 2>/dev/null)
nohup bash "$0" --run "$sid" >/dev/null 2>&1 </dev/null &
exit 0
