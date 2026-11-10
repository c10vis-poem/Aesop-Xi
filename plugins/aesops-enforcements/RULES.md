# RULES: the operator's rules (old ten-rule numbering in the table; Rule 12 added 2026-11-10)

**These ten rules override every older rule, in any file.** Old rule text in CLAUDE.md, AGENTS.md and elsewhere is superseded. Operator's orders, 2026-11-05: "the whole point of having Fable consolidate everything down into ten base rules is to override all that old bullshit", and "I want all the hooks and all the rules persistent everywhere." So: ten rules, every one on, on every device, session and cloud. Nothing starts off.

Every hook serves a rule, and runs through `scripts/run-gate.sh`; `scripts/gates.tsv` is the wiring. They were merged, not dropped, because they depend on each other: `enforce-prompt` alone writes the check-in, wrap-up and push markers that rules 2, 6, 7 and 10 read.

"Override" is what the operator types in a prompt: it counts for that prompt only, never from a subagent hand-back. "Revoke" is run by the operator (`! gate off ...`): the agent cannot run it.

| # | Rule | Hooks that enforce it | Override | Revoke |
|---|------|-----------------------|----------|--------|
| 1 | No actions, no reading, no tool use without explicit permission or direction. A `#` message is a direction; okay or yes opens the job; one opening covers the whole job. Inference is not an okay. Once directed, what the job requires gets done first | direction-gate | operator's `#`, okay or yes | `gate off direction-gate` |
| 2 | No state change before check-in: answer is okay, amend or override | direction-gate | okay, override or `#` | `gate off direction-gate`, `gate off enforce-prompt` |
| 3 | Secrets never printed unredacted; git hooks never skipped | secret-guard | `#show-secret <path>` for one call | `gate off secret-guard` |
| 4 | The agent cannot edit settings, enforcement state or the off switches, cannot run `gate off/on`, and cannot set `disableAllHooks` true in any repo, **unless the operator directs it**: a `#` direction that names settings, hooks, gates or the switches opens guard for that prompt only (direction-gate writes the marker; state-guard keeps the agent from writing it) | guard | the operator's `#` direction naming the target, or a `!` line | `gate off guard` |
| 5 | Questions: every menu has a write-in option; no turn ends on a yes/no or either/or question | answer-gate | `#skip-answer` | `gate off answer-gate` |
| 6 | What the task requires gets done before other tools run, and still-owed work carries across prompts: the skills, tools and files in ENFORCEMENTS.md, build docs, a capable subagent | task-gate; enforce-prompt works out what each prompt requires | `#skip-enforce` | `gate off task-gate` |
| 7 | A turn cannot end with required steps missing: skills, tools and reads still owed, opening and wrap-up steps, a subagent's plan and scope, and housekeeping when due (`/housekeeping`, or `#housekeeping-defer`) | stop-gate; session-start and observe-event feed it | `#skip-stop`, `/wrapup-defer N why: ...`; `observe-dismiss <id> "<reason>"` closes a friction event | `gate off stop-gate`, `gate off session-start`, `gate off observe-event` |
| 8 | Read and verify before saying it (operator's Rule 9): no "not found / doesn't exist" answer without a search this turn (absence-gate); no claim cited by file and line unless that file was read this session, and no "done / fixed / passing" after edits unless something ran after the last edit, and no claim that something is false, unsupported or won't work without official documentation fetched or a real trial run that turn; training data is not a source (claim-gate) | answer-gate | `#skip-answer` | `gate off answer-gate` |
| 9 | One session log (operator's Rule 7), two parts in one place: the scratchpad (the agent's notes on what was done all session) and the task log (every repo touch, file write, commit, move, delete, script run, skill used and tool used). At SessionEnd save-session-log commits both to NvAEx-Recaps `session-logs/<date>-<session>/`; no other copy is kept. Part of the wrap-up protocol, not of the GitHub rule | session-log (never blocks) | n/a | `gate off session-log` |
| 10 | Everything GitHub (operator's Rule 8): any fork touched is synced with its main branch first; any repo changed keeps every push and merge until the end; at the end: secret scan, push, PR, CI, with auto-merge and auto-delete set while CI runs. Nobody watches CI and nobody deletes branches by hand. The wrap-up order (`/wrapup`) is the okay to ship; there is no `/ok push`. `#no-merge` and `#keep-branch <name>` are the operator's exceptions | repo-gate (`#skip-repo`); push-gate (`#skip-git`, or "push now"; "hold push" revokes, `/wrapup` opens it); stop-gate; ship-session (`#no-ship`) | as listed | `gate off repo-gate`, `gate off push-gate`, `gate off ship-session` |
| 10s | Sub-agents (operator's Rule 10, 2026-11-10): the job is defined at spawn and broken into tasks; every sub-agent that can write keeps a task file and writes to it at every step (subagent-task-gate). It cannot stop while a task is unwritten or skipped, while a file its brief assigned (`Files:` list, `Paths file:`, `Folder:`) is unread or read only in part, or while a skill or tool its agent definition equips was never used, unless `## Blocked` names it and says why (subagent-stop-gate, subagent_audit.py). Every stop writes an audit line (assigned vs read whole vs partial; skills and tools used of equipped) into the session's task log, with the sub-agent's task file; one let go after 4 blocks is queued as a friction event | task-gate; stop-gate (SubagentStop) | the operator's direct instruction | `gate off task-gate`, `gate off stop-gate` |
| 12 | Read what the operator orders (operator, 2026-11-10): when the operator says to read something (a file, a folder or an asset, with the reason) and says full read or brief analysis, the turn cannot end until that read is done. **Full** (the default): every line of every file; for an asset, every clean MD document in its index folder (vault `Assets-Index/<repo>/clean_md/`, or its `Vendor-Registries/` folder), or with none yet its tree and every doc file. **Brief**: part of the file; for an asset its `chunk.jsonl`, or its current `manifest.jsonl` plus a file it points to. The order stands across prompts until done. Nothing is required that the operator did not order. Training data and another model's word are never a source (Rule 9). Automated runs (`AESOP_AUTOMATED=1`): a highlight, not a stop | source-gate; `asset-manifest <path>` writes manifests | `#skip-source` | `gate off source-gate` |

## 2026-11-10: operator decisions (session 437a362c)

- **Rule 11, routed items (operator):** a routed skill, tool or read that goes unused is a stop gate everywhere, except on automated (unattended) tasks, where it is a highlight, not a stop. task-gate already stops; the automated-task highlight is not built yet.
- **Numbering:** the table above still uses the old ten-rule numbers; the operator's eleven (NvAEx-Recaps `handoff/2026-11-06/RULES-DRAFT.md`) are the authority. Rows 4, 8 and 9 above carry the operator's numbers in brackets. Renumbering the table is still owed.
- **Rule 10, sub-agents:** has no row in this table yet; the gates that exist are under 2026-11-08 below.

## The 14 hooks

Each is one switch. Some run several checks, which stay as separate files in `scripts/` so each can be tested alone.

| Hook | Runs | What it does |
|---|---|---|
| direction-gate | itself | Rules 1 and 2 |
| enforce-prompt | itself, classify | records check-ins and what each prompt requires |
| secret-guard | itself | no secrets printed, no skipped git hooks |
| guard | settings-guard, state-guard | settings, state and switches off limits |
| answer-gate | menu-gate, absence-gate, question-gate | checks menus and the final answer |
| task-gate | agent-type-gate, build-doc-gate, enforce-gate | required work first |
| stop-gate | itself, subagent-stop-gate | no ending with required steps missing |
| session-start | context-diff, housekeeping-check, staged-updates | what the session must know |
| observe-event | itself | queues failures, denials and corrections |
| session-log | change-log, session-ledger, carryover, save-session-log | the one session log |
| repo-gate | sync-on-use, branch-current-gate | repo synced and branch current |
| push-gate | git-gate, ci-ready | no mid-session pushes, no auto-merge without CI |
| ship-session | itself | ships at session end after `/ok push` |

The yes/no check matches phrases, so it catches the common forms of a yes/no question, not every one.

Not wired, not a hook on any event:
- `extras/auditor/settings-snippet.json`: the Stop auditor is an agent-type hook. It cannot pass through run-gate or a kill switch (CONTRACT rule 4) and installing it means editing settings.json. Kept for the operator to decide.
- `bin/plugin-fork-sync`: by hand. It updates plugins, so it was never wired.

## Three guarantees every hook honors

1. **Immutable to the agent.** Rule 4 stops the agent from touching settings, enforcement state and the switches.
2. **Never a bare yes/no.** A block always names what was blocked, why, the override and the revoke. The operator picks.
3. **Revocable any time, mid-session.** `gate off <hook>` creates `~/.claude/state/off/<hook>`; `gate on <hook>` removes it; `gate off all`, `gate on all`, `gate status`. No restart, no settings edit.

## Switches, checked first

`~/.nvaex-hooks-off` (everything), `~/.claude/state/off/aesops-enforcements` (this package), `~/.claude/state/off/<hook>` and `~/.claude/state/off/aesops-enforcements.<hook>` (one hook). `#hooks-off` in a prompt turns every hook off on this device, across sessions, until `#hooks-on`.

## No hook can deadlock a session

- A loose phrase (`scripts/override-phrases.txt`: "override", "go ahead", "I told you", "you can read it", "this is what I want", ...) lets every block through for that turn. Add words freely.
- The same call blocked more than `AESOP_MAX_BLOCKS` (2) times yields; more than `AESOP_MAX_TURN_BLOCKS` (6) blocks from one agent in a turn yields. Logged `LOOP-BREAKER` in `~/.claude/state/hooks.log`. A new operator prompt resets the counts.
- A hook that crashes or times out is allowed and logged. A script that is missing is allowed, logged `MISSING`, told to the agent and reported by `gate status`.
- **Hard guards** (secret-guard, settings-guard, state-guard) are outside the phrases and the loop breaker. Each stops one named action, so the next call still runs; yielding on retry would let the agent reach the operator's settings or secrets by trying three times. The operator keeps `!` lines and `gate off`.

## obs 0051, fixed

direction-gate replaced resume-gate and checkin-gate on 2026-11-06. It is a hard block with no loop breaker: `tests/hooks/direction-gate.test.sh`.

## 2026-11-08: renamed, Rule 8 tune-up, sub-agent write-to-task gates

- **Name.** `nvaex-gates` is now `aesops-enforcements` (operator, 2026-11-08). Switches follow the name: `~/.claude/state/off/aesops-enforcements[.<hook>]`.
- **Loaded at the root, always.** `~/.claude/settings.json` enables `aesops-enforcements@novaexopia`, so every project root gets it.
- **Rule 8, GitHub (the operator's numbering in RULES-DRAFT; Rule 10 in the table above).** The wrap-up order is the okay to ship: `/wrapup` (or an okay/yes during wrap-up, or the old `#ok push`) records it; `#no-ship` withholds it. Stop gate W6c: a touched repo cannot close out to main unless its own files (AGENTS, RESUME, PENDING, README, MEMORY, HANDOFF or CHANGELOG) changed on that branch; the operator's `#skip-docs` lifts it. The Stop answer check blocks any answer that tells the operator to merge: merging is the agent's job.
- **Sub-agents (Rule 10 in RULES-DRAFT).** `subagent-task-gate` (PreToolUse, inside task-gate), to the operator's spec (Read this / Subagent Persuasion 04-05): a sub-agent that can write gets at most 2 read-only calls before its progress file exists; every state-changing call (Bash, Write, Edit, Agent, Skill, WebFetch, MCP) needs a progress-file write since the previous one; at most 3 read-only calls in a row without one; the file must have ## Last action. `subagent-stop-gate` (SubagentStop): no stop with no progress file, a skipped plan step not explained under ## Blocked, done steps with empty ## Findings, a progress file older than the last tool call, or a tool or skill that failed to load and is not explained under ## Blocked; plus the declared-scope check. Up to 4 blocks per sub-agent, then it stops with a logged notice. Exempt: agent types with no Write tool (web-fetch, Explore, Plan, claude-code-guide, statusline-setup).
- **Ship wait (obs 0069).** On a private repo without auto-merge, ship-session waits up to 120 s for a check to register before watching CI; "no checks reported" right after a push is never read as "no CI".
