# Session wrap-up protocol

Triggered ONLY by the `/wrapup` command (`~/.claude/commands/wrapup.md`); mentioning "wrap up" in a sentence does nothing. Wrap-up mode unlocks the git gate. Do the steps in order, then tell the operator.

1. **Commit** every repo touched this session onto local topic branches (good messages, no `git add -A` of old work). Don't push one by one.
2. **Task-observer:** log this session's corrections and rule violations as observations, and mark resolved ones.
3. **Memory:** save new durable facts and feedback, and update or delete stale notes. Write a handoff note only from files actually read (list what was read and what wasn't).
4. **PENDING.md** (vault): add new open items, remove finished ones. Update `last-housekeeping:` if housekeeping was done.
4b. **Per-repo docs, for EVERY repo touched this session** — done here at wrap-up, not scattered through the session:
   - `CLAUDE.md`: update it if this session changed the repo's rules, workflow, layout or conventions.
   - `MEMORY.md`: **every repo gets one.** Create it if missing (durable facts about the repo: what it is, decisions, gotchas, current state, dated). Add anything new learned this session.
   - `PENDING.md`: add this repo's new open items, remove finished ones.
   - Commit these onto the session branch with the rest of the repo's work, so they ship together.
5. **RESUME.md** (vault, plus any repo worked in that keeps one): **rewrite from scratch**: state, decisions, open items in order, next steps, sources read/not read. Enforced: in wrap-up mode the Stop gate (`stop-gate.sh`) refuses to end the turn until the vault RESUME.md has changed this session.
6. **Ship now:** run `~/.claude/hooks/ship-session.sh --now <session_id>` (preview first with `--dry-run <session_id>`). It pushes every branch committed this session, opens PRs, turns on auto-merge, and deletes branches **only after MERGED**. Report the results. (The SessionEnd hook runs the same script again as a safety net; it finds nothing left if this step worked.)
7. **Recap:** check the vault `_recaps/<date>-<sid8>.md` (it's git-ignored).
8. Tell the operator in a few lines: shipped, pending, anything that needs their action.
