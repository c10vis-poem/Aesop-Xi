#!/bin/bash
# Usage: mcptest.sh URL [extra-header]  -> MCP initialize + tools/list round trip
U=$1; H=${2:-X-None: 1}; rm -f /tmp/mcp.init  # never read a stale reply
A=(-s -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "$H")
sid=$(curl "${A[@]}" -D - -o /tmp/mcp.init -X POST "$U" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
grep -oE '"serverInfo":\{[^}]*\}' /tmp/mcp.init
S=(); [ -n "$sid" ] && S=(-H "Mcp-Session-Id: $sid")
curl "${A[@]}" "${S[@]}" -X POST "$U" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
curl "${A[@]}" "${S[@]}" -X POST "$U" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | grep -oE '"name":"[a-z_0-9]+"' | cut -d'"' -f4 | sort -u | tr '\n' ' ' | head -c 700; echo
