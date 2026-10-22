#!/bin/bash
# Clone the vault (c10vis-poem/NovAExorpus) to ~/vault and install a MANUAL `vault-sync ~/vault` command.
# No timer, by operator decision: sync only when run by hand. Pushes only with a deploy-key remote.
set -euo pipefail
V=~/vault
[ -d "$V/.git" ] || git clone -q https://github.com/c10vis-poem/NovAExorpus.git "$V"
git -C "$V" config pull.rebase true
git -C "$V" config user.name  "omniroute-x86"
git -C "$V" config user.email "omniroute-x86@users.noreply.github.com"

sudo tee /usr/local/bin/vault-sync >/dev/null <<'EOF'
#!/bin/sh
# Pull (rebase) then push local commits if the remote allows writes. Never force.
cd "$1" || exit 1
git add -A && git diff --cached --quiet || git commit -qm "vault: sync from omniroute-x86 $(date -u +%FT%TZ)"
git pull -q --rebase --autostash || { git rebase --abort 2>/dev/null; logger -t vault-sync "pull conflict, left for manual merge"; exit 1; }
case "$(git remote get-url origin)" in git@*) git push -q || logger -t vault-sync "push failed";; esac
EOF
sudo chmod 755 /usr/local/bin/vault-sync
