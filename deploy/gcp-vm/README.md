# GCP VM — OmniRoute control plane host

VM: `omniroute-x86` · project `project-alchemist-490416` · zone `us-central1-a`
e2-standard-4 (4 vCPU / 16 GB, x86_64) · Ubuntu 24.04 · 50 GB pd-balanced.
~$0.134/hr while running + ~$5/mo disk. External IP is ephemeral.

## Cost guards (install first, every rebuild)

| File | What it does |
|---|---|
| `idle-shutdown` → `/usr/local/bin/` | Powers off after 30 min with no inbound connection and load < 0.5 |
| `idle-shutdown.service` / `.timer` → `/etc/systemd/system/` | Runs the check every 5 min |
| Resource policy `nightly-stop-4am` | Hard stop 4 AM America/Los_Angeles (needs compute service-agent `roles/compute.instanceAdmin.v1`) |

## Base system

`01-base.sh` — Docker + Compose, Tailscale, Node 22, VS Code, Chrome,
Chrome Remote Desktop (XFCE session), Obsidian, Arc-Dark theme. Idempotent.

```sh
gcloud compute scp deploy/gcp-vm/01-base.sh omniroute-x86:/tmp/ --zone us-central1-a
gcloud compute ssh omniroute-x86 --zone us-central1-a --command 'bash /tmp/01-base.sh'
```

## Phone (Termux) controls — copy to `~/bin/`

| Script | Use |
|---|---|
| `phone/vm` | `vm on \| off \| status \| ssh \| desktop` (old ARM VM: `VM_NAME=omniroute-brain vm ...`) |
| `phone/close-firewall` | Deletes public firewall rules; leaves SSH only |

## Service stack (`stack/`) — rebuild order

Run as the normal user (not `sudo`) so `${HOME}` resolves to the user's home. Copy `stack/` to `/opt/dumbass/`.

| Step | Command (on the VM) | Result |
|---|---|---|
| 1 | `./make-env.sh && docker compose up -d postgres neo4j` | Postgres+pgvector (`terrestrial_brain`, `mem0`, `mem0_app`) and Neo4j on 127.0.0.1 |
| 2 | `./terrestrial-brain.sh` then `./tb-schema.sh` | TB MCP :8000 (header `x-brain-key`); schema from the fork's migrations. Re-apply `20260704000001_fix_db_security_policies.sql` as `postgres` |
| 3 | `./code-review-graph.sh` (edit unit to `--host 172.17.0.1`) | code-review-graph MCP on the Docker bridge :5555 |
| 4 | `cd omniroute && docker compose build && docker compose up -d` | OmniRoute from `c10vis-poem/NvAEx-OmniRoute`; data dir must be `chown 1000:1000` |
| 5 | `./omni-keys.sh` | OmniRoute API keys for TB + mem0 written into their env files |
| 6 | `./make-mem0-env.sh && docker compose up -d mem0 mem0-dashboard && ./mem0-bootstrap.sh` | mem0 API :8888 + dashboard :3000, admin + key in `secrets.env` |
| 7 | `./install-plugins.sh` | continual-harness → retrieval-planner → reasoning-bank (install order = hook order) |

Model IDs through OmniRoute need the provider prefix, e.g. `openrouter/openai/gpt-4o-mini`.
Test helpers: `mcptest.sh URL [header]` (initialize + tools/list), `mcpcall.sh URL header TOOL 'json'`, `schemas.sh`.

## Network

Firewall: SSH (22), ICMP, and GCP-internal only. Everything else is reached over Tailscale.

An on-device copy of these scripts lives at `Documents/vm-setup/` (shared storage).
