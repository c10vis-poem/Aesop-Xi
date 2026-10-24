#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse "*": after RESUME is read, no changes until the operator checks in with a mark in a prompt:
#   /ok | /ok 1,3 | /ok 1-4 | /ok all | /defer 2 | /reject 2 | /write 2 <new instruction> | /write <new item>
# (# forms also work). Allowed before check-in: reading and searching tools, Skill, task/plan tools,
# StructuredOutput (hook agents), AskUserQuestion, read-only Bash, the task-observer scan, `resume-item plan`,
# and Explore/Plan subagents. Applies only to sessions started with the snapshot-taking resume-gate.
# Bash is judged by the commands that run, not by text inside quotes or heredocs (obs 0042); an interpreter
# run (python/node/bash <file>) counts as a change (obs 0044).
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
[ -f "$ST/resume-$sid.snap.md" ] || exit 0          # older sessions: not enforced
[ -f "$ST/checkin-$sid" ] && exit 0                  # operator has checked in
tool=$(jq -r '.tool_name // ""' <<<"$in")
case $tool in
  Read|Glob|Grep|Skill|WebFetch|WebSearch|ToolSearch|TaskOutput|TaskList|TaskGet|TaskCreate|TaskUpdate|TaskStop|StructuredOutput|AskUserQuestion|ListMcpResourcesTool|ReadMcpResourceTool|ListAgents|SendMessage|Monitor|ReadNotifications|ListConnectors|ListPlugins|ListSkills) exit 0 ;;
  mcp__*) case $tool in *search*|*read*|*get*|*list*|*fetch*|*whoami*|*details*|*lookup*|*query*) exit 0 ;; *) why="an MCP write tool" ;; esac ;;
  Agent) case $(jq -r '.tool_input.subagent_type // ""' <<<"$in") in Explore|Plan|*explore*|*reader*|*read-only*) exit 0 ;; *) why="a subagent that may change files" ;; esac ;;
  Edit|Write|NotebookEdit) why="file edits" ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    # 1. drop heredoc bodies, quoted strings and trailing comments: text, not commands
    c=$(awk 'BEGIN{h=""} { if (h!="") { if ($0==h) h=""; next } if (match($0,/<<-?[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)["'"'"']?/)) { s=substr($0,RSTART,RLENGTH); gsub(/^<<-?[[:space:]]*["'"'"']?|["'"'"']?$/,"",s); h=s } print }' <<<"$cmd" \
        | sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g; s/(^|[[:space:]])#.*$//")
    # 2. the allowed startup writes
    c=$(sed -E 's#>>?[[:space:]]*"?[^ ;&|]*checkpoints\.log"?##g; s#[0-9]?>[[:space:]]*/dev/null##g; s#2>&1##g' <<<"$c")
    grep -qE '(^|[;&|[:space:]])resume-item[[:space:]]+plan([[:space:]]|$)' <<<"$c" && exit 0
    # 3. anything that changes state
    if grep -qE '(^|[^<>])>[^&]|(^|[;&|[:space:]])(rm|mv|cp|mkdir|rmdir|touch|chmod|chown|ln|tee|kill|pkill|termux-wake-lock|install|dd|truncate|patch|rsync|unzip|tar)([[:space:]]|$)|sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|(^|[;&|[:space:]])(python3?|node|perl|ruby|uv|npx)([[:space:]]+-[^[:space:]]*)*[[:space:]]+[^-[:space:]]|(^|[;&|[:space:]])(bash|sh|zsh)([[:space:]]+-[^[:space:]c]*)*[[:space:]]+[^-[:space:]]|git[[:space:]]+([^;&|]*[[:space:]])?(commit|push|add|rm|mv|reset|checkout|switch|merge|rebase|stash|worktree|tag|clean|cherry-pick|restore|pull|apply|am)([[:space:]]|$)|gh[[:space:]]+(pr[[:space:]]+(create|merge|close|edit|ready)|repo[[:space:]]+(sync|create|delete|rename|edit)|api[[:space:]]+(-X|--method)|release[[:space:]]+create)|(pip|pip3|pkg|apt|apt-get|npm|pnpm|yarn|cargo)[[:space:]]+(install|add|remove|uninstall|upgrade|update)|claude[[:space:]]+plugin[[:space:]]+(install|uninstall|update)|npu-serve([[:space:]]+[^s]|$)|curl[^|;&]*-X[[:space:]]*(POST|PUT|PATCH|DELETE)|resume-item[[:space:]]+[0-9]' <<<"$c"; then
      why="that command changes state"
    else exit 0; fi ;;
  *) why="$tool" ;;
esac
echo "$(date +%T) BLOCK checkin-gate: $tool" >> "$ST/enforce-$sid.log"
echo "BLOCKED (check-in): no changes before the operator checks in ($why). Post the START HERE plan (each item + what you'll do + tools/skills you'll load), run \`resume-item plan\`, and end the turn. The operator replies with /ok, /ok 1,3, /ok 1-4, /ok all, /defer 2, /reject 2, /write 2 <changed instruction>, or /write <new item> (# forms also work)." >&2
exit 2
