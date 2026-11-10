# Sourced by subagent-stop-gate.sh and subagent-task-gate.sh. Needs $in (the hook's JSON).
# Sets: sa_at (agent type), sa_aid (agent id), sa_tp (the subagent's own transcript), sa_pf (its progress file or "").
# Exempt: agent types that cannot write a file (no Write tool), so they cannot keep a progress file.
sa_at=$(jq -r '.agent_type // empty' <<<"$in" 2>/dev/null)
sa_aid=$(jq -r '.agent_id // empty' <<<"$in" 2>/dev/null)
sa_tp=$(jq -r '.agent_transcript_path // empty' <<<"$in" 2>/dev/null); sa_tp=${sa_tp/#\~/$HOME}
if [ ! -f "$sa_tp" ] && [ -n "$sa_aid" ]; then
  _mtp=$(jq -r '.transcript_path // empty' <<<"$in" 2>/dev/null); _mtp=${_mtp/#\~/$HOME}
  [ -n "$_mtp" ] && sa_tp="${_mtp%.jsonl}/subagents/agent-$sa_aid.jsonl"
fi
sa_exempt() { case "$sa_at" in web-fetch|Explore|Plan|claude-code-guide|statusline-setup|*adversarial-reviewer) return 0 ;; esac; return 1; }
sa_pf=
if [ -f "$sa_tp" ]; then
  sa_pf=$(grep -m1 -oE '(~|/[^" \\]*)?/?\.claude/session-work/[0-9-]+/([A-Za-z0-9._-]+/)*agent-[A-Za-z0-9._-]+\.md|session-work/[0-9-]+/([A-Za-z0-9._-]+/)*agent-[A-Za-z0-9._-]+\.md' "$sa_tp" | head -1)
  case $sa_pf in "~"*) sa_pf=${sa_pf/#\~/$HOME} ;; session-work/*) sa_pf="$HOME/.claude/$sa_pf" ;; .claude/*) sa_pf="$HOME/$sa_pf" ;; esac
fi
SA_HOW="Your progress file is ~/.claude/session-work/$(date +%F)/agent-<topic>.md with ## Plan (every step a checkbox), ## Last action (timestamp + what you are doing), ## Findings, ## Skills used, ## Blocked. Every file your brief assigns (Files:, Paths file:, Folder:) is read whole before you stop."
