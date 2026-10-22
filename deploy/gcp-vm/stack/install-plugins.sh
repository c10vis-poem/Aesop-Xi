#!/bin/bash
# Install/refresh the dumbass OmniRoute plugins from the fork's feature branch. Prints no secrets.
set -euo pipefail
O=/opt/dumbass/omniroute; R=~/repos/NvAEx-OmniRoute; SRC=$O/data/plugin-src
git -C $R fetch -q --depth 1 origin feat/dumbass-orchestration
echo "plugins from feat/dumbass-orchestration @ $(git -C $R rev-parse --short FETCH_HEAD)"
sudo rm -rf $SRC && mkdir -p /tmp/ps && rm -rf /tmp/ps/* && git -C $R archive FETCH_HEAD dumbass-plugins | tar x -C /tmp/ps
sudo mkdir -p $SRC && sudo cp -r /tmp/ps/dumbass-plugins/{continual-harness,reasoning-bank,retrieval-planner} $SRC/ && rm -rf /tmp/ps
. /opt/dumbass/tb.env
M=$(grep -s ^RP_MEM0_KEY= /opt/dumbass/secrets.env | cut -d= -f2 || true)
python3 - "$SRC/retrieval-planner/config.json" "$MCP_ACCESS_KEY" "${M:-}" <<'PY'
import json, sys
p, tb, m0 = sys.argv[1:]
cfg = {"terrestrialBrain": {"url": "http://host.docker.internal:8000/mcp", "key": tb},
       "codeReviewGraph": {"url": "http://host.docker.internal:5555/mcp"},
       "mem0": {"url": "http://mem0:8000", "apiKey": m0, "userId": "operator"},
       "modelContextTokens": {"claude": 200000, "gemini": 1000000, "gpt-4o": 128000, "gpt-5": 400000}}
json.dump(cfg, open("/tmp/rpcfg.json", "w"))
PY
sudo mv /tmp/rpcfg.json $SRC/retrieval-planner/config.json && sudo chmod 600 $SRC/retrieval-planner/config.json && sudo chown -R 1000:1000 $SRC
grep -q ^OMNIROUTE_PLUGINS_DIR= $O/.env || { echo "OMNIROUTE_PLUGINS_DIR=/app/data/plugins" >> $O/.env; (cd $O && docker compose up -d --force-recreate omniroute >/dev/null 2>&1); }
for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/api/monitoring/health)" = 200 ] && break; sleep 3; done
J=$(mktemp); trap 'rm -f $J' EXIT
curl -s -o /dev/null -c $J -X POST http://127.0.0.1:20128/api/auth/login -H "Content-Type: application/json" -d "{\"password\":\"$(cat $O/admin-password)\"}"
for p in continual-harness retrieval-planner reasoning-bank; do  # hooks run in install order (loader ignores manifest priority)
  curl -s -o /dev/null -b $J -X DELETE http://127.0.0.1:20128/api/plugins/$p  # refresh: uninstall old copy (data in dataDir is kept)
  inst=$(curl -s -b $J -X POST http://127.0.0.1:20128/api/plugins -H "Content-Type: application/json" -d "{\"path\":\"/app/data/plugin-src/$p\"}" | head -c 160)
  act=$(curl -s -b $J -X POST http://127.0.0.1:20128/api/plugins/$p/activate | head -c 160)
  echo "$p: install=$inst | activate=$act"
done
curl -s -b $J http://127.0.0.1:20128/api/plugins | python3 -c 'import json,sys; d=json.load(sys.stdin); ps=d if isinstance(d,list) else d.get("plugins",d.get("data",[])); [print(" ", p.get("name"), p.get("status"), p.get("version")) for p in ps]'
