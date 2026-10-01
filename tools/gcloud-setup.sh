#!/usr/bin/env bash
# aesop-xi/tools/gcloud-setup.sh
#
# One-shot: creates GCloud VM + bucket + firewall + provisions everything.
# Run from Termux after: gcloud auth login && gcloud config set project YOUR_PROJECT_ID
#
# What it does:
#   1. Creates a storage bucket for persistent project data
#   2. Creates firewall rule for OmniRoute port 20128
#   3. Creates a c3-standard-8 VM (8 vCPU, 32GB, Debian 12, 20GB SSD)
#   4. VM startup script auto-installs:
#      - Node 22, pnpm, git, build-essential, jq, nginx, certbot
#      - Postgres 17 + pgvector
#      - gcsfuse (mounts your bucket at /mnt/data)
#      - OmniRoute (cloned, installed, systemd service on port 20128)
#      - terrestrial-brain (cloned, npm deps, migrations, systemd service on port 8000)
#   5. Prints the external IP and connection instructions

set -euo pipefail

# ---------- CONFIG ----------
PROJECT_ID="${GCLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "ERROR: No project set. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

VM_NAME="novaxorpus-dev"
ZONE="us-central1-a"
MACHINE_TYPE="c3-standard-8"
BOOT_DISK_SIZE="20GB"
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"
BUCKET_NAME="${PROJECT_ID}-novaxorpus-data"
OMNIROUTE_PORT=20128
TB_PORT=8000
GITHUB_ORG="c10vis-poem"

log() { echo "[gcloud-setup] $*"; }

log "Project: $PROJECT_ID"
log "VM: $VM_NAME ($MACHINE_TYPE) in $ZONE"
log "Bucket: gs://$BUCKET_NAME"

# ---------- 1. Storage bucket ----------
log "Creating bucket..."
gcloud storage buckets create "gs://$BUCKET_NAME" \
  --location=us-central1 \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access \
  2>/dev/null && log "Bucket created." || log "Bucket exists, skipping."

# ---------- 2. Firewall rules ----------
log "Creating firewall rules..."
gcloud compute firewall-rules create allow-omniroute \
  --allow=tcp:$OMNIROUTE_PORT \
  --target-tags=omniroute \
  --description="OmniRoute MCP gateway" \
  2>/dev/null && log "Firewall rule created." || log "Firewall rule exists, skipping."

gcloud compute firewall-rules create allow-tb-mcp \
  --allow=tcp:$TB_PORT \
  --target-tags=omniroute \
  --description="terrestrial-brain MCP" \
  2>/dev/null && log "TB firewall rule created." || log "TB firewall rule exists, skipping."

# ---------- 3. Create VM ----------
log "Creating VM (this takes ~60s)..."

gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size="$BOOT_DISK_SIZE" \
  --boot-disk-type=pd-ssd \
  --tags=omniroute,http-server,https-server \
  --scopes=storage-full,compute-ro,logging-write \
  --metadata=bucket-name="$BUCKET_NAME",github-org="$GITHUB_ORG",omniroute-port="$OMNIROUTE_PORT",tb-port="$TB_PORT",startup-script='#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/nova-startup.log) 2>&1
echo "========== NovÆxorpus VM Startup $(date -Iseconds) =========="

BUCKET=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/bucket-name" -H "Metadata-Flavor: Google")
GITHUB_ORG=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-org" -H "Metadata-Flavor: Google")
OMNIROUTE_PORT=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/omniroute-port" -H "Metadata-Flavor: Google")
TB_PORT=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/tb-port" -H "Metadata-Flavor: Google")

export DEBIAN_FRONTEND=noninteractive

# ---- System packages ----
echo "[1/9] Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
  git curl wget build-essential jq unzip \
  nginx certbot python3-certbot-nginx \
  postgresql postgresql-contrib libpq-dev \
  lsb-release gnupg apt-transport-https ca-certificates

# ---- Node 22 LTS ----
echo "[2/9] Installing Node.js 22..."
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi
npm install -g pnpm 2>/dev/null || true
echo "Node $(node -v), npm $(npm -v), pnpm $(pnpm -v 2>/dev/null || echo n/a)"

# ---- gcsfuse ----
echo "[3/9] Installing gcsfuse and mounting bucket..."
if ! command -v gcsfuse &>/dev/null; then
  GCSFUSE_REPO="gcsfuse-$(lsb_release -cs)"
  echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" \
    > /etc/apt/sources.list.d/gcsfuse.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  apt-get update -qq
  apt-get install -y -qq gcsfuse
fi
mkdir -p /mnt/data
if ! mountpoint -q /mnt/data; then
  gcsfuse --implicit-dirs "$BUCKET" /mnt/data
  grep -q "$BUCKET" /etc/fstab || \
    echo "$BUCKET /mnt/data gcsfuse rw,allow_other,implicit_dirs,_netdev 0 0" >> /etc/fstab
fi
echo "Bucket gs://$BUCKET mounted at /mnt/data"

# ---- Postgres + pgvector ----
echo "[4/9] Setting up Postgres + pgvector..."
PG_VER=$(pg_lsclusters -h 2>/dev/null | awk "{print \$1}" | head -1)
PG_VER=${PG_VER:-17}
systemctl enable postgresql
systemctl start postgresql

# Install pgvector from package or source
apt-get install -y -qq "postgresql-${PG_VER}-pgvector" 2>/dev/null || {
  echo "Building pgvector from source..."
  cd /tmp
  [ -d pgvector ] || git clone --depth 1 https://github.com/pgvector/pgvector.git
  cd pgvector && make clean && make && make install
  cd / && rm -rf /tmp/pgvector
}

# Create role + database
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='"'"'brain_app'"'"'" | grep -q 1 || {
  sudo -u postgres psql <<EOSQL
CREATE ROLE brain_app LOGIN PASSWORD '"'"'brain_local_dev'"'"';
CREATE DATABASE terrestrial_brain OWNER brain_app;
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"'"'anon'"'"') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$;
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"'"'authenticated'"'"') THEN CREATE ROLE authenticated NOLOGIN; END IF; END \$\$;
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"'"'service_role'"'"') THEN CREATE ROLE service_role NOLOGIN; END IF; END \$\$;
GRANT service_role TO brain_app;
EOSQL
}

sudo -u postgres psql -d terrestrial_brain <<EOSQL
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS \$f\$ SELECT '"'"'service_role'"'"'::text; \$f\$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS \$f\$ SELECT NULL::uuid; \$f\$;
GRANT ALL ON SCHEMA extensions TO brain_app;
GRANT ALL ON SCHEMA public TO brain_app;
GRANT USAGE ON SCHEMA auth TO brain_app;
GRANT EXECUTE ON FUNCTION auth.role() TO brain_app;
GRANT EXECUTE ON FUNCTION auth.uid() TO brain_app;
ALTER DATABASE terrestrial_brain SET search_path TO public, extensions;
EOSQL
echo "Postgres + pgvector ready"

# ---- Clone repos ----
echo "[5/9] Cloning repositories..."
mkdir -p /opt/novaxorpus
cd /opt/novaxorpus

for repo in OmniRoute NovA-terrestrial-brain aesop-xi NovAExorpus; do
  [ -d "$repo" ] || git clone "https://github.com/${GITHUB_ORG}/${repo}.git"
done

# ---- OmniRoute install ----
echo "[6/9] Installing OmniRoute..."
cd /opt/novaxorpus/OmniRoute
pnpm install --frozen-lockfile 2>/dev/null || npm install

# ---- terrestrial-brain install + migrations ----
echo "[7/9] Installing terrestrial-brain..."
cd /opt/novaxorpus/NovA-terrestrial-brain/local-mcp
npm install --ignore-scripts

# Generate MCP access key
if [ ! -f .env.local ]; then
  MCP_KEY=$(openssl rand -hex 24)
  cat > .env.local <<ENVEOF
MCP_ACCESS_KEY=$MCP_KEY
TB_MCP_URL=http://localhost:${TB_PORT}/mcp
TB_MCP_KEY=$MCP_KEY
ENVEOF
  chmod 600 .env.local
fi
MCP_KEY=$(grep MCP_ACCESS_KEY .env.local | cut -d= -f2)

# Run migrations
echo "Running terrestrial-brain migrations..."
export PGPASSWORD="brain_local_dev"
for f in /opt/novaxorpus/NovA-terrestrial-brain/supabase/migrations/*.sql; do
  psql -h 127.0.0.1 -U brain_app -d terrestrial_brain -v ON_ERROR_STOP=0 -f "$f" 2>&1 \
    | grep -i error | head -1 | sed "s/^/  WARN: $(basename "$f"): /" || true
done

# ---- Systemd services ----
echo "[8/9] Creating systemd services..."

# OmniRoute service
cat > /etc/systemd/system/omniroute.service <<UNIT
[Unit]
Description=OmniRoute AI Gateway
After=network.target postgresql.service

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

# terrestrial-brain service
cat > /etc/systemd/system/terrestrial-brain.service <<UNIT
[Unit]
Description=terrestrial-brain MCP Server
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/novaxorpus/NovA-terrestrial-brain/supabase/functions/terrestrial-brain-mcp
ExecStart=/usr/bin/deno run --allow-net --allow-env --allow-read --allow-write index.ts
Restart=always
RestartSec=5
Environment=LOCAL_PG_URL=postgres://brain_app:brain_local_dev@127.0.0.1:5432/terrestrial_brain
Environment=MCP_ACCESS_KEY=${MCP_KEY}
Environment=OPENROUTER_BASE=http://127.0.0.1:${OMNIROUTE_PORT}/v1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

# Install deno if not present (x86 Debian, not Termux)
if ! command -v deno &>/dev/null; then
  curl -fsSL https://deno.land/install.sh | sh
  ln -sf /root/.deno/bin/deno /usr/bin/deno 2>/dev/null || true
fi

systemctl enable omniroute terrestrial-brain
systemctl start omniroute terrestrial-brain

# ---- Verify ----
echo "[9/9] Verifying services..."
sleep 3
for svc in omniroute terrestrial-brain; do
  if systemctl is-active --quiet "$svc"; then
    echo "  $svc: RUNNING"
  else
    echo "  $svc: FAILED — check: journalctl -u $svc"
  fi
done

EXTERNAL_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")
echo ""
echo "=========================================="
echo "  NovÆxorpus VM READY"
echo "  External IP:      $EXTERNAL_IP"
echo "  OmniRoute:        http://$EXTERNAL_IP:${OMNIROUTE_PORT}"
echo "  terrestrial-brain: http://$EXTERNAL_IP:${TB_PORT}/mcp"
echo "  Bucket:           /mnt/data (gs://$BUCKET)"
echo "  Repos:            /opt/novaxorpus/"
echo "=========================================="
echo "Startup complete at $(date -Iseconds)"
'

# ---------- 4. Wait and report ----------
log ""
log "VM creating... waiting for external IP..."
sleep 10

EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)

log ""
log "============================================"
log "  VM CREATED: $VM_NAME"
log "  External IP:       $EXTERNAL_IP"
log "  OmniRoute:         http://$EXTERNAL_IP:$OMNIROUTE_PORT"
log "  terrestrial-brain: http://$EXTERNAL_IP:$TB_PORT/mcp"
log "  Bucket:            gs://$BUCKET_NAME (mounted at /mnt/data)"
log ""
log "  SSH:    gcloud compute ssh $VM_NAME --zone=$ZONE"
log "  Logs:   gcloud compute ssh $VM_NAME --zone=$ZONE -- tail -f /var/log/nova-startup.log"
log "  Stop:   gcloud compute instances stop $VM_NAME --zone=$ZONE"
log "  Start:  gcloud compute instances start $VM_NAME --zone=$ZONE"
log "============================================"
log ""
log "Startup script is installing everything (~3-5 min)."
log "Once done, set on your phone:"
log ""
log "  mkdir -p ~/.omniroute"
log "  echo 'OMNIROUTE_URL=http://$EXTERNAL_IP:$OMNIROUTE_PORT' > ~/.omniroute/.env"
log ""
