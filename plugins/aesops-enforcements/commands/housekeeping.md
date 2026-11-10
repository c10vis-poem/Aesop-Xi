---
description: Run weekly housekeeping - report, act on each routine with the operator, then mark it done
---
Run housekeeping now:
1. Run `${CLAUDE_PLUGIN_ROOT}/bin/housekeeping report` and read the file it prints.
2. Show the operator the report in plain words, then work through it: recaps to roll up, repos to clean, the observation review (task-observer), cloud billing, builder reminders.
3. Flag old terms and plans that contradict current decisions, with their age.
4. Merging, deleting, discarding and anything outside this device need the operator's okay per item. A "NOT CHECKED" line stays open: say so.
5. When every routine has run, run `${CLAUDE_PLUGIN_ROOT}/bin/housekeeping done`, then report what was done and what is still open.
