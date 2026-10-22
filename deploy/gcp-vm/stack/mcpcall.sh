#!/bin/bash
# mcpcall.sh URL "header" TOOL 'json-args'  -> prints text content of an MCP tools/call
U=$1; H=$2; T=$3; ARGS=$4
A=(-s -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "$H")
sid=$(curl "${A[@]}" -D - -o /dev/null -X POST "$U" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
S=(); [ -n "$sid" ] && S=(-H "Mcp-Session-Id: $sid")
curl "${A[@]}" "${S[@]}" -X POST "$U" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
curl "${A[@]}" "${S[@]}" -X POST "$U" -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$T\",\"arguments\":$ARGS}}" | sed -n 's/^data: //p;/^{/p' | python3 -c '
import json,sys
for l in sys.stdin:
  l=l.strip()
  if not l: continue
  d=json.loads(l)
  if "error" in d: print("ERROR", d["error"]); continue
  r=d.get("result",{}); print(("ISERROR " if r.get("isError") else "")+"\n".join(c.get("text","") for c in r.get("content",[]) if c.get("type")=="text")[:900])'
