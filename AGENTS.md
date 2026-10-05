# Æsop-Xi — repo conventions (every agent: Claude Code, Codex, dsh, Hermes, Prime Agent)

[IF THIS HAS CHANGED SINCE 9-01-2026 THIS DOCUMENT NEEDS TO BE UPDATED TO REFLECT THAT] 

Applies to any agent session working in this repo, regardless of which
session or model. Created 2026-08-31
— previously nonexistent despite RESUME.md
implying a handoff process was already in place.

## Operator Rule 1 — no action without an explicit prompt

A skipped or unanswered question is NOT consent. No action — reading,
searching, or anything else — without an explicit prompt or permitted
request. State-changing or not, it doesn't matter.

## Operator Rule 2 — read this file and RESUME.md first

Before doing anything else in this repo, read this AGENTS.md and RESUME.md.
Standing convention across the operator's repos for months — step one,
every session, no exceptions. (Complements the session-handoff workflow below.)

## Session handoff workflow

- **`RESUME.md` is fully rewritten at the end of every session** — never appended
  to. It is a snapshot of current state, not a running log. (The pre-2026-08-31
  version had grown to 300 lines across many sessions and contained literal
  unresolved git conflict markers from a stash that was never cleanly finished —
  that's what happens when this rule isn't followed.)
- **Anything flagged during a session but not addressed goes into `unresolved.md`**
  at repo root, not into RESUME.md. `unresolved.md` is a durable, cross-session
  backlog — items persist until resolved or explicitly dropped, and it is NOT
  rewritten each session the way RESUME.md is.
- **Review open `unresolved.md` items with the user early in a session** that
  touches this repo, rather than silently carrying them forward or silently
  dropping them.
- `RESUME.md` may point to specific `unresolved.md` items when they're relevant to
  the immediate next session; `unresolved.md` remains the permanent home for
  everything else.

## Memory — three separate systems, don't conflate them

- **Dev-process continuity building Æsop-Xi**: this file + `RESUME.md` +
  `unresolved.md`. Operational, about the build process.
- **The finished Æsop-Xi agent's own runtime memory model**: `ARCHITECTURE.md`
  §4 (Declarative / Recall / Strategic / Working-Ephemeral) and
  `protocol/memory.md`. Product architecture spec.
- **The whole stack's runtime memory infrastructure** (the actual mem0 /
  terrestrial-brain / OmniRoute / reasoning-bank services that every agent
  across the 7 base repos consumes): see `## Runtime memory stack` below.
  aesop-xi is the canonical home per the naming canon ("memory layer, context
  formatting, tool and context orchestration, protocols"). The other 6 base
  repos reference this section, they don't duplicate it.

## Runtime memory stack (data plane, canonical here)

**Architecture — one-way routing through OmniRoute:**

```
[any agent, any harness]
      │
      ▼
OmniRoute @ localhost:20128/mcp     ← single MCP endpoint
      │
   ┌──┴────────┬────────────────┐
   ▼           ▼                ▼
 mem0     terrestrial-brain   local SQLite FTS5
 (hosted) (Postgres+pgvector) (offline fallback)
      │
      ▼  async tap on every completion
 mem0 habits + Reasoning Bank failure traces
                │
                ▼
   NovAExorpus/05_episodic_logs/
```

**Layer roles:**
- **mem0** — in-session episodic state, user habits, "what was said 2 min ago"
- **terrestrial-brain (= OB1)** — structural governed retrieval via MCP
  (`knowledge.retrieve`, `knowledge.record`); universal, node-independent
- **OmniRoute** — the gateway; dynamic-dispatch + local fallback + async
  memory tap; agents never manually pick backends
- **ReasoningBank** — judges each finished task (success/fail) and distils
  up to 3 lessons, recalled for similar tasks later. Planned as an OmniRoute
  plugin; not built. No crash recovery.
- **Continual Harness** — reset-free self-improvement loop (rewrites its own
  strategy prompt, skills and memory mid-run). No automatic rollback; backups
  are restored by hand. Scope for us still open; not built.

**Homes on disk (all under aesop-xi):**
- `skills/omniroute/` — routing config, decay policies, memory-tap rules
- `skills/mem0/` — mem0 client config, per-project user_id defaults
- `skills/terrestrial_brain/` — obsidian sync config, ingestion routes
- `tools/omniroute/` — start/stop scripts, port 20128 bind
- `tools/reasoning_bank/` — ledger reader/writer; trajectories flush to
  `NovAExorpus/05_episodic_logs/`
- `tools/continual_harness/` — supervisor loop

Upstream fork trackers stay for sync only (`clovis-mem0-vingiaN`,
`NovA-terrestrial-brain`, `OmniRoute`, `reasoning-bank`) — operational
code lives here.

**Runtime state (not repo):**
- Postgres data: `~/pgdata/` on device; migrates to Jetson later
- Keys: `~/.mem0/.env` (chmod 600), `~/.openwiki/.env`,
  `~/repos/NovA-terrestrial-brain/local-mcp/.env.local`
- mem0 hosted MCP: `https://mcp.mem0.ai/mcp`; key starts with `m0-`
- OmniRoute upstream provider: OpenRouter (single, 160+ models via
  `OPENROUTER_API_KEY`)

**Bootstrap** — `tools/bootstrap.sh` is canonical. Every other repo's
`tools/bootstrap.sh` is a thin wrapper that calls this first, then does
repo-specific post-boot. Idempotent, fast on hot start, loud on failure.
Runs on session start via AGENTS.md instruction, git post-checkout hook,
or manual invocation.

**Decisions:**
- Chose hosted mem0 MCP over self-hosted docker server (Termux can't run
  Docker; hosted covers cross-device automatically).
- mem0 pip SDK doesn't install on Termux (grpcio wheel build fails on
  bionic); use MCP + plugin only. SDK path via proot-Debian if ever needed.
- Terrestrial-brain runs phone-local NOW (Termux Postgres 18.2 + pgvector
  v0.8.6 built from source with `MKDIR_P/INSTALL/SHLIB_LINK` overrides);
  migrates to Jetson later via env var URL swap, no rebuild.
- OmniRoute → OpenRouter as single upstream, not direct provider APIs.
- Repo-shape decisions (Novus-Agenti demolish, restructure) deferred to
  post-grill session.

## Termux/Android platform gap — the general fix (2026-09-06)

`bootstrap-stack.sh`'s Android failures (code-review-graph, notebooklm-py/Playwright,
OmniRoute/libsql) share one root cause: those packages target **glibc Linux**;
Termux is **Android/bionic**. `proot-distro login debian` (already installed on
this phone) is genuine glibc aarch64 — route glibc-only pieces through it instead
of patching each package individually. Use Termux's own native builds first where
they already exist and are better (e.g. Postgres: Termux ships PG18 natively,
faster and no proot needed — pgvector just needs building from source with
`MKDIR_P`/`INSTALL`/`SHLIB_LINK` overridden, since Termux's own `pg_config` bakes
in nonexistent `/usr/bin/*` paths and doesn't link `libm`). `proot-distro login`
runs with `--kill-on-exit` — a persistent background process needs the *outer*
`proot-distro login ...` command itself backgrounded, not just an inner
`nohup`/`disown`, or it dies the instant the invoking shell returns. Full account:
the "Bootstrap Triage" artifact from the 2026-09-06 session.

## Discovered assets (2026-08-30/31) — previously unused, now catalogued

Found sitting unused in `~/downloads` or built during this session. Don't
re-discover these from scratch:

- **`~/tools/geniex-bench`** — GenieX's NPU benchmark tool (native Android/bionic,
  no proot needed). Confirmed working: `--plugin {llama_cpp|qairt} --device
  {cpu|gpu|npu|hybrid|auto} -m <path-or-model-id>`. This is the tool to point at a
  Gemma GGUF for a real NPU benchmark. Needs `LD_LIBRARY_PATH` set to
  `lib:lib/llama_cpp:lib/qairt:lib/qairt/htp-files` (all four, not just one — this
  bit initially non-obvious). Set up via `aesop-voice-pipeline` skill's
  `setup_geniex_bench.sh`.
- **`~/tools/whisper-parakeet`** — whisper.cpp + NVIDIA Parakeet toolkit (glibc,
  needs the Debian proot). Includes `whisper-server`, `whisper-quantize`, Parakeet
  CLI/test binaries. Set up via the same skill's `setup_whisper_parakeet.sh`.
- **`~/downloads/processor_config.json`** — a real `Gemma4AudioFeatureExtractor`
  config (mel spectrogram params) for the multimodal Gemma 4 models also in
  `~/downloads` (`gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` etc.). Needed if their audio
  branch ever gets run.
- **`~/downloads/htp_backend_ext_config.json`** — NOT directly reusable: targets
  `dsp_arch: v73` / a ViT vision graph, not this phone's actual v79 chip or an LLM
  graph. See `aesop-voice-pipeline/references/htp-backend-mismatch.md` for detail.
  Regenerate fresh via Qualcomm's own AI Hub/QAIRT tooling when actually needed,
  don't hand-patch this one.
- **`~/downloads/mcp.json`** — a working MCP server config for an `agentmemory`
  server via `npx`, usable as-is.
- **`~/downloads/quickstart.md` / `usage.md`** — real docs for OpenWiki (your
  `c10vis-poem/openwiki` fork), not generic filler.
- **`~/downloads/INSTRUCTIONS.md`** — doc-writing instructions for the
  `Novus-Agenti` wiki project specifically.
- **ECC** (`~/repos/ECC-aesop`) — a real, ready-to-go Claude Code plugin
  (`.claude-plugin/plugin.json`) never actually installed via the plugin system.
  Confirmed against `~/.claude/plugins/installed_plugins.json` (only 3 unrelated
  plugins listed). Deferred to a future flash session — see `unresolved.md` in
  NovAExorpus.

## Enforcement hooks H1–H7 travel with this repo (2026-10-02)

`.claude/settings.json` registers every phone hook (RESUME/check-in/Stop gates, sync-on-use, ledger, ship-session, secret-guard, ENFORCEMENTS gate, prompt classifier, branch/git gates, context-diff, housekeeping, archive) through `deploy/phone/hooks/run-hook.sh`. A session started in this repo gets them on any device; where `~/.claude/hooks/<name>` already exists (this phone) the launcher exits 0 so nothing fires twice. Sources stay in `deploy/phone/hooks/` — edit there, copy to `~/.claude/hooks/`.

## Subagents — standing order (operator, 2026-10-01; updated 2026-10-04)
This is the explicit ask the Agent tool requires; don't wait to be told.
- A request with independent parts → spawn subagents for them in parallel; do the
  remaining parts myself meanwhile; never sit idle waiting.
- Size the model per task: haiku = mundane lookup/grep/listing; sonnet = normal
  research, audits, routine code; opus/fable = hard reasoning, architecture, debugging.
- Single, simple, sequential tasks stay inline — no spawn.
- **Every subagent keeps a live progress file**, and the spawn prompt must say so:
  `~/.claude/session-work/<date>/agent-<topic>.md`, written FIRST (before any work)
  and updated after every step, with:
  - `## Plan` — every step as a checkbox, `[x]` done / `[ ]` pending
  - `## Last action` — timestamp + what it just did / is doing now
  - `## Findings` — results so far (so nothing is lost if it's stopped)
  - `## Blocked` — anything it's stuck on
- When the operator asks where a subagent is, read its progress file and answer —
  never wait for it to finish. A stale `Last action` timestamp = likely hung: say so
  and offer to stop it; its findings survive in the file.

## Every agent must know

Two things every agent MUST know:
- **Never call mem0 or terrestrial-brain directly.** All memory access
  goes through OmniRoute at `localhost:20128/mcp`. OmniRoute dispatches
  intelligently and taps every response for async writes to mem0 habits +
  Reasoning Bank traces. Direct calls bypass the observation layer.
- **Every session starts with `bash tools/bootstrap.sh`** in any repo.
  Idempotent; hydrates runtime deps (Postgres, OmniRoute, keys, skills)
  and syncs the repo with origin/main.

## Cross-engine compatibility

Testing-derived rules:

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

## Git workflow — PR required, no direct pushes to main

Push changes to a branch, open a PR, let the `CI` GitHub Action run, merge
once it's green (`allow_auto_merge` is on, so this can auto-merge with no
manual click). Do not `git push origin main` directly for code changes.
Before every push, scan the diff for secrets/keys and refuse to push if any
are found. Delete the branch after merge (`--delete-branch`; repo auto-delete
is on) unless the operator says otherwise for a specific case.

The point of this workflow is that everything reaches `main` — a branch
that never gets a PR opened, or a PR that never gets merged, is a failure
of this rule, not a valid alternative to it. Don't let work sit stranded.

## Scoping note

This file only loads automatically when a session's working directory is inside
this repo. A session started elsewhere (e.g. `~/downloads`) will not see it or
`RESUME.md`/`unresolved.md` unless it's explicitly pointed here.
