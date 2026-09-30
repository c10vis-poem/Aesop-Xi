# AGENTS.md

Repository: `aesop-xi`

Authority: NovÆxorpus Master Canon Specifications

Read by ANY agent working in this repo — Claude Code, Codex, DeepSeek Harness
(dsh), Prime Agent, Hermes, others. Engine-specific behavior in CLAUDE.md;
this file is the universal contract.

## RULE 1 — NO ACTION WITHOUT AN EXPLICIT PROMPT

A skipped or unanswered question is NOT consent. No action — reading,
searching, or anything else — without an explicit prompt or permitted
request. State-changing or not, it doesn't matter.

## RULE 2 — READ THE REPO'S OWN CLAUDE.MD AND RESUME.MD FIRST

Before doing anything else — before investigating, before answering a
question about state — check for and read this repo's own CLAUDE.md and
RESUME.md. Operator's standing convention across all their repos for
months. Not optional; step one, every session, every repo.

## GH workflow (every repo)

1. Feature branch (never commit to `main` directly).
2. Before every push, scan the diff for secrets/API keys; refuse if found.
3. Push, open a PR, track CI.
4. On green CI, auto-merge into `main` immediately.
5. Leave the branch in place after merge.
6. Forked repos: at session start, sync fork's default branch from
   `upstream` before any other work.

The point: everything reaches `main`. A branch that never gets a PR
opened, or a PR that never gets merged, is a failure of this rule, not
a valid alternative to it. Don't let work sit stranded.

## Runtime memory stack

**aesop-xi is the canonical home** for the entire runtime memory /
routing / retrieval system per naming canon ("memory layer, context
formatting, tool and context orchestration, protocols"). Full architecture,
component roles, decisions, and disk layout: see `CLAUDE.md` §Runtime
memory stack. Not duplicated here — that section is the single source of
truth for every agent, engine-agnostic.

Two things every agent MUST know:
- **Never call mem0 or terrestrial-brain directly.** All memory access
  goes through OmniRoute at `localhost:20128/mcp`. OmniRoute dispatches
  intelligently and taps every response for async writes to mem0 habits +
  Reasoning Bank traces. Direct calls bypass the observation layer.
- **Every session starts with `bash tools/bootstrap.sh`** in any repo.
  Idempotent; hydrates runtime deps (Postgres, OmniRoute, keys, skills)
  and syncs the repo with origin/main.

## Cross-engine compatibility (this file, tool-agnostic)

Any agent reads this file, not just Claude Code. Testing-derived rules:

- **Honey applies universally** — natively in Claude Code, as a text-strip
  layer in Codex, as a Cordis plugin in DeepSeek Harness (dsh). Apply its
  rules regardless of engine.
- **task-observer / GSD-style skill scaffolding is Claude-Code-only.**
  Codex cannot parse markdown skill wrappers or the dual-layer activation
  protocol; dsh's sandboxed plugin layer blocks the observation-log writes
  entirely. Do not expect either to work, or force them, under Codex/dsh —
  that's the `.claude/` directory's job.
- **Claude Code and any local engine (Prime Agent, Codex, dsh) are never
  active in the same repo directory at the same time** — running two
  simultaneously causes git-lock and file-write races.

## Hook conventions per engine

- **Claude Code**: hooks live in `~/.claude/hooks/` (device-local); sourced
  from `aesop-xi/skills/omniroute/hooks/claude-code/`. `PreToolUse` queries
  OmniRoute for relevant memories; `PostToolUse` writes trajectories.
- **Codex**: hooks live in `~/.codex/hooks/`; sourced from
  `aesop-xi/skills/omniroute/hooks/codex/`. Same signal points, different
  hook API.
- **dsh (DeepSeek Harness)**: Cordis plugin under
  `aesop-xi/skills/omniroute/hooks/dsh/`; installed via `cordis add`.
- **Prime Agent / Hermes / other**: shape TBD; capture per-harness plugin
  layer as we identify them.

Source: operator-confirmed 2026-09-15; cross-linked in
`~/.claude/CLAUDE.md` on the operator's device and in the
`gh-workflow-convention` memory entry.
