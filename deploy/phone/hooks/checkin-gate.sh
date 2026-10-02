#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse "*": after RESUME is read, no changes until the operator checks in (#ok / #defer in a prompt).
# Allowed before check-in: reading tools, Skill, read-only Bash, the task-observer scan, `resume-item plan`.
# Applies only to sessions that started with the snapshot-taking resume-gate (resume-<sid>.snap.md exists).
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0
st="$HOME/.claude/state"
[ -f "$st/resume-$sid.snap.md" ] || exit 0          # older sessions: not enforced
[ -f "$st/checkin-$sid" ] && exit 0                  # operator has checked in
tool=$(jq -r '.tool_name // ""' <<<"$in")
case $tool in
  Read|Glob|Grep|Skill|WebFetch|WebSearch|ToolSearch|TaskOutput|ListMcpResourcesTool|ReadMcpResourceTool) exit 0 ;;
  Edit|Write|NotebookEdit) why="file edits" ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    # strip the allowed startup writes, then look for anything that changes state
    c=$(sed -E 's#>>?[[:space:]]*"?[^ ;&|]*checkpoints\.log"?##g; s#[0-9]?>[[:space:]]*/dev/null##g; s#2>&1##g' <<<"$cmd")
    grep -qE '(^|[;&|[:space:]])resume-item[[:space:]]+plan([[:space:]]|$)' <<<"$c" && exit 0
    if grep -qE '(^|[^<>])>[^&]|(^|[;&|[:space:]])(rm|mv|cp|mkdir|rmdir|touch|chmod|chown|ln|tee|kill|pkill|termux-wake-lock|install|dd|truncate|patch)([[:space:]]|$)|sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|git[[:space:]]+([^;&|]*[[:space:]])?(commit|push|add|rm|mv|reset|checkout|switch|merge|rebase|stash|worktree|tag|clean|cherry-pick|restore|pull|apply|am)([[:space:]]|$)|gh[[:space:]]+(pr[[:space:]]+(create|merge|close|edit|ready)|repo[[:space:]]+(sync|create|delete|rename|edit)|api[[:space:]]+-X|release[[:space:]]+create)|(pip|pip3|pkg|apt|apt-get|npm|pnpm|yarn|cargo|uv)[[:space:]]+(install|add|remove|uninstall|upgrade|update)|claude[[:space:]]+plugin[[:space:]]+(install|uninstall|update)|npu-serve([[:space:]]+[^s]|$)|curl[^|;&]*-X[[:space:]]*(POST|PUT|PATCH|DELETE)|resume-item[[:space:]]+[0-9]' <<<"$c"; then
      why="that command changes state"
    else exit 0; fi ;;
  *) why="$tool" ;;
esac
echo "$(date +%T) BLOCK checkin-gate: $tool" >> "$st/enforce-$sid.log"
echo "BLOCKED (check-in): no changes before the operator checks in ($why). Post the START HERE plan (each item + what you'll do + tools/skills you'll load), run \`resume-item plan\`, and end the turn. The operator replies /ok, /ok 1,3, /defer 2, or a side task + /defer (# forms also work)." >&2
exit 2
