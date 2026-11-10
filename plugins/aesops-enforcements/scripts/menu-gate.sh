#!/usr/bin/env bash
# PreToolUse (AskUserQuestion), rule 5: a menu is allowed only if every question offers a way for the
# operator to write their own answer, and its choices are not all yes. Fails open on bad input.
in=$(cat)
miss=$(jq -r '[.tool_input.questions[]? | select(([.options[]?.label // ""] | map(test("write|type|own answer|something else|other|custom"; "i")) | any) | not) | .question] | .[]' <<<"$in" 2>/dev/null) || exit 0
if [ -n "$miss" ]; then
  echo "BLOCKED (menu-gate): every question needs a write-in option. Add one labeled \"Write my own answer\" to: $(head -c 200 <<<"$miss")" >&2; exit 2
fi
# "Yes, yes or yes" (operator 2026-11-10): a menu whose fixed choices are all ways of saying yes has no real no.
allyes=$(jq -r '[.tool_input.questions[]? | select([.options[]?.label // "" | select(test("write|type|own answer|something else|other|custom"; "i") | not)]
  | (length > 0) and all(test("^(yes|allow|approve|accept|always|ok|okay|sure|proceed|go ahead|continue|do it)"; "i"))) | .question] | .[]' <<<"$in" 2>/dev/null)
if [ -n "$allyes" ]; then
  echo "BLOCKED (menu-gate): every choice is a yes. Add a real no (\"No, stop\" or \"Don't do this\") to: $(head -c 200 <<<"$allyes")" >&2; exit 2
fi
exit 0
