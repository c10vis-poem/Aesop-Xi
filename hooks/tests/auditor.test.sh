#!/data/data/com.termux/files/usr/bin/bash
# Stop auditor: snippet shape; install/uninstall idempotence against a temp settings.json (no live files).
S=$(cd "$(dirname "$0")/../auditor" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
cnt(){ jq '[.hooks.Stop[]?.hooks[]? | select(.type=="agent")] | length' "$1"; }
ok "$(jq -e '.hooks[0] | .type=="agent" and .model=="claude-opus-5-5" and (.prompt|contains("$ARGUMENTS") and contains("stop_hook_active"))' "$S/settings-snippet.json" >/dev/null && echo y)" y "snippet has required keys"
ok "$(jq -e '.hooks[0].prompt | contains("never Read it without offset and limit") and (contains("Read the tail") | not)' "$S/settings-snippet.json" >/dev/null && echo y)" y "transcript is paged, never read whole"
export CLAUDE_SETTINGS=$T/settings.json
echo '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"}]}],"PreToolUse":[]}}' > "$CLAUDE_SETTINGS"
cp "$CLAUDE_SETTINGS" "$T/orig.json"
bash "$S/install-auditor.sh" >/dev/null; ok "$(cnt "$CLAUDE_SETTINGS")" 1 "install adds one agent hook"
ok "$(jq '.hooks.Stop|length' "$CLAUDE_SETTINGS")" 2 "existing Stop hook kept"
ok "$(ls "$T"/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' ')" 1 "backup written"
bash "$S/install-auditor.sh" >/dev/null; ok "$(cnt "$CLAUDE_SETTINGS")" 1 "second install is a no-op"
bash "$S/install-auditor.sh" --uninstall >/dev/null; ok "$(cnt "$CLAUDE_SETTINGS")" 0 "uninstall removes it"
ok "$(jq -S . "$CLAUDE_SETTINGS" | md5sum)" "$(jq -S . "$T/orig.json" | md5sum)" "uninstall restores original content"
bash "$S/install-auditor.sh" --uninstall >/dev/null; ok "$?" 0 "second uninstall is a no-op"
echo '{bad' > "$CLAUDE_SETTINGS"; bash "$S/install-auditor.sh" >/dev/null 2>&1; ok "$?" 1 "invalid settings: fails closed"
ok "$(cat "$CLAUDE_SETTINGS")" '{bad' "invalid settings untouched"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
