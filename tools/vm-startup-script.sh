#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/nova-startup.log) 2>&1
echo "========== NovAExorpus VM Startup $(date -Iseconds) =========="

export DEBIAN_FRONTEND=noninteractive

GITHUB_ORG="c10vis-poem"
OMNIROUTE_PORT=20128

# ---- System packages ----
apt-get update -qq
apt-get install -y -qq \
  git curl wget build-essential jq unzip \
  nginx certbot python3-certbot-nginx \
  python3 python3-pip python3-venv \
  lsb-release gnupg apt-transport-https ca-certificates

# ---- Node 22 + pnpm ----
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi
npm install -g pnpm 2>/dev/null || true

# ---- OmniRoute ----
mkdir -p /opt/novaxorpus
cd /opt/novaxorpus
[ -d OmniRoute ] || git clone "https://github.com/${GITHUB_ORG}/OmniRoute.git"
cd OmniRoute
pnpm install --frozen-lockfile 2>/dev/null || npm install

cat > /etc/systemd/system/omniroute.service <<UNIT
[Unit]
Description=OmniRoute AI Gateway
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/novaxorpus/OmniRoute
ExecStart=/usr/bin/node bin/omniroute.mjs --port ${OMNIROUTE_PORT}
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable omniroute
systemctl start omniroute

# ---- NotebookLM-py ----
cd /opt/novaxorpus
[ -d notebooklm-py ] || git clone "https://github.com/${GITHUB_ORG}/notebooklm-py.git" 2>/dev/null || true
if [ -d notebooklm-py ]; then
  cd notebooklm-py
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt 2>/dev/null || true
fi

# ---- Verify ----
sleep 3
if systemctl is-active --quiet omniroute; then
  echo "OmniRoute: RUNNING on port $OMNIROUTE_PORT"
else
  echo "OmniRoute: FAILED — check: journalctl -u omniroute"
fi

EXTERNAL_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google" || echo "UNKNOWN")
echo ""
echo "=========================================="
echo "  VM READY"
echo "  External IP:  $EXTERNAL_IP"
echo "  OmniRoute:    http://$EXTERNAL_IP:${OMNIROUTE_PORT}"
echo "  Repos:        /opt/novaxorpus/"
echo "=========================================="
echo "Done at $(date -Iseconds)"
