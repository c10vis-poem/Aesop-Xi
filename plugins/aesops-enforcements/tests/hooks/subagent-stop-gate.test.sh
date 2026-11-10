#!/usr/bin/env bash
# Rule 10 sub-agent stop gate (operator, 2026-11-10): write to task, read every assigned file whole,
# use every equipped skill and tool, or say why under ## Blocked. Every stop is audited.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); export HOME=$T
D="$T/.claude/session-work/2026-11-10"; mkdir -p "$D" "$T/.claude/state" "$T/.claude/agents" "$T/docs"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
PF="$D/agent-x.md"
cat > "$T/.claude/agents/worker.md" <<'EOF'
---
name: worker
tools: Read, Bash, Grep
skills:
  - foo-skill
---
A test worker.
EOF
cat > "$T/.claude/agents/plain.md" <<'EOF'
---
name: plain
---
No tools or skills listed: nothing to check there.
EOF
printf 'a\nb\nc\n' > "$T/docs/one.md"; printf 'a\nb\nc\n' > "$T/docs/two.md"; printf 'a\nb\nc\n' > "$T/docs/three.md"
seq 1 2500 > "$T/big.txt"
U(){ jq -cn --arg c "$1" '{type:"user",message:{role:"user",content:$c}}'; }
A(){ jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}'; }
G(){ jq -n --arg t "${1:-$T/tr.jsonl}" --arg at "${2:-plain}" --arg id "${3:-ag1}" '{session_id:"MAIN",agent_id:$id,agent_type:$at,agent_transcript_path:$t}' \
  | bash "$S/subagent-stop-gate.sh" 2>"$T/err"; echo $?; }
SPAWN="Keep a progress file: ~/.claude/session-work/2026-11-10/agent-x.md"
pf(){ printf '%s\n' "$@" > "$PF"; }

ok "$(G /nonexistent)" 0 "no transcript -> allow"
U "$SPAWN" > "$T/tr.jsonl"; ok "$(G "" Explore)" 0 "agent type with no Write tool -> exempt"
U "do a thing" > "$T/tr.jsonl"; ok "$(G "" plain ag-np)" 2 "no progress file -> block (write to task is required)"
U "$SPAWN" > "$T/tr.jsonl"; ok "$(G "" plain ag-mf)" 2 "progress file named but missing -> block"
pf '## Plan' '- [x] a' '- [ ] b' '## Last action' 'x' '## Findings' 'f' '## Blocked'
ok "$(G "" plain ag-skip)" 2 "skipped step -> block"; ok "$(grep -c 'b;' "$T/err")" 1 "reason names the step"
pf '## Plan' '- [x] a' '- [ ] b' '## Findings' 'f' '## Blocked' '- b: waiting on operator'
ok "$(G "" plain ag-bl)" 0 "unchecked but explained under Blocked -> allow"
pf '## Plan' '- [x] a' '## Findings' '## Blocked'
ok "$(G "" plain ag-nf)" 2 "done steps, empty Findings -> block"

# reads: Folder:, partial reads, whole reads
pf '## Plan' '- [x] read' '## Findings' 'read them' '## Blocked'
{ U "$SPAWN
Folder: $T/docs"; A Read "{\"file_path\":\"$T/docs/one.md\"}"; A Read "{\"file_path\":\"$T/docs/two.md\",\"limit\":1}"; } > "$T/tr.jsonl"
ok "$(G "" plain ag-r)" 2 "assigned folder, one unread, one partial -> block"
ok "$(grep -c 'three.md' "$T/err")" 1 "reason names the unread file"
ok "$(grep -c 'in part: two.md' "$T/err")" 1 "reason names the partial file"
{ U "$SPAWN
Folder: $T/docs"; A Read "{\"file_path\":\"$T/docs/one.md\"}"; A Read "{\"file_path\":\"$T/docs/two.md\",\"limit\":1}"
  A Read "{\"file_path\":\"$T/docs/two.md\",\"offset\":2,\"limit\":5}"; A Bash "{\"command\":\"cat $T/docs/three.md\"}"; } > "$T/tr.jsonl"
ok "$(G "" plain ag-r2)" 0 "every file read whole (ranges + cat) -> allow"
{ U "$SPAWN
Files:
- $T/big.txt"; A Read "{\"file_path\":\"$T/big.txt\"}"; } > "$T/tr.jsonl"
ok "$(G "" plain ag-big)" 2 "2500-line file, one plain Read (2000 lines) -> partial, block"
{ U "$SPAWN
Files:
- $T/big.txt"; A Read "{\"file_path\":\"$T/big.txt\"}"; A Read "{\"file_path\":\"$T/big.txt\",\"offset\":2001}"; } > "$T/tr.jsonl"
ok "$(G "" plain ag-big2)" 0 "second Read covers the rest -> allow"
printf '%s\n' "$T/docs/one.md" "$T/docs/two.md" > "$T/B1-paths.txt"
{ U "$SPAWN
Paths file: $T/B1-paths.txt"; A Read "{\"file_path\":\"$T/docs/one.md\"}"; } > "$T/tr.jsonl"
ok "$(G "" plain ag-pf)" 2 "paths file: one of two unread -> block"
pf '## Plan' '- [x] read' '## Findings' 'read them' '## Blocked' '- two.md: permission denied (error text here)'
ok "$(G "" plain ag-pf2)" 0 "unread file explained under Blocked -> allow"

# skills and tools from the agent definition
pf '## Plan' '- [x] read' '## Findings' 'done' '## Blocked'
{ U "$SPAWN"; A Read '{"file_path":"/x"}'; A Bash '{"command":"ls"}'; } > "$T/tr.jsonl"
ok "$(G "" worker ag-t)" 2 "equipped Grep and foo-skill never used -> block"
ok "$(grep -c 'Skills: foo-skill' "$T/err")" 1 "reason names the skill"
ok "$(grep -c 'Tools: Grep' "$T/err")" 1 "reason names the tool"
pf '## Plan' '- [x] read' '## Findings' 'done' '## Skills used' '- foo-skill: applied its checklist to every file' '## Blocked' '- Grep: nothing to search, every file was read whole'
ok "$(G "" worker ag-t2)" 0 "skill used (preloaded, said how) + unused tool explained -> allow"
{ U "$SPAWN"; A Read '{"file_path":"/x"}'; A Bash '{"command":"ls"}'; A Grep '{"pattern":"x"}'; A Skill '{"skill":"plug:foo-skill"}'; } > "$T/tr.jsonl"
pf '## Plan' '- [x] read' '## Findings' 'done' '## Blocked'
ok "$(G "" worker ag-t3)" 0 "every tool and skill called -> allow"

# audit and the no-loop limit
A_=$T/.claude/state/subagent-audit-MAIN.tsv
ok "$(grep -c $'\tpass\t' "$A_")" 6 "an audit line for every passing stop"
ok "$(grep 'ag-r2' "$A_" | grep -c 'assigned 3, read whole 3, partial 0, unread 0')" 1 "audit counts assigned vs read"
U "do a thing" > "$T/tr.jsonl"
for i in 1 2 3 4; do G "" plain ag-loop >/dev/null; done
ok "$(G "" plain ag-loop)" 0 "after 4 blocks it is let go (no endless loop)"
ok "$(grep 'ag-loop' "$A_" | grep -c 'let go with gaps')" 1 "audit records it was let go with gaps"
ok "$(grep -c 'subagent-gap' "$T/.claude/state/observe-queue-MAIN.tsv")" 1 "and queues a friction event for the main session"

# scope check (obs 0040)
pf '## Plan' '- [x] a' '## Findings' 'f' '## Blocked'
W(){ U "$1" > "$T/tr.jsonl"; shift; for f in "$@"; do A Edit "$(jq -cn --arg f "$f" '{file_path:$f}')" >> "$T/tr.jsonl"; done; }
W "$SPAWN. SCOPE CLAUSE: Change only /work/app/src and /work/docs. Report otherwise." /work/app/src/a.kt /work/docs/x.md "$PF"
ok "$(G "" plain ag-s1)" 0 "writes inside the declared scope -> allow"
W "$SPAWN. SCOPE CLAUSE: Change only /work/app/src. Report otherwise." /work/app/src/a.kt /work/hooks/run-hook.sh
ok "$(G "" plain ag-s2)" 2 "write outside scope -> block"; ok "$(grep -c '/work/hooks/run-hook.sh' "$T/err")" 1 "reason names the file"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
