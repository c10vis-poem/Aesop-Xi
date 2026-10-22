#!/bin/bash
# Start mem0 API + dashboard, create the admin + an API key once. Secrets go to files, never stdout.
set -euo pipefail
cd /opt/dumbass
docker compose up -d mem0 mem0-dashboard 2>&1 | tail -1
A=http://127.0.0.1:8888
for i in $(seq 1 60); do [ "$(curl -s -o /dev/null -w '%{http_code}' $A/auth/setup-status)" = 200 ] && break; sleep 3; done
echo "mem0 api: $(curl -s $A/auth/setup-status)"
umask 077; SEC=/opt/dumbass/secrets.env; touch $SEC
if ! grep -q ^MEM0_ADMIN_PASSWORD= $SEC; then echo "MEM0_ADMIN_EMAIL=admin@omniroute-x86.local" >> $SEC; echo "MEM0_ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc A-Za-z0-9 | head -c 20)" >> $SEC; fi
. $SEC
payload() { python3 -c 'import json,sys; print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "$@"; }
if [ "$(curl -s $A/auth/setup-status | python3 -c 'import json,sys;print(json.load(sys.stdin).get("needsSetup"))')" = True ]; then
  curl -s -X POST $A/auth/register -H "Content-Type: application/json" -d "$(payload name=Operator email=$MEM0_ADMIN_EMAIL password=$MEM0_ADMIN_PASSWORD)" | python3 -c 'import json,sys;d=json.load(sys.stdin);print("register:", "ok" if "access_token" in d else d)'
fi
TOKEN=$(curl -s -X POST $A/auth/login -H "Content-Type: application/json" -d "$(payload email=$MEM0_ADMIN_EMAIL password=$MEM0_ADMIN_PASSWORD)" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
echo "login: ok"
if ! grep -q ^RP_MEM0_KEY= $SEC; then
  KEY=$(curl -s -X POST $A/api-keys -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{"label":"retrieval-planner"}' | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("key") or d.get("api_key") or "")')
  [ -n "$KEY" ] && echo "RP_MEM0_KEY=$KEY" >> $SEC && echo "api key: created (saved to $SEC)"
fi
echo "dashboard http=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000)"
