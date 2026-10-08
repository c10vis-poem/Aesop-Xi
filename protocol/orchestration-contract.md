# D.U.M.B.A.S.S. Orchestration Contract

**Status:** DRAFT v0.3 (2026-09-25; v0.2–0.3 operator decisions: Honey-only compression, routing-driven retrieval across all arms, context-scaled budget), awaiting operator approval. No OmniRoute code is written against
this until it is approved. Scope: the runtime loop every agent request goes through. The finished
Æsop-Xi agent's own memory model stays in `ARCHITECTURE.md` §4 / `protocol/memory.md`.

**Sources read for this draft:** OmniRoute fork `c10vis-poem/NvAEx-OmniRoute` @ `f4afc71` —
`docs/frameworks/{PLUGIN_SDK,PLUGINS,AGENT-SKILLS,LOCAL_CORPUS_CONTEXT,OBSIDIAN_CONTEXT}.md` in full;
`SKILLS.md` §1–130 + custom-skill section; `MEMORY.md` overview, injection, MemoryBackend pattern;
`docs/compression/{COMPRESSION_ENGINES,EXTENDING_COMPRESSION}.md` in full. mem0 fork `server/`
(compose, `.env.example`, `README.md`, `main.py` config). Planning set
`Documents/Dumbass_cloud_config/01–07.md` in full. Live VM services (each round-trip tested).
**Not read:** OmniRoute `MCP-SERVER.md`, `A2A-SERVER.md`, `EVALS.md` body, `WEBHOOKS.md`,
`PLUGIN_MARKETPLACE.md`; Hermes / Qwen Code / Graphify / notebooklm-py source. Claims that depend on
those are marked **OPEN**.

---

## 1. Roles

| Component | What it is | Runs where | Owns | State |
|---|---|---|---|---|
| Agent harness (Claude Code, Hermes, Qwen Code, OpenWiki) | Agent loop + UI | phone / tablet / VM desktop | the conversation | per device |
| **Honey-for-devs** | Output discipline + compression, two halves (§3.1) | harness skill **and** OmniRoute engine | token budget | skill: on phone from the plugin marketplace (greenpt/honey 1.3.1), **not the fork** — reinstall from fork; engine: **to build** |
| **Task Observer** | Skill-improvement methodology (§3.2) | harness skill + OmniRoute tool | the observation log | skill: on phone (source vs. fork unverified); tool: **to build** |
| **OmniRoute** | Gateway / control plane: auth, routing, compression, memory, skills, MCP | VM Docker, `127.0.0.1:20128` | provider keys, routing policy | building from fork |
| **Terrestrial Brain** | Static corpus retrieval (arm 1) | VM, MCP `:8000`, header `x-brain-key` | Postgres `terrestrial_brain` | live |
| **code-review-graph** | Code graph + vector retrieval (arm 2) | VM, MCP `:5555` | per-repo SQLite | live |
| **mem0** | Episodic memory (arm 3) | VM, REST `:8888` + dashboard `:3000` | Postgres `mem0`, `mem0_app` | fork merged, service **to start** |
| **Reasoning Bank** | Success-verified trajectory ledger (§3.4) | OmniRoute plugin | JSONL → Postgres `reasoning_bank` | **to build** |
| **Continual Harness** | Session checkpoint / rollback (§3.5) | OmniRoute plugin | per-session checkpoints | **to build** |
| **Retrieval planner** | Decides per request which arms to query (§3.3) | OmniRoute plugin | nothing (stateless) | **to build** |
| Vault | Source of truth (GitSync → `c10vis-poem/NovAExorpus`) | phone, tablet, VM `~/vault` | all authored knowledge | live |
| Neo4j | Graph store | VM `127.0.0.1:7687` | nothing yet | installed, **no consumer** |

Rule: **only OmniRoute holds provider API keys.** Services that need an LLM or embeddings
(Terrestrial Brain, mem0) call OmniRoute's OpenAI-compatible endpoint with their own OmniRoute key.

---

## 2. The request loop

```
[0] harness launch ── Honey skill + Task Observer skill loaded into the agent's context
[1] agent → OmniRoute /v1  (per-harness OmniRoute API key; REQUIRE_API_KEY=true)
[2] onRequest plugins, by priority (lower first)
      p20  continual-harness   attach this session's checkpoint (if any)       [modifyBody]
      p30  retrieval-planner   classify the request, query EVERY arm it needs — any of
                               mem0 / Terrestrial Brain / code-review-graph, all three,
                               or none — and inject under a context-scaled budget [modifyBody]
      p40  reasoning-bank      open a trajectory record for this request        [addMetadata]
[3] (reserved — OmniRoute's built-in memory injection stays OFF; the planner replaces it)
[4] skill injection   (Omni Skills: observation_log tool, mode=auto)
[5] compression       honey engine only (Caveman removed; RTK off, re-enable only if
                      terminal/test output proves to be the dominant token cost)
[6] route → provider  (OpenRouter / frontier accounts), fallback per OmniRoute combos
[7] tool calls        follow-up retrieval the agent still needs: TB / CRG MCP tools,
                      Obsidian context (read-only scope), Local Corpus (lexical fallback)
[8] onResponse / onStreamEnd
      reasoning-bank      close the record: outcome, tools used, verification evidence
      continual-harness   update the session checkpoint
      memory write        new episodic facts → mem0 (planner-owned, not OmniRoute's regex extractor)
[9] response to agent  (output style per §4)
```

Retrieval policy (operator decision): **retrieval is part of routing.** The planner decides per
request which arms are relevant, and a single prompt can use all three. A greeting pulls nothing;
"what calls requireAuth?" pulls code-review-graph; a long multi-part prompt about the VM build pulls
mem0 + Terrestrial Brain + code-review-graph together. Agents can still call the arms' tools
directly for follow-ups.

Budget (operator decision: do not kneecap long prompts): no fixed token cap. The retrieval budget is
a share of the **target model's context window** (default 25%, configurable), minus room reserved for
the prompt itself and the response. It is split across the chosen arms by result relevance, not
evenly. A hard ceiling exists only to stop injected context from crowding out the prompt/answer.

---

## 3. Component contracts

### 3.1 Honey-for-devs
- **Harness half:** installed from `c10vis-poem/NoVa-honey-for-devs` into every harness
  (`honey-install`). Governs how much the agent *writes*.
- **OmniRoute half:** a compression engine `id: "honey"` registered through OmniRoute's documented
  engine interface (`id`, `compress`, `getConfigSchema`, `validateConfig`, `stackable: true`,
  `targets: ["messages","tool_results"]`). Governs how much gets *sent*. Uses Honey's `eson`
  codec for uniform JSON/tool-result arrays and Honey's terse prose rules for messages.
  Code blocks, identifiers, paths, errors, and secrets-handling text are never altered.
- Pipeline (operator decision): Honey alone replaces Caveman — both do prose condensation, so
  running both is redundant. RTK is off by default; it is the only engine with terminal/test-log
  filters, so it comes back only if measurements show that output dominating token spend.
- Acceptance: OmniRoute `/api/compression/preview` shows savings on a fixed sample set, and the
  compression test gates in `COMPRESSION_ENGINES.md` still pass.
- **OPEN:** how a custom engine is loaded in the Docker image (`~/.omniroute/compression/engines/`
  vs. a fork source change). Decide by reading `strategySelector.ts` before building.

### 3.2 Task Observer
- **Harness half:** the skill (`c10vis-poem/aesop-task-observer`) in every harness, plus the
  activation line in that harness's instruction file.
- **OmniRoute half:** an Omni Skill tool `observation_log@1.0.0` (custom handler, `mode: auto`)
  that appends one observation to **a single shared store**. This replaces the two diverged
  per-device logs found on 2026-09-25 (`~/.claude/skill-observations/` and
  `~/.claude/projects/-data-data-com-termux-files-home/skill-observations/`).
- Record schema = the skill's existing frontmatter (`id, title, status, type, skill,
  proposes_skill, siblings_checked, area, date, session_context`) + `device`, `harness`.
- Acceptance: two different harnesses log through the tool; both entries appear in one listing.

### 3.3 Retrieval arms
| Arm | Interface | Auth | Query shape | Writes |
|---|---|---|---|---|
| Terrestrial Brain | MCP `http://127.0.0.1:8000/mcp` | `x-brain-key` | `search_thoughts`, projects, documents… | via its own tools only |
| code-review-graph | MCP `http://127.0.0.1:5555/mcp` | local-only | `query_graph`, `get_impact_radius`, `semantic_search_nodes`… | graph builds only |
| mem0 | REST `:8888` + OmniRoute `GenericMemoryBackend` | `X-API-Key` | search / add memories | episodic facts only |

- All three index **from** the vault/repos and are rebuildable from them. None writes to the vault.
- **Retrieval planner** (plugin `retrieval-planner`, `onRequest` p30, permission `network`):
  classify intent from the latest user turn (cheap rules first; a small routed model only when
  rules are unsure), call the chosen arms over their local endpoints in parallel with a timeout,
  merge results with source labels, fit them to the context-scaled budget (highest-relevance
  results first, across all arms), inject as one context block. Every decision
  (arms chosen, tokens injected, latency) is recorded in the Reasoning Bank record.
- **OPEN:** whether OmniRoute's MCP server can front external MCP servers (so agents need one
  endpoint instead of three). Until verified, harnesses connect to the TB and CRG MCP endpoints
  directly over Tailscale.

### 3.4 Reasoning Bank
- OmniRoute plugin `reasoning-bank`, hooks `onRequest` (p40), `onResponse`, `onStreamEnd`,
  `onError`; permissions `file-write` only.
- Writes one JSONL record per request to `DATA_DIR/reasoning_bank/candidates/` with `requestId`,
  session, harness, model/provider, tools called, token counts, outcome.
- **Promotion rule (Success Verification Grade):** a candidate becomes a *verified success* only
  with evidence: tests/CI passed, a merged PR, or explicit operator acceptance. Failures go to
  `failure_logs/` as regression fixtures and are **never** positive training data.
- Batch loader (home node, later) moves verified records into Postgres `reasoning_bank`.
- **OPEN:** whether plugin sandboxes keep state across hooks (needed to pair request↔response);
  fallback is keying everything on `requestId` in the file.

### 3.5 Continual Harness
- OmniRoute plugin `continual-harness`, hooks `onRequest` (p20) and `onResponse`.
- Session identity: request header `x-dumbass-session` (set by the harness).
- On request: if a checkpoint exists for the session, prepend a compact checkpoint block (goal,
  done, next, open questions) via `modifyBody`. On response: update the checkpoint.
- Rollback: keep the last N checkpoints per session; a harness can request `?checkpoint=<n>`.
- Checkpoints are working state, never durable truth, and are never written to the vault.

### 3.6 Vault and context sources
- Obsidian context (22 MCP tools): **read scope by default**, write scope only on named keys.
  OmniRoute's WebDAV vault sync stays **off** (GitSync Portal already syncs the vault).
- Local Corpus: pointed at the VM vault clone as a cheap lexical fallback (limits: 5,000 files,
  64 MiB; current vault is ~1,323 files / 66 MB, so it may need a narrower root).

---

## 4. Output style

- **To a human:** Honey terse: answer first, no filler, exact code/paths/commands.
- **Agent → agent / tool results:** minified JSON; uniform arrays in columnar form
  (`{"c":[...],"r":[[...]]}`); `eson` only for high-volume cached pipes.
- **Every task result** closes with: `outcome` (success / partial / failed), `evidence`
  (commands run + results), `files_changed`, `open_items`. This is what Reasoning Bank grades.

---

## 5. Identity, security, cost

- One OmniRoute API key per harness per device; scopes are the minimum each harness needs.
- All service ports bind `127.0.0.1`; devices reach them over Tailscale only. GCP firewall: SSH only.
- Secrets live in `/opt/dumbass/*.env` (mode 600), never in unit files or repos.
- OmniRoute's built-in memory injection stays off; the retrieval planner injects what each
  request needs, sized to the target model's context window.
- The VM runs only while in use: 30-min idle auto-off + 4 AM hard stop; no other scheduled jobs.

---

## 6. Build order (after approval)

1. Start OmniRoute (fork build) + mem0 server; point TB and mem0 LLM calls at OmniRoute.
2. `honey` compression engine → preview savings → set stacked pipeline.
3. `reasoning-bank` + `continual-harness` plugins, each with tests in the fork.
4. `observation_log` Omni Skill; merge the two existing observation logs into it.
5. `retrieval-planner` plugin over mem0 / Terrestrial Brain / code-review-graph; measure arms
   chosen and tokens injected per request on real traffic, then tune the budget share.
6. Harness installs (Honey + Task Observer + OmniRoute key) on phone, tablet, VM.

Each step is built on a feature branch of the relevant fork, CI green, and deployed to the VM
from that branch. It merges to the fork's main **only after the operator confirms it works in real
use** — passing tests alone is not the merge signal for new features.
