#!/usr/bin/env bash
# End to end through the real wiring: every event goes through the command hooks/hooks.json holds, with
# the real hook scripts in a fake HOME. Only gh is stubbed (no network). Each hook is proven by what it
# did (a block, a file, a context line), not only by the trace line.
PKG=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got '$1' want '$2')"; fi; }
yes_() { if eval "$2"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'G'
#!/data/data/com.termux/files/usr/bin/bash
case "$*" in
  *"repo view"*isFork*) echo true ;;
  "repo sync"*) echo "could not sync: stub" >&2; exit 1 ;;
  "api repos/o/r --jq .full_name") echo o/r ;;
  "pr view"*) echo main ;;
  *) exit 1 ;;
esac
G
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH" GIT_ALLOW_PROTOCOL=file NVAEX_GATE_TRACE=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.invalid
unset VAULT AESOP_VAULT RECAPS_DIR STATE_DIR CLAUDE_CODE_REMOTE AESOP_HOOK_TIMEOUT CLAUDE_CODE_SESSION_ID
ROOT=$PKG; n=0
fresh() { n=$((n+1)); export HOME=$T/h$n; mkdir -p "$HOME/.claude/state"; st=$HOME/.claude/state; unset VAULT; unset TERMUX_VERSION; off=$st/off; echo direction > "$st/job-S"; }
# fire EVENT JSON: runs hooks.json's own command for EVENT; rc in $rc, stdout $T/out, stderr $T/err
fire() {
  local c; c=$(jq -r --arg e "$1" '.hooks[$e][0].hooks[0].command' "$PKG/hooks/hooks.json")
  CLAUDE_PLUGIN_ROOT=$ROOT bash -c "$c" <<<"$2" >"$T/out" 2>"$T/err"; rc=$?
}
tool() { jq -nc --arg t "$1" --argjson i "$2" --arg c "${3:-$HOME}" '{session_id:"S",hook_event_name:"PreToolUse",cwd:$c,tool_name:$t,tool_input:$i,transcript_path:""}'; }
post() { jq -nc --arg e "${4:-PostToolUse}" --arg t "$1" --argjson i "$2" --arg c "${3:-$HOME}" '{session_id:"S",hook_event_name:$e,cwd:$c,tool_name:$t,tool_input:$i}'; }
ups() { fire UserPromptSubmit "$(jq -nc --arg p "$1" --arg c "$HOME" '{session_id:"S",hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c}')"; local r=$rc; echo direction > "$st/job-S"; rc=$r; }
ev() { jq -nc --arg e "$1" --arg c "$HOME" '{session_id:"S",hook_event_name:$e,cwd:$c}'; }
fired() { grep -c "FIRED $1 $2\$" "$st/hooks.log" 2>/dev/null; }

# ---- one scenario per blocking hook: leaves E (event) and J (json) that must block --------------
arm() { case $name in enforce-gate|task-gate) printf 'x\tskill: foo\tturn\n' > "$st/required-S.tsv" ;; stop-gate) rm -f "$st/resume-S.ok" ;; esac; }
scen() {
  name=$1; fresh; E=PreToolUse
  case $name in
    direction-gate) rm -f "$st/job-S"; J=$(tool Bash '{"command":"ls"}') ;;
    secret-guard) J=$(tool Read '{"file_path":"/x/.env"}') ;;
    guard|settings-guard) J=$(tool Edit "$(jq -nc --arg f "$HOME/.claude/settings.json" '{file_path:$f}')") ;;
    state-guard) J=$(tool Write "$(jq -nc --arg f "$st/checkin-S" '{file_path:$f}')") ;;
    push-gate|git-gate) J=$(tool Bash '{"command":"git push origin x"}') ;;
    agent-type-gate) J=$(tool Agent '{"subagent_type":"Explore","prompt":"keep a progress file"}') ;;
    ci-ready) : > "$st/pushnow-S"; J=$(tool Bash '{"command":"gh pr merge 1 --auto --squash -R o/r"}') ;;
    build-doc-gate) mkdir -p "$HOME/repos/bd"; git init -q "$HOME/repos/bd"; J=$(tool Bash '{"command":"make"}' "$HOME/repos/bd") ;;
    branch-current-gate) r=$HOME/bc; git init -q -b main "$r"
      ( cd "$r"; git commit -q --allow-empty -m 1; git commit -q --allow-empty -m 2; git update-ref refs/remotes/origin/main HEAD; git reset -q --hard HEAD~1
        git remote add origin https://github.com/c10vis-poem/bc; git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main )
      J=$(tool Edit "$(jq -nc --arg f "$r/a.txt" '{file_path:$f}')" "$r") ;;
    repo-gate|sync-on-use) r=$HOME/repos/sy; mkdir -p "$r"; git init -q "$r"; git -C "$r" remote add origin https://github.com/c10vis-poem/sy
      J=$(tool Read "$(jq -nc --arg f "$r/a.txt" '{file_path:$f}')" "$r") ;;
    task-gate|enforce-gate) : > "$st/resume-S.ok"; arm; J=$(tool Bash '{"command":"ls"}') ;;
    stop-gate) E=Stop; export VAULT=$HOME/v; mkdir -p "$VAULT"; echo '# R 2026-11-05' > "$VAULT/RESUME.md"; J=$(ev Stop) ;;
    answer-gate|absence-gate) E=Stop; echo '{"type":"user","message":{"content":"where"}}' > "$HOME/t.jsonl"
      J=$(jq -nc --arg t "$HOME/t.jsonl" --arg c "$HOME" '{session_id:"S",hook_event_name:"Stop",cwd:$c,transcript_path:$t,last_assistant_message:"That file does not exist."}') ;;
    menu-gate) J=$(tool AskUserQuestion '{"questions":[{"question":"Which?","options":[{"label":"A"},{"label":"B"}]}]}') ;;
    question-gate) E=Stop; J=$(jq -nc --arg c "$HOME" '{session_id:"S",hook_event_name:"Stop",cwd:$c,last_assistant_message:"Done.\n\nWant me to ship it?"}') ;;
    subagent-stop-gate) E=SubagentStop; jq -nc '{type:"user",message:{content:"progress: session-work/2026-11-05/rebuild/agent-x.md"}}' > "$HOME/a.jsonl"
      J=$(jq -nc --arg t "$HOME/a.jsonl" '{session_id:"S",hook_event_name:"SubagentStop",agent_transcript_path:$t}') ;;
  esac
}
BLOCKERS="direction-gate secret-guard guard push-gate repo-gate task-gate stop-gate answer-gate"
CHECKS="state-guard ci-ready agent-type-gate build-doc-gate branch-current-gate menu-gate question-gate subagent-stop-gate"
verb() { awk -F'\t' -v n="$1" '$3==n{print $5; exit}' "$PKG/scripts/gates.tsv"; }

echo "--- wiring"
ok "$(jq '.hooks|length' "$PKG/hooks/hooks.json")" 9 "9 lifecycle events (PreCompact removed 2026-11-10: nothing runs there)"
ok "$(jq '[.hooks[][]|.hooks[]]|length' "$PKG/hooks/hooks.json")" 9 "one hook entry per event (CONTRACT rule 4)"
ok "$(jq -r '[.hooks[][]|.hooks[].command]|map(select(test("^bash \"\\$\\{CLAUDE_PLUGIN_ROOT\\}/scripts/run-gate.sh\" --event ")))|length' "$PKG/hooks/hooks.json")" 9 "every entry is the one launcher on CLAUDE_PLUGIN_ROOT"
ok "$(awk -F'\t' '!/^#/{print $1}' "$PKG/scripts/gates.tsv" | sort -u | wc -l | tr -d ' ')" 9 "table covers the same 9 events"
for h in $(awk -F'\t' '!/^#/{print $3}' "$PKG/scripts/gates.tsv" | sort -u); do
  yes_ "RULES.md lists $h with its revoke" 'grep -q "gate off $h" "$PKG/RULES.md"'
  v=$(verb "$h"); case $v in -|!) ;; *) yes_ "RULES.md names the verb of $h" 'grep -qF -- "$v" "$PKG/RULES.md"' ;; esac
done
ok "$(grep -lE '/data/data/|\.claude/hooks' "$PKG"/scripts/*.sh "$PKG"/bin/* | grep -vE 'change-log.sh' | wc -l | tr -d ' ')" 0 "no phone path or ~/.claude/hooks left in hook code"

echo "--- every blocking hook fires through run-gate and blocks; message names override and revoke"
for h in $BLOCKERS; do
  scen "$h"; fire "$E" "$J"
  ok "$rc" 2 "$h blocks through run-gate"
  yes_ "$h: its own message" 'grep -q "BLOCKED (" "$T/err"'
  yes_ "$h: names the revoke" 'grep -q "gate off $h" "$T/err" && grep -q "gate on $h" "$T/err"'
  yes_ "$h: names the override" 'grep -q "OVERRIDE" "$T/err"'
  v=$(verb "$h"); case $v in '!') yes_ "$h: says ! line" 'grep -q "! line" "$T/err"' ;; *) yes_ "$h: names $v" 'grep -qF -- "$v" "$T/err"' ;; esac
  ok "$(fired "$E" "$h")" 1 "$h: fired once"
done

echo "--- every check inside a merged hook still blocks through the wiring"
for h in $CHECKS; do scen "$h"; fire "$E" "$J"; ok "$rc" 2 "$h blocks through run-gate"; done

echo "--- non-blocking hooks: real effects"
fresh; echo a > "$HOME/.claude/CLAUDE.md"; fire SessionStart "$(ev SessionStart)"; echo b >> "$HOME/.claude/CLAUDE.md"; fire SessionStart "$(ev SessionStart)"
yes_ "context-diff shows the change" 'jq -e ".hookSpecificOutput.additionalContext|test(\"Changed since last session\")" "$T/out" >/dev/null'
ok "$(fired SessionStart session-start)" 2 "session-start fired"
fresh; export VAULT=$HOME/v; mkdir -p "$VAULT/skill-updates"; printf '## Routines\n- r1\n' > "$VAULT/PENDING.md"; printf '## skill-a -> x\n' > "$VAULT/skill-updates/PENDING.md"
TERMUX_VERSION=t fire SessionStart "$(jq -nc --arg c "$HOME" '{session_id:"S",hook_event_name:"SessionStart",source:"compact",cwd:$c}')"
c=$(jq -r .hookSpecificOutput.additionalContext "$T/out")
yes_ "housekeeping-check: due line" 'grep -q "HOUSEKEEPING DUE" <<<"$c"'
yes_ "staged-updates: pending line" 'grep -q "STAGED SKILL UPDATES PENDING (1)" <<<"$c"'
yes_ "observe-event SessionStart: compaction noted" 'grep -q "Context was compacted" <<<"$c" && [ -f "$st/compact-S" ]'
yes_ "several hooks merge into ONE valid JSON object" '[ "$(jq -s length "$T/out")" = 1 ]'
fresh; ups "turn on the hooks enforcement, what happened"
yes_ "enforce-prompt: requirement written and pointer line" '[ -s "$st/required-S.tsv" ] && grep -q ENFORCEMENTS "$T/out"'
yes_ "observe-event UserPromptSubmit: correction queued" 'grep -q correction "$st/observe-queue-S.tsv"'
fresh; mkdir -p "$HOME/repos/r"; git init -q "$HOME/repos/r"; j=$(tool Write "$(jq -nc --arg f "$HOME/repos/r/new.txt" '{file_path:$f}')" "$HOME/repos/r")
fire PreToolUse "$j"; ok "$rc" 0 "plain Write passes all gates"
yes_ "session-log: NEW line" 'grep -q "NEW" "$st/changes-S.log"'
fire PostToolUse "$(jq -c '.hook_event_name="PostToolUse"' <<<"$j")"
yes_ "session-log: recap has the repo and the file, outside the vault" 'grep -q "$HOME/repos/r" "$st"/recaps/*-S.md && grep -q new.txt "$st"/recaps/*-S.md'
fresh; mkdir -p "$HOME/repos/d"; git init -q "$HOME/repos/d"; echo x > "$HOME/repos/d/README.md"
fire PostToolUse "$(post Read "$(jq -nc --arg f "$HOME/repos/d/README.md" '{file_path:$f}')" "$HOME/repos/d")"
yes_ "build-doc-gate PostToolUse: doc read recorded" 'grep -q "repos/d" "$st/docread-S.txt"'
fire PreToolUse "$(tool Bash '{"command":"make"}' "$HOME/repos/d")"; ok "$rc" 0 "build-doc-gate: make allowed after the doc"
fresh; printf '## START HERE\n1. carried item\n' > "$st/resume-S.snap.md"; mkdir -p "$st/carryover"; printf 'Z\n' >/dev/null
printf '%s\topen\t2026-11-01\tcarried item\n' carrieditem > "$st/carryover/old.tsv"
fire PostToolUse "$(post Read '{"file_path":"/x/RESUME.md"}')"
yes_ "carryover PostToolUse: carried item reported" 'grep -q "already carried over 1" "$T/out"'
fresh; printf '## START HERE\n1. item one\n' > "$st/resume-S.snap.md"; fire SessionEnd "$(ev SessionEnd)"
yes_ "carryover SessionEnd: session's open items recorded" 'grep -q itemone "$st/carryover/S.tsv"'
fresh; fire PostToolUseFailure "$(jq -nc '{session_id:"S",hook_event_name:"PostToolUseFailure",tool_name:"Edit",error:"boom"}')"
yes_ "observe-event PostToolUseFailure: queued" 'grep -q "tool-fail" "$st/observe-queue-S.tsv"'
fire PermissionDenied "$(jq -nc '{session_id:"S",hook_event_name:"PermissionDenied",tool_name:"Edit",reason:"no"}')"
yes_ "observe-event PermissionDenied: queued" 'grep -q "denied" "$st/observe-queue-S.tsv"'
fresh; RECAPS_REPO=$T/no-recaps fire SessionEnd "$(ev SessionEnd)"
yes_ "save-session-log SessionEnd: no Recaps checkout is logged, not fatal" 'grep -q "save-session-log: .* not a git repo" "$st/hooks.log"'
yes_ "no device copy of the scratchpad (one place only)" '[ ! -d "$HOME/.claude/scratchpad-archive" ]'
fresh; mkdir -p "$st/recaps"; printf '# Session\n\n## Repos touched\n\n## Files written\n\n## Git actions\n' > "$st/recaps/2026-11-05-S.md"
fire SessionEnd "$(ev SessionEnd)"; ok "$rc" 0 "ship-session: SessionEnd returns"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q 'held: no wrap-up' "$HOME/.claude/logs/ship-session.log" 2>/dev/null && break; sleep 0.5; done
yes_ "ship-session: worker ran and held without the wrap-up order" 'grep -q "held: no wrap-up order" "$HOME/.claude/logs/ship-session.log"'
fresh; mkdir -p "$st/recaps"; printf '# Session\n\n## Repos touched\n\n## Files written\n\n## Git actions\n' > "$st/recaps/2026-11-05-S.md"; : > "$st/pushok-S"
ups "all done #no-ship"; fire SessionEnd "$(ev SessionEnd)"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q 'held: operator' "$HOME/.claude/logs/ship-session.log" 2>/dev/null && break; sleep 0.5; done
yes_ "ship-session: #no-ship override holds the ship" 'grep -q "held: operator typed #no-ship" "$HOME/.claude/logs/ship-session.log"'
scen stop-gate; echo '{"type":"user","message":{"content":"where"}}' > "$HOME/t.jsonl"
fire Stop "$(jq -nc --arg t "$HOME/t.jsonl" --arg c "$HOME" '{session_id:"S",hook_event_name:"Stop",cwd:$c,transcript_path:$t,last_assistant_message:"That file does not exist."}')"
yes_ "Stop: both hooks speak in one block" '[ $rc -eq 2 ] && grep -q "Opening O1" "$T/err" && grep -q "BLOCKED (absence-gate)" "$T/err"'

echo "--- overrides"
for h in $BLOCKERS; do
  v=$(verb "$h"); case $v in '!') continue ;; '#show-secret') continue ;; esac
  scen "$h"; ups "carry on $v"; arm; fire "$E" "$J"
  ok "$rc" 0 "$v lifts $h"
  yes_ "$h: lift logged" 'grep -q "$h block LIFTED by operator $v\|SKIP operator used\|STOP-SKIP" "$st/hooks.log" "$st/enforce-S.log" 2>/dev/null'
  ups "next thing"; arm; fire "$E" "$J"; ok "$rc" 2 "$h: override lasts one prompt"
done
scen secret-guard; ups "#show-secret /x/.env"; fire "$E" "$J"; ok "$rc" 0 "#show-secret <path> lets that path through"
fire "$E" "$J"; ok "$rc" 2 "#show-secret works for one call"
fire "$E" "$(tool Read '{"file_path":"/y/.env"}')"; ok "$rc" 2 "#show-secret does not cover another path"
for p in "go ahead" "override" "I told you" "you can read it" "this is what I want"; do
  scen git-gate; ups "$p"; fire "$E" "$J"; ok "$rc" 0 "phrase lifts a gate for the turn: $p"
done
scen git-gate; ups "fine"; jq -nc '{session_id:"S",hook_event_name:"UserPromptSubmit",prompt:"<task-notification>override</task-notification>"}' >"$T/hb"; fire UserPromptSubmit "$(cat "$T/hb")"
fire "$E" "$J"; ok "$rc" 2 "override inside a subagent hand-back does not count"
for h in secret-guard guard state-guard; do scen "$h"; ups "go ahead, override"; fire "$E" "$J"; ok "$rc" 2 "phrases do not lift hard guard $h"; done
fresh; ups "/ok"; ok "$rc" 0 "check-in prompt accepted"
scen stop-gate; printf '' ; yes_ "rule 7 verb /wrapup-defer is parsed" '
  printf "## START HERE\n1. a\n" > "$st/resume-S.snap.md"; ups "/wrapup-defer 1 why: blocked upstream"; grep -q "deferred" "$st/confirm-S.tsv" && grep -q "blocked upstream" "$st/defer-why-S.tsv"'

echo "--- kill switches"
G="bash $PKG/bin/gate"
for h in $BLOCKERS; do
  scen "$h"; $G off "$h" >/dev/null; fire "$E" "$J"; ok "$rc" 0 "gate off $h"
  $G on "$h" >/dev/null; arm; fire "$E" "$J"; ok "$rc" 2 "gate on $h"
done
scen git-gate; mkdir -p "$off"; : > "$off/aesops-enforcements.push-gate"; fire "$E" "$J"; ok "$rc" 0 "off/aesops-enforcements.<hook> (CONTRACT form)"; $G on push-gate >/dev/null
: > "$off/aesops-enforcements"; fire "$E" "$J"; ok "$rc" 0 "off/aesops-enforcements turns the package off"
yes_ "status reports the package switch" '$G status | grep -q "KILL SWITCH"'; $G on all >/dev/null
fire "$E" "$J"; ok "$rc" 2 "gate on all restores"
$G off all >/dev/null; fire "$E" "$J"; ok "$rc" 0 "gate off all"; $G on all >/dev/null
: > "$HOME/.nvaex-hooks-off"; fire "$E" "$J"; ok "$rc" 0 "~/.nvaex-hooks-off honoured first"
yes_ "status reports ~/.nvaex-hooks-off" '$G status | grep -q "nvaex-hooks-off"'; $G on all >/dev/null; yes_ "gate on all clears it" '[ ! -e "$HOME/.nvaex-hooks-off" ]'
ups "#hooks-off"; fire "$E" "$J"; ok "$rc" 0 "#hooks-off"; fire SessionStart "$(ev SessionStart)"; yes_ "off survives and says so at session start" 'grep -q "hooks-on" "$T/out"'
ups "#hooks-on"; fire "$E" "$J"; ok "$rc" 2 "#hooks-on"
: > "$off/other-pkg"; $G on all >/dev/null; yes_ "gate on all leaves other packages' switches alone" '[ -e "$off/other-pkg" ]'
ok "$($G off nosuchhook 2>&1 >/dev/null | grep -c 'no hook named')" 1 "gate refuses an unknown hook name"
ok "$($G status | grep -c '^on ')" "$(awk -F'\t' '!/^#/{print $3}' "$PKG/scripts/gates.tsv" | sort -u | wc -l | tr -d ' ')" "status lists every hook, all on, nothing starts off"
for c in 'gate off direction-gate' "bash $PKG/bin/gate off all" 'touch ~/.nvaex-hooks-off' 'rm ~/.claude/state/off/direction-gate' 'rm ~/.claude/state/hooks-off'; do
  fresh; fire PreToolUse "$(tool Bash "$(jq -nc --arg c "$c" '{command:$c}')")"; ok "$rc" 2 "the agent cannot run: ${c/$PKG/PKG}"
done
fresh; fire PreToolUse "$(tool Bash '{"command":"echo \"gate off x\""}')"; ok "$rc" 0 "quoted text about gate off is not a command"

echo "--- no deadlock"
for h in $BLOCKERS; do
  case " secret-guard guard direction-gate " in *" $h "*) continue ;; esac
  scen "$h"; ups "work"; arm; fire "$E" "$J"; a=$rc; arm; fire "$E" "$J"; b=$rc; arm; fire "$E" "$J"; c=$rc
  ok "$a$b$c" 220 "$h: same call blocks twice, third yields"
  yes_ "$h: LOOP-BREAKER logged" 'grep -q "$h LOOP-BREAKER" "$st/hooks.log"'
  ups "next"; arm; fire "$E" "$J"; ok "$rc" 2 "$h: new turn, gate is back"
done
scen direction-gate; b=0; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do fire PreToolUse "$(tool Bash "$(jq -nc --arg c "ls $i" '{command:$c}')")"; [ "$rc" = 2 ] && b=$((b+1)); done
ok "$b" 12 "Rule 1 holds: 12 different calls, 12 blocks, no loop breaker"
fresh; export VAULT=$HOME/v; mkdir -p "$VAULT"; echo R > "$VAULT/RESUME.md"; rm -f "$st/job-S"
fire PreToolUse "$(tool Read "$(jq -nc --arg f "$VAULT/RESUME.md" '{file_path:$f}')")"; ok "$rc" 0 "opening read allowed while closed"
scen guard; for i in 1 2 3 4; do fire "$E" "$J"; done; ok "$rc" 2 "hard guard holds on the 4th identical try (retrying must not reach the operator's settings)"
fire PreToolUse "$(tool Bash '{"command":"ls"}')"; ok "$rc" 0 "hard guard deadlocks nothing: the next call runs"
scen stop-gate; for i in 1 2 3; do fire Stop "$J"; done; ok "$rc" 0 "stop-gate: a session can always end (third Stop yields)"

echo "--- missing, crash, relocation"
cp -r "$PKG" "$T/copy"; ROOT=$T/copy; rm "$T/copy/scripts/push-gate.sh"; printf 'exit 7\n' > "$T/copy/scripts/secret-guard.sh"
scen git-gate; fire "$E" "$J"; ok "$rc" 0 "missing script: call allowed"
yes_ "missing script: logged" 'grep -q "MISSING push-gate" "$st/hooks.log"'
yes_ "missing script: told to the agent" 'grep -q "HOOK MISSING" "$T/out"'
s=$(bash "$T/copy/bin/gate" status); ok "$?" 1 "gate status exits 1 on a missing hook"
yes_ "gate status names it" 'grep -q "^MISSING push-gate" <<<"$s"'
fresh; fire SessionStart "$(ev SessionStart)"; yes_ "session start reports it before its event comes round" 'grep -q "HOOK MISSING.*push-gate" "$T/out"'
fresh; fire PreToolUse "$(tool Read '{"file_path":"/x/.env"}')"; ok "$rc" 0 "crash: call allowed"
yes_ "crash: logged" 'grep -q "secret-guard ERROR exit 7" "$st/hooks.log"'
yes_ "crash: in gate status" 'bash "$T/copy/bin/gate" status | grep -q "^ERROR: 1"'
cp "$PKG/scripts/push-gate.sh" "$PKG/scripts/secret-guard.sh" "$T/copy/scripts/"
scen git-gate; fire "$E" "$J"; ok "$rc" 2 "plugin works from any folder (copied to $T/copy)"
ROOT=$PKG

echo "--- cloud"
cloud() { local c; c=$(jq -r --arg e "$1" '.hooks[$e][0].hooks[0].command' "$PKG/hooks/hooks.json"); env -u PREFIX CLAUDE_CODE_REMOTE=true CLAUDE_PLUGIN_ROOT=$PKG bash -c "$c" <<<"$2" >"$T/out" 2>"$T/err"; rc=$?; }
fresh; bad=0
cloud SessionStart "$(ev SessionStart)"; [ $rc = 0 ] || bad=1
cloud UserPromptSubmit "$(jq -nc --arg c "$HOME" '{session_id:"S",hook_event_name:"UserPromptSubmit",prompt:"#fix the npu and rename NvAEx",cwd:$c}')"; [ $rc = 0 ] || bad=2
: > "$st/resume-S.ok"
cloud PreToolUse "$(tool Bash '{"command":"ls"}')"; [ $rc = 0 ] || { bad=3; cat "$T/err"; }
cloud PreToolUse "$(tool Bash '{"command":"ls"}')"; [ $rc = 0 ] || { bad=4; cat "$T/err"; }
cloud PreToolUse "$(tool Bash '{"command":"ls"}')"; [ $rc = 0 ] || { bad=5; cat "$T/err"; }
r=$HOME/repos/sy; mkdir -p "$r"; git init -q "$r"; git -C "$r" remote add origin https://github.com/c10vis-poem/sy
cloud PreToolUse "$(tool Read "$(jq -nc --arg f "$r/a" '{file_path:$f}')" "$r")"; [ $rc = 0 ] || { bad=6; cat "$T/err"; }
cloud PostToolUse "$(post Write '{"file_path":"/x/a"}')"; [ $rc = 0 ] || bad=7
cloud Stop "$(ev Stop)"; [ $rc = 0 ] || { bad=8; cat "$T/err"; }
cloud SessionEnd "$(ev SessionEnd)"; [ $rc = 0 ] || bad=10
ok "$bad" 0 "cloud with no vault, no phone paths, no working gh: nothing blocks"
for k in 'housekeeping-check' 'staged-updates' 'context-diff' 'enforce-prompt: row' 'sync-on-use: sy'; do
  yes_ "cloud degrade logged: $k" 'grep -q "DEGRADE $k" "$st/hooks.log"'
done
fresh; export VAULT=$HOME/v; mkdir -p "$VAULT"; echo R > "$VAULT/RESUME.md"; rm -f "$st/job-S"; cloud PreToolUse "$(tool Bash '{"command":"ls"}')"; ok "$rc" 2 "cloud: direction-gate still blocks"
fresh; cloud PreToolUse "$(tool Bash '{"command":"git push origin x"}')"; ok "$rc" 2 "cloud: git-gate still blocks"

echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
