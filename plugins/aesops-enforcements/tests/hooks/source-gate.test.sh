#!/usr/bin/env bash
# Rule 12 (operator, 2026-11-10): the operator orders a read ("read X", full or brief); the turn cannot end until
# that read is done. Nothing is required that the operator did not order.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); B=$(cd "$S/../bin" && pwd); T=$(mktemp -d)
export HOME=$T STATE_DIR=$T/st REPOS_DIR=$T/repos VAULT=$T/vault
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$T/bin"; printf '#!/bin/sh\necho PUBLIC\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
R=$REPOS_DIR/jevtool; mkdir -p "$R/docs" "$VAULT/Vendor-Registries/acme" "$T/notes"
echo "# Jev" > "$R/README.md"; echo "# Install" > "$R/INSTALL.md"; echo "# Guide" > "$R/docs/guide.md"; echo x > "$R/main.py"
git -C "$R" init -q && git -C "$R" add . && git -C "$R" commit -q -m init
printf 'a\nb\nc\n' > "$T/notes/one.md"; printf 'a\nb\nc\n' > "$T/notes/two.md"; seq 1 2500 > "$T/big.txt"
U(){ jq -cn --arg c "$1" '{type:"user",message:{role:"user",content:$c}}'; }
A(){ jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}'; }
P(){ jq -cn --arg s "$1" --arg p "$2" '{session_id:$s,hook_event_name:"UserPromptSubmit",prompt:$p}' | bash "$S/source-gate.sh" >/dev/null 2>&1; }
ST(){ jq -cn --arg s "$1" --arg t "$T/tr-$1.jsonl" '{session_id:$s,hook_event_name:"Stop",transcript_path:$t,last_assistant_message:"done"}' | bash "$S/source-gate.sh" 2>"$T/err"; echo $?; }
E(){ jq -cn --arg s "$1" --arg e "$2" --arg t "$3" --argjson i "$4" '{session_id:$s,hook_event_name:$e,tool_name:$t,tool_input:$i,cwd:"/"}' | bash "$S/source-gate.sh" >/dev/null 2>&1; echo $?; }

# no order, nothing required
P S0 "what flags does jevtool have?"; : > "$T/tr-S0.jsonl"
ok "$(ST S0)" 0 "asset named but no read ordered -> nothing required"
ok "$(E S0 PreToolUse Bash '{"command":"pip install x"}')" 0 "installs are not checked unless ordered"

# full read of a file
P S1 "I need you to read $T/big.txt in full, it has the spec"
{ U x; A Read "{\"file_path\":\"$T/big.txt\"}"; } > "$T/tr-S1.jsonl"
ok "$(ST S1)" 2 "full read ordered, only 2000 of 2500 lines read -> block"
ok "$(command grep -c 'big.txt' "$T/err")" 1 "reason names the file"
A Read "{\"file_path\":\"$T/big.txt\",\"offset\":2001}" >> "$T/tr-S1.jsonl"
ok "$(ST S1)" 0 "every line read -> pass"
: > "$T/tr-S1.jsonl"; ok "$(ST S1)" 0 "a done order is cleared"

# full read of a folder: every file whole
P S2 "read $T/notes so you know the history"
{ U x; A Read "{\"file_path\":\"$T/notes/one.md\"}"; } > "$T/tr-S2.jsonl"
ok "$(ST S2)" 2 "folder ordered, one of two files read -> block"
ok "$(command grep -c 'two.md' "$T/err")" 1 "reason names the unread file"
A Bash "{\"command\":\"cat $T/notes/two.md\"}" >> "$T/tr-S2.jsonl"
ok "$(ST S2)" 0 "both read whole -> pass"

# brief read of a file
P S3 "quick rundown: read $T/big.txt"
U x > "$T/tr-S3.jsonl"; ok "$(ST S3)" 2 "brief ordered, nothing opened -> block"
A Read "{\"file_path\":\"$T/big.txt\",\"limit\":50}" >> "$T/tr-S3.jsonl"
ok "$(ST S3)" 0 "brief: part of it read -> pass"

# an asset: full = clean MD (or tree + every doc); brief = chunk.jsonl or manifest + a pointed file
P S4 "read jevtool, full read, before we install it"; : > "$T/tr-S4.jsonl"
ok "$(ST S4)" 2 "full read of an asset ordered, nothing read -> block"
E S4 PostToolUse Bash "$(jq -cn --arg c "find $R -not -path '*/.git/*'" '{command:$c}')" >/dev/null
for f in README.md INSTALL.md docs/guide.md; do E S4 PostToolUse Read "$(jq -cn --arg f "$R/$f" '{file_path:$f}')" >/dev/null; done
ok "$(ST S4)" 0 "tree + every doc read -> pass"
bash "$B/asset-manifest" "$R" >/dev/null; I=$VAULT/Assets-Index/jevtool
mkdir -p "$I/clean_md"; echo '{"id":1}' > "$I/chunk.jsonl"; echo "# A" > "$I/clean_md/a.md"; echo "# B" > "$I/clean_md/b.md"
P S5 "brief analysis: read jevtool and tell me if it has a fast flag"; : > "$T/tr-S5.jsonl"
ok "$(ST S5)" 2 "brief read of an asset ordered, nothing looked up -> block"
E S5 PostToolUse Bash "$(jq -cn --arg c "grep fast $I/chunk.jsonl" '{command:$c}')" >/dev/null
ok "$(ST S5)" 0 "brief: chunk.jsonl lookup -> pass"
P S6 "read jevtool, the whole thing"; : > "$T/tr-S6.jsonl"
E S6 PostToolUse Read "$(jq -cn --arg f "$I/clean_md/a.md" '{file_path:$f}')" >/dev/null
ok "$(ST S6)" 2 "full read with clean MD: one of two -> block"
E S6 PostToolUse Read "$(jq -cn --arg f "$I/clean_md/b.md" '{file_path:$f}')" >/dev/null
ok "$(ST S6)" 0 "every clean MD read -> pass"

# the order stands across prompts until done; automated runs highlight; records are the gate's
P S7 "read $T/notes/one.md"; P S7 "now something else"; : > "$T/tr-S7.jsonl"
ok "$(ST S7)" 2 "an undone order carries to later prompts"
ok "$(AESOP_AUTOMATED=1 bash -c "jq -cn --arg t '$T/tr-S7.jsonl' '{session_id:\"S7\",hook_event_name:\"Stop\",transcript_path:\$t}' | bash '$S/source-gate.sh'" 2>/dev/null; echo $?)" 0 "automated run: highlight, not a block"
ok "$(command grep -c 'HIGHLIGHT (source-gate' "$STATE_DIR/hooks.log")" 1 "automated highlight logged"
X(){ jq -cn --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}' | bash "$S/state-guard.sh" 2>/dev/null; echo $?; }
ok "$(X "$T/.claude/state/source-asked-S7")" 2 "agent cannot clear its own read order"
ok "$(X "$T/.claude/state/source-S7.tsv")" 2 "agent cannot write the read records"

# manifests
ok "$(sed -n 1p "$I/manifest.jsonl" | jq -r .head)" "$(git -C "$R" rev-parse HEAD)" "manifest records HEAD"
ok "$([ -f "$I/POINTER.md" ] && echo yes)" yes "pointer written next to the manifest"
echo "# A" > "$VAULT/Vendor-Registries/acme/guide.md"; bash "$B/asset-manifest" "$VAULT/Vendor-Registries/acme" >/dev/null
ok "$([ -f "$VAULT/Vendor-Registries/acme/manifest.jsonl" ] && echo yes)" yes "vendor manifest sits next to the raw files"
printf '#!/bin/sh\necho PRIVATE\n' > "$T/bin/gh"; git -C "$R" remote add origin https://github.com/c/priv.git
ok "$(bash "$B/asset-manifest" "$R" >/dev/null 2>&1; echo $?)" 1 "private repo refused (the vault is public)"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
