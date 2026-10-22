#!/bin/bash
# Print inputSchema for selected MCP tools: schemas.sh URL "header" tool1 tool2...
U=$1; H=$2; shift 2
A=(-s -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "$H")
sid=$(curl "${A[@]}" -D - -o /dev/null -X POST "$U" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
S=(); [ -n "$sid" ] && S=(-H "Mcp-Session-Id: $sid")
curl "${A[@]}" "${S[@]}" -X POST "$U" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
curl "${A[@]}" "${S[@]}" -X POST "$U" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | sed -n 's/^data: //p;/^{/p' | python3 -c "
import json,sys
want=set(sys.argv[1:])
for line in sys.stdin:
  line=line.strip()
  if not line: continue
  d=json.loads(line)
  for t in d.get('result',{}).get('tools',[]):
    if t['name'] in want: print(t['name'], json.dumps(t.get('inputSchema',{}).get('properties',{}))[:400], 'required=',t.get('inputSchema',{}).get('required'))
" "$@"
