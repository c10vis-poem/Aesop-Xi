#!/usr/bin/env bash
# Stop, the operator's Rule 5: a turn cannot end on a closed question: yes/no, either/or, or a menu with no write-in.
# Reads the last non-empty line of the final answer. Blocks once
# (stop_hook_active allows), so it can never hold a turn open. Fails open on bad input.
in=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$in" 2>/dev/null) || exit 0
[ "$active" = true ] && exit 0
last=$(jq -r '.last_assistant_message // ""' <<<"$in" | sed -E '/^[[:space:]]*$/d' | tail -1 | sed -E 's/[*_`]+//g; s/[[:space:]]+$//')
[ -n "$last" ] || exit 0
# Rule 2's check-in (okay, amend, override, defer) is the required answer format, not a yes/no or either/or question.
command grep -qiE '\b(ok|okay)\b.*\bamend\b|\bamend\b.*\boverride\b|\bdefer\b.*\boverride\b' <<<"$last" && exit 0
# Closed questions only (operator 2026-11-10: "focus on what a closed question is"); everything else is open.
#   yes/no    the question opens with a yes/no verb (do, does, should, can, would, is, are, want me to ...) or
#             ends on a tag (..., ok? right? yes or no? y/n)
#   either/or two or more fixed choices joined by "or", with no open alternative ("or something else")
#   menu      a numbered or lettered list of choices with no write-in, ending on a question
hit=
if command grep -qiE '\?$' <<<"$last"; then
  q=$(sed -E 's/.*[.!:;][[:space:]]+//' <<<"$last")      # the question itself: the last sentence
  open_alt='(or|and)[^?]*(some|any)(thing|where|one|body) else|or other|write (in )?(your|my) own|your own (answer|words)'
  command grep -qiE '^(do|does|did|should|shall|can|could|would|will|is|are|am|was|were|may|might|want|wanna|ready|ok|okay|good|sound|sounds|have|has)([[:space:]]|$)' <<<"$q" && hit=yes/no
  command grep -qiE '([[:space:]]|,)(ok|okay|right|yes|no|correct|alright|good|cool|y/n)\?$|yes or no' <<<"$q" && hit=yes/no
  if [ -z "$hit" ] && command grep -qiE '[[:space:]]or[[:space:]]' <<<"$q" && ! command grep -qiE "$open_alt" <<<"$q"; then hit=either/or; fi
  if [ -z "$hit" ]; then
    tail8=$(jq -r '.last_assistant_message // ""' <<<"$in" | tail -12)
    if command grep -qE '^[[:space:]]*(\(?[0-9]+[.)]|[A-Da-d][.)]|[-*][[:space:]]+\*{0,2}[A-D]\)?)[[:space:]]' <<<"$tail8" \
       && command grep -qiE '(which|pick|choose|select|one first|prefer)' <<<"$q" && ! command grep -qiE "$open_alt" <<<"$tail8"; then hit="menu (no write-in)"; fi
  fi
fi
command grep -qiE ",? or i('|’)?(ll| will) " <<<"$last" && hit=either/or
# Rule 8: the agent never tells the operator to merge; merging is the agent's job (auto-merge on green CI).
all=$(jq -r '.last_assistant_message // ""' <<<"$in" 2>/dev/null)
if command grep -qiE "(you|you'll|you will)[[:space:]]+(need to|have to|must|should|can|will need to|got to)[[:space:]]+(click )?merge|please[[:space:]]+(click )?merge|go ahead and merge|merge (it|the pr|this pr|pr #?[0-9]+) (yourself|manually|by hand)|(^|[.!][[:space:]]+)merge (it|the pr|this pr|pr #?[0-9]+)[.!]" <<<"$all"; then
  echo "BLOCKED (question-gate, rule 8): the answer tells the operator to merge. Merging is the agent's job: enable auto-merge (gh pr merge --auto --squash --delete-branch) or wait for green CI and merge it, then report." >&2
  exit 2
fi
[ -n "$hit" ] || exit 0
echo "BLOCKED (question-gate): the answer ends on a $hit question: ${last:0:160}. Pick the path and do it, or ask one open question naming what you are missing." >&2
exit 2
