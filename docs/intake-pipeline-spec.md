# Intake workflow spec (draft 1, 2026-10-28)

Status: design only. Nothing here is built, installed or configured. The operator approves each piece.

Source: RESUME.md lines 29-48 (operator), plus the operator's corrections to stage 1 in session 37dc78ed.

## The pipeline

```
prompt ─► 0 Intake ─► 1 Context fan-out ─► 2 Orchestrator (+Jev) ─► 3 Proposal to operator
                         │                                              ▲
                         └► 1b Freshness gate                           │
                                                 4 Auditor (+Jev) ──────┘  (runs while the operator reads 3)
```

## 0. Intake (prompt engineering)

- **Now:** the `prompt-enhancer` plugin (v1.0.5, `~/.claude/plugins/cache/local-zips/prompt-enhancer`). Its manifest says it turns a rough prompt into one rewritten prompt and never runs the task. The rewritten prompt goes on to stage 1; the operator's original words stay attached, so later stages quote them (AGENTS rule "use the operator's words").
- **Later:** a Qwen STT model drives the voice stack. A custom MCP server runs the prompt-engineering step and hands off to the on-device execution agent, which starts the routing pipeline. Stage 0's output contract (original text, rewritten prompt, detected intent) stays the same, so stages 1-4 don't change when voice replaces typing.

## 1. Context fan-out

Cheap reader agents (haiku) each read one source in full and return a short, cited summary:
RESUME.md, AGENTS.md (vault + `~/.agents/AGENTS.md`), PENDING.md, and MEMORY.md when the prompt touches durable facts.

### 1a. Memory tiers: draft definitions (operator to confirm)

These are the files that exist today, as read this session. Each one gets a single job.

| Tier | File | One job | Lifetime | Written by |
|---|---|---|---|---|
| Rules (static) | `AGENTS.md` (vault, repos, `~/.agents/`) | How every agent must work | Until the operator changes a rule | Operator approves |
| Project semantic | `MEMORY.md` (vault) | Durable, dated facts about the repo | Permanent, newest first | Wrap-up |
| Project semantic | `CONTEXT.md` | Glossary: what names mean | Permanent | Grill sessions |
| Session semantic | `RESUME.md` | Where the last session stopped: START HERE plus verified STATE | Rewritten every session | Wrap-up |
| Backlog | `PENDING.md` | Open work that outlives a session | Until done with evidence, or dropped by the operator | Any session |
| Short-term episodic | session ledger, change-log, transcript | What this session did, as it happens | This session | Hooks |
| Project episodic | `_recaps/<date>-<id>.md` | Automatic per-session record (repos, files, git actions) | 30 days, then a monthly roll-up | SessionEnd hook |
| Project episodic | `handoff/<date>/` | Work bundle handed to another device or model | Until the receiving session absorbs it | The handing-off session |
| Persistent (agent) | `~/.claude/projects/.../memory/*.md` | Claude-only feedback and preferences | Permanent | Claude |
| Persistent (private) | `~/repos/NvAEx-Recaps` | Private recaps and secrets | Permanent | `nvaex-secret`, wrap-up |

Overlaps and stale items found while drafting. These are flagged, not removed:
- `handoffs/` (with an s) holds August 2026 HANDOFF files; `handoff/` holds October. Two folders do one job.
- `__RESUME.md/` is a folder (the work queue), but its name reads like the RESUME file.
- `pending/` holds only `POINTER.md`, next to `PENDING.md`.
- `NvAEx-Recaps` has its own AGENTS, MEMORY, PENDING and RESUME files. Their relationship to the vault copies is undefined.
- Recap `2026-10-28-37dc78ed.md` (this session) has empty sections so far.

### 1b. Freshness gate (blocking)

The operator's rule: every repo up to date, no merges left behind, and no upstream drift reported as days, weeks or a month old.

Before the orchestrator plans anything, it checks every repo in `~/repos/` and the vault:
1. local default branch == origin default (fetch, then compare)
2. the fork is not behind upstream (`gh repo sync` dry check)
3. no unmerged local or remote branches, no stale open PRs
4. after any merge to `main`, the device clone is pulled (RESUME STATE line 18)

Any drift becomes the proposal's first item, so it is fixed before the asked-for work starts. The fix goes through the fork pipeline: sync, then PR, then CI. The gate does not pull or merge on its own unless the operator makes that standing.

Baseline audit, 2026-10-28 (read-only; full table in `agent-repo-freshness.md`): 19 of 77 repos fully current. 40 forks are behind upstream, the oldest by 55 days (pm-claude-skills). 6 local clones are well behind their own origin. 14 repos have remote branches with unmerged commits. The worst repos for open PRs are speech-to-speech (30, the oldest 89 days) and reverse-skill (23, the oldest 51 days).

## 2. Orchestrator (+Jev)

- **Model:** opus or fable.
- **Inputs:** the stage 0 prompt, the stage 1 summaries, the freshness report.
- **Candidate set:** skills, tools, scripts, agent configs, and routes. The routes are: dynamic workflow, workspace marketplace, preconfigured agent package, slash-command execution, model route, straight execution, or another reasoned course.
- **Jev's role:** Jev (plugin `jev` v0.3.3) is a typed-decision mod. `$.jev.ask` takes Choice, Score and Noul questions and returns calibrated probabilities, never text. The orchestrator writes the candidate routes, Jev scores and ranks them, and the orchestrator writes the plan from the ranking.
- **Jev blockers today:** its `hooks/` folder is `hooks.off-20261028` (off by operator order), so `$.jev` is not live. It also needs a provider key (TypeSafe or OpenRouter; the operator already uses OpenRouter) and Claude Code ≥ v2.1.287. Turning it back on is the operator's command.
- **Output:** one recommended course of action, no menu. It covers the route, the tools and skills, the task list, the model per task, and the reasons.

## 3. Proposal to the operator

- The orchestrator's plan, with the freshness items first.
- A "missed angles" section that fills in when the auditor finishes.
- The operator approves item by item (AGENTS: approval is per item).

## 4. Auditor (+Jev), in parallel with the operator's review

- A background subagent starts the moment the proposal is shown, so the operator is never waiting on it.
- It gets the same inputs as the orchestrator, plus the plan. It asks Jev Noul questions, for example "does this plan skip a rule in AGENTS.md?", "is a needed repo stale?", "is there an installed skill that does this already?".
- Its findings append to the proposal before the operator approves. If the operator approves first, the findings arrive as a follow-up.
- It is modeled on Claude's subagent task-auditor pattern (the Stop `type: agent` AUDITOR in settings.json).

## Governance (built in the hook congruence pass, item 2)

- Stop-gate hooks in settings.json enforce the stages: no execution before an approved proposal, no proposal while the freshness gate fails.
- Only operator-written hooks run. A plugin hook runs only if the session's own marketplace or agent package includes it.
- **Skill/tool loading gate (operator, 2026-10-28):** a hook that blocks work when the task calls for a skill or tool that was not loaded. Today's ENFORCEMENTS rows fire only on keywords. In session 37dc78ed, the agent ran a whole Drive ingest with only task-observer loaded, until the operator asked. The gate's required-skill list should come from the stage-2 route plan (Jev via `classify.sh`'s `CLASSIFY_URL` backend), not from keyword rows. Its checks: each skill or tool the plan names is loaded before the first tool call that does that work; every Workflow `agent()` names a model (observation 0048).
- **Task auditor with tool denial (operator, 2026-10-28):** a subagent audits each task through the dynamic-workflow audit pattern. Whenever the operator pointed at a skill or tool and the agent did not load it, the agent loses tool access until it does. Mechanism: the auditor writes a verdict to a state file the agent cannot change (state-guard). A PreToolUse gate on `*` reads that file and denies every tool except Skill and ToolSearch while a load is owed. A Stop `type: agent` auditor runs only at turn end, so it cannot deny tools mid-turn on its own; the PreToolUse gate does that half.

## Build mapping (proposed)

| Piece | Form |
|---|---|
| Stages 1-4 | Workflow script (fan-out readers, orchestrator, background auditor) |
| Entry point | a skill (`intake`) that runs the workflow |
| Freshness gate | script in Aesop-Xi `hooks/`, called by the workflow and at SessionStart |
| Merge-to-main device pull | hook or GitHub dispatch, decided in item 2 |
| Stage enforcement | Stop/PreToolUse gates, item 2 |

## Open questions for the operator

1. Confirm or correct the tier table (1a), especially what `NvAEx-Recaps` is for, compared with the vault copies.
2. Jev: turn its hooks back on, and which provider key?
3. Advisor mode: is this Claude Code's advisor setting? It was found switched off before (observation 0039). Should it be on for the main session and for every subagent?
4. The 1-hour cache TTL for subagents: not yet verified as configurable per subagent. Look it up before building.
5. Freshness gate: should it fix drift on its own (sync, PR, merge), or report it and wait?
