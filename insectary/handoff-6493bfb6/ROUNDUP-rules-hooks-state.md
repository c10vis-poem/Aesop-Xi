# Roundup: every rules, hooks, stop-gate and session-state document (2026-11-13 13:05, session 6493bfb6)

Owner's order 12:59-13:00: round up every document that holds rules, hooks or stop gates, or points an agent at
them, or tells an agent what the session state is. Four read-only sub-agents (repos, homes, vault/shared/Recaps,
session state). Their own files: agent-rules-roundup-repos.md, agent-rules-roundup-homes.md,
agent-rules-roundup-vault.md, agent-session-state-roundup.md (this folder). Nothing was changed or deleted.
Vault-agent machine lists: scratchpad names.txt, vault.txt, content.txt.

Gaps the agents named: upstream/vendor repos skipped; repo content grep only on agent files (others by name);
session-state search to depth 3-6; not searched: duplicate vault checkout NovAExorpus-6d2f7df..., _personal, zArchive,
_Termux-sync, Drive_sync, vault .trash, transcripts, Recaps secrets/, ~/.hermes/hermes-agent, two master-hook tarballs
(not opened).

## A. Keep (the new source)
- Aesop-Xi branch `rules-v3-2026-11-13` (worktree ~/repos/wt/rules-v3), commit d93661c: the six new rules in
  plugins/aesops-enforcements/RULES.md. Not pushed.

## B. Live code that runs today (rewrite against the new rules)
- Aesop-Xi main plugins/aesops-enforcements/: lib/contract.py (88965), lib/hook.py, lib/jev_audit.py,
  lib/statusline.py, hooks/hooks.json, salary/opening.md, salary/github.md, tests/.
- Installed copies: ~/.claude/plugins/cache/aesop-xi/aesops-enforcements/1.0.0 and 1.0.1 (RULES.md, hooks.json).
- Other live hooks: ~/.claude/hooks/subagent-stop-gate.sh; ~/.claude/agents/hooks/worker-stop-gate.sh;
  ~/bin/agy-stop-gate.sh; vault plugins/greedy-crane/hooks/stop-gate.sh and scripts/worker-stop-gate.sh;
  NovAExopia-main plugins/nvaex-wiki-admin (hooks.json, stop-gate.sh, worker-stop-gate.sh: duplicate of greedy-crane);
  jev-core hooks.json + route/gate/health/fail/scorecard.py; nvaex-memory, nvaex-burn hooks.json.
- Newer code not live: wt/a3-aesop-xi (branch fix/holes-b-task2, PR #98 open): contract.py (100880), hook.py,
  jev_audit.py, hooks.json, opening.md, RULES.md 1.0.3 (edited today, uncommitted).

## C. Stale rules and hook copies (removal candidates; owner marks each)
Aesop-Xi plugin folder: RULES.md.bak5, lib/contract.py.bak .bak3 .bak4 .bak5 .bak8, lib/hook.py.bak .bak3 (protected).
Aesop-Xi copies: Aesop-Xi-contract-a and wt-docs (detached 90b7225); .wt/Aesop-Xi-intake; .wt/aesop-xi-opening;
  silo/Aesop-Xi; .review/fable/Aesop-Xi; fresh-2026-11-10/Aesop-Xi; merge-2026-11-11/NovAExorpus/layers/aesop-xi;
  scratchpad worktree (prunable). Old gate-script system (hooks/*-gate.sh, scripts/*-gate.sh, gates.tsv,
  hooks/ENFORCEMENTS.md, hooks/RULES.md) lives in 5 of these.
Old 7-rule RULES.md (2629): NovAExopia-main, NovAExopia, NovusAExenti, wt/b-novaexopia, .wt/NovAExopia-webview,
  .wt/NovAExopia-wiki-admin, .wt/novaexopia-wiki, .wt/NovusAExenti-wiki-admin, fresh-2026-11-10/NovAExopia,
  silo/NovAExopia.
Other rules docs: NovAExopia(-main) docs/plugins/CONTRACT.md, mods/SPEC.md; wt/b-novaexopia tools/tool_call_interceptor.py;
  wt/a3-aesop-xi protocol/orchestration-contract.md, tools/cross_auditor_orchestrator.py, tools/divergence_detector.py,
  RULES-v2-draft.md, RULES-COMPARE.md (also vault 01-inbox/ copies).
~/.claude: ENFORCEMENTS.md (+ .bak), WRAP-UP.md, INVENTORY.md, hooks/README.md, CLAUDE.md.bak-2026-10-22/-23;
  hooks/: 26 disabled stubs, ~25 *.disabled-20261028 symlinks into Aesop-Xi/hooks, ~14 *.bak gates, hooks.bak-20261028/;
  live symlinks into Aesop-Xi/hooks (carryover, ci-ready, classify, review-changes, run-hook, vault-ship, lib/);
  commands/ok.md defer.md reject.md wrapup.md (+ .bak); plugin cache novaexopia/aesops-enforcements/0.1.0 and
  novaexopia/nvaex-gates/0.1.0; session-work/2026-10-01/{HOOK-PROPOSALS.md, staged-hooks/}, 2026-10-18/pre-observer-install/,
  2026-10-23/{agent-enforcement-hooks.md, install-hooks.sh, install-new-hooks.sh}, 2026-10-29/wiki-admin-homework/P6-*.
~/.agents: AGENTS.md.bak-20261108, .bak-20261109. ~/bin: resume-item, pregrill.
Vault: TOOLS-SCRIPTS-HOOKS-INVENTORY.md; skill-updates/2026-10-08/proposals/hooks-spec.md;
  handoff/2026-10-30/{inventory/active-rules-hooks-plugins-2026-10-30.md, project-memory/rules-hooks-inventory.md,
  thread-handoffs/rules-and-repo-rules.md}; handoff/2026-10-31/homework/P6-* (+ copies in greedy-crane docs/homework,
  hooks/drafts); skill-observations/.remember/logs/hook-errors.log.
Shared storage: Documents/NovAExorpus-v2/handoff/stop-hook-problems-2026-11-11.md; Drive-sync .../Enforcements/
  Copy of rules-and-repo-rules.md (+ .pdf); Download/Fable-2026-11-03/Aesop-Xi/hooks/{RULES.md, settings.hooks.v2.json,
  gate, run-gate.sh}; Download/master-hook.tar.gz, master-hook (1).tar.gz.
Recaps: handoff/2026-11-06/RULES-DRAFT.md; memory/active/enforcements.md; memory/claude-auto/project_hooks_h1_h8.md,
  project_bootstrap_hook_mechanism.md, project_pothook_session_pipeline.md; .wt/recaps-device-setup/device-export/claude/
  ENFORCEMENTS.md; four .wt-session-log-* duplicates.
Loose: ~/repos/wt/HANDOFF-holes-b-2026-11-13.md and 13 msg-*.txt / pr-*.txt drafts.

## D. Session-state documents that point at rules or hooks (rewrite or clean, not delete)
Live repo state files: NovAExopia-main RESUME (l.6, 17), PENDING (l.27, 30, 33, 39, 67), MEMORY (l.7);
  Aesop-Xi RESUME (l.6, 14), PENDING (l.8, 19, 35-53), MEMORY (l.5-8, 11, 18-24, 38, 51-52); vault AGENTS.md (l.89, 96, 130),
  vault PENDING (l.21-111), agents/AGENTS.global.md; Recaps memory/general.md (l.43, 56), memory/claude/MEMORY.md,
  memory/2026-11-10, -11, -12, -13 daily files; AGENTS.md of all 7 base repos (rules restated).
Old repo clones with their own state: ~/repos/NovAExopia (detached 59dfff3, merge conflict in marketplace.json).
Handoffs: Recaps handoff/ 46 files 2026-11-05 to 11-13 (all listed in agent-session-state-roundup.md);
  vault handoff/ about 60 files 2026-10-23 to 10-31 and handoffs/ (2026-08); NovAExorpus-v2 01-inbox/HANDOFF-7c7b204b.md.
Contracts: Recaps contracts/ 33 files (2026-11-11, -12, -13) + scores.md (kept by rule 6.2).
Memory: ~/.claude/projects/*/memory 43 files (old handoffs, feedback rules); Recaps memory/claude-auto ~90 notes.
Worktree and snapshot state copies: ~30 sets in .wt, silo, fresh-2026-11-10, wt, merge-2026-11-11, .review.
Vault oddities: RESUME.conflict-android-20261031T173452Z.md; __RESUME.md/_PENDING.md/AGENTS.md nested path.

## E. Bugs found during the roundup (freelance, rule 3.3)
1. Sub-agent hand-backs are read as the owner's commands: a report quoting `#go` signed contract A (13:01); one quoting
   `#override` and `#go` lifted the gates and tried to sign again (13:02); one quoting `#ok` accepted contract A (13:03).
   The owner typed none of them.
2. Protection refuses a read-only grep whose text names secret-file words only to exclude them (13:00).
3. The stop gate counted AGENTS.md unread although the harness had loaded it (10:53).
4. greedy-crane quarantine flagged the owner's own DRAFT-LIST as an injection ("reveal") (10:53).
