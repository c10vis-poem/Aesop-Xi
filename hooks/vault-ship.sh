#!/data/data/com.termux/files/usr/bin/bash
# vault-ship: upload the vault (replaces GitSync's upload) and open the vault-sync -> main PR.
#   vault-ship            commit the vault, push to vault-sync, PR to main with auto-merge (merge commit)
#   vault-ship --dry-run  show what would be committed and pushed
# Run by hand any time, or by ship-session.sh at wrap-up (after the operator's "/ok push").
# main is protected (public repo: PR + secret scan + CI), so uploads go to vault-sync first.
# Shared storage can write empty git objects or empty files: never switch branches here; after
# every git write, fail on new empty objects and restore files emptied on disk from HEAD.
VAULT=${VAULT:-/data/data/com.termux/files/home/storage/shared/Documents/NovAExorpus}
REPO=${VAULT_REPO:-c10vis-poem/NovAExorpus}
dry=; [ "$1" = --dry-run ] && dry=1
cd "$VAULT" || { echo "vault-ship: no vault at $VAULT" >&2; exit 1; }
say() { echo "vault-ship: $*"; }
die() { echo "vault-ship: $*" >&2; exit 1; }

[ -e .git/rebase-merge ] || [ -e .git/rebase-apply ] || [ -e .git/MERGE_HEAD ] && die "a rebase or merge is in progress; finish or abort it first"
[ "$(git branch --show-current)" = main ] || die "the vault must be on main (it is on '$(git branch --show-current)'); never switch branches here"
git fetch -q origin || die "fetch failed"

check_objects() {  # empty object files written in the last hour = a failed write
  local n; n=$(find .git/objects -type f -empty -mmin -60 | wc -l)
  [ "$n" -eq 0 ] || die "$n empty git object(s) just written (storage write failure); nothing pushed. Delete them (find .git/objects -type f -empty -mmin -60 -delete) and run again"
}
restore_emptied() {  # files emptied on disk that are not empty in HEAD
  local f n=0
  while IFS= read -r -d '' f; do
    [ -f "$f" ] && [ ! -s "$f" ] && [ "$(git cat-file -s "HEAD:$f" 2>/dev/null || echo 0)" -gt 0 ] \
      && git checkout -- "$f" && n=$((n+1))
  done < <(git diff --name-only -z)
  [ "$n" -gt 0 ] && say "restored $n file(s) emptied by a failed write"
}

# 1. bring in what is already on GitHub (no branch switch: merge into local main)
for r in origin/main origin/vault-sync; do
  git merge-base --is-ancestor "$r" HEAD 2>/dev/null && continue
  [ -n "$dry" ] && { say "would merge $r"; continue; }
  git merge -q --no-edit "$r" >/dev/null || die "merging $r failed; resolve, then run again"
  check_objects; restore_emptied
done

# 2. commit the vault's changes (.gitignore applies; the gitleaks hook scans the commit)
n=$(git status --porcelain | wc -l)
if [ "$n" -gt 0 ]; then
  if [ -n "$dry" ]; then say "would commit $n change(s):"; git -c core.quotepath=off status --porcelain | head -20
  else
    git add -A && git commit -q -m "vault: $(hostname 2>/dev/null || echo phone) $(date '+%F %H:%M')" || die "commit refused (secret scan?)"
    check_objects; restore_emptied; say "committed $n change(s) as $(git log -1 --format=%h)"
  fi
else say "nothing to commit"; fi

# 3. push to vault-sync, then the PR to main (auto-merge with a merge commit once CI is green)
ahead=$(git rev-list --count origin/vault-sync..HEAD 2>/dev/null || git rev-list --count origin/main..HEAD)
[ "$ahead" -gt 0 ] || { say "vault-sync is up to date"; exit 0; }
[ -n "$dry" ] && { say "would push $ahead commit(s) to vault-sync and open the PR to main"; exit 0; }
git push -q origin HEAD:vault-sync || die "push to vault-sync refused (secret scan, or vault-sync diverged)"
pr=$(gh pr list -R "$REPO" --head vault-sync --state open --json url -q '.[0].url')
[ -n "$pr" ] || pr=$(gh pr create -R "$REPO" --base main --head vault-sync --title "vault sync $(date +%F)" \
  --body "$(printf 'Vault upload by vault-ship.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')")
gh pr merge "$pr" -R "$REPO" --auto --merge >/dev/null 2>&1 && say "pushed $ahead commit(s); $pr auto-merges when CI is green" \
  || say "pushed $ahead commit(s); $pr is open (auto-merge not set)"
