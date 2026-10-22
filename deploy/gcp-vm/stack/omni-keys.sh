#!/bin/bash
# Create OmniRoute API keys for services and write them into their env files. Prints no secrets.
set -euo pipefail
B=http://127.0.0.1:20128; J=$(mktemp); trap 'rm -f $J' EXIT
PW=$(cat /opt/dumbass/omniroute/admin-password)
code=$(curl -s -o /tmp/login.out -w "%{http_code}" -c $J -X POST $B/api/auth/login -H "Content-Type: application/json" -d "{\"password\":\"$PW\"}")
echo "login http=$code $(head -c 120 /tmp/login.out | tr -d '\n' | sed -E 's/"(token|jwt)":"[^"]*"/"\1":"<redacted>"/g')"; rm -f /tmp/login.out
[ "$code" = 200 ] || exit 1
mk() { curl -s -b $J -X POST $B/api/keys -H "Content-Type: application/json" -d "{\"name\":\"$1\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])'; }
setkv() { f=$1 k=$2 v=$3; sudo sed -i "s|^$k=.*|$k=$v|" "$f"; grep -q "^$k=$v" "$f" && echo "set $k in $f"; }
grep -q "^OPENROUTER_API_KEY=set-after" /opt/dumbass/tb.env && setkv /opt/dumbass/tb.env OPENROUTER_API_KEY "$(mk terrestrial-brain)"
grep -q "^OPENAI_API_KEY=set-after" /opt/dumbass/mem0.env && setkv /opt/dumbass/mem0.env OPENAI_API_KEY "$(mk mem0)"
curl -s -b $J $B/api/keys | python3 -c 'import json,sys; d=json.load(sys.stdin); ks=d if isinstance(d,list) else d.get("keys",d.get("data",[])); print("keys now:", ", ".join(k.get("name","?") for k in ks))'
