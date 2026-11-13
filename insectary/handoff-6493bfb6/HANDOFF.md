# Handoff: session 6493bfb6 (2026-11-13), rules rewrite and the push/quarantine job

## Done
- The six new rules: plugins/aesops-enforcements/RULES.md on this branch (rules-v3-2026-11-13, commit d93661c),
  pushed to GitHub 13:34. Merge to main LAST, after the job below.
- ~/.agents/AGENTS.md item 1: the owner rule (rules in Aesop-Xi; nothing without a signed work order; read and notes only).
- Roundup of every rules/hooks/stop-gate/session-state document, GitHub branch audit, local git audit: the files in
  this folder.

## The job (contract B, signed #go #push 13:34; owner copy NvAEx-Recaps/contracts/2026-11-13/6493bfb6-B.md)
1. Push what's relevant to main: vault #58 #59 #83, supabase/memory SQL branches, rules-fix-2026-11-09 settings
   (minus greedy-crane hooks), wa_quarantine.py edit; NovAExopia #32 #14, webview-and-mods, gemini-skills-adopt
   (re-pathed), jev-core 0.4.2 if newer; Aesop-Xi intake-skill; notify-vault CI PRs in Novus/Hyperion/CloviX;
   AEthX docs/npu-proof; Recaps #5 #14, handoff/8e3a65ec-tracks, uncommitted memory/contracts/logs, device inventory.
2. Aesop-Xi/insectary/ = buggy (old rules/hooks/gate branches #98 #97 #84 absence-gate rebuild; vault #71 #73 rule
   branches; lie-test; RULES v2 draft/compare; 285-item list; bug lists; old ~/.claude hook system).
   Aesop-Xi/archive/ = everything else not merged (merge-2026-11-11 whole-vault restructure, old corpus-ingest plugin,
   NovAExorpus-v2 findings/plans, loose drafts, unarchived session-work reports, ingest ledgers).
   Branches pushed as insectary/<repo>/<branch> or archive/<repo>/<branch>; MANIFEST.md in each folder.
3. Close PRs/branches now on main or quarantined. 4. Merge this rules branch last.
Not started at session end except this branch push. Nothing deleted from disk.

## Bugs for the hook rewrite (see ROUNDUP section E)
Sub-agent hand-backs counted as the owner's #go/#override/#ok (signed and accepted contract A, 13:01-13:03); protection
refuses read-only grep naming secret words; opening counts a harness-loaded AGENTS.md unread; quarantine flags the
owner's own list; cp from ~/.claude/state refused even to copy the agent's own proposal/notes.

## Not read this session
Most of the roundup's listed files (found by name/grep only); the old Aesop-Xi branches' code.
