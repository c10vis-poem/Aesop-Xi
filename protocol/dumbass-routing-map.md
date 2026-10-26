# D.U.M.B.A.S.S. routing layer, MCP and agent runtime map

**Status:** DRAFT v0.4 (2026-10-26), awaiting operator approval. Supersedes the OmniRoute-based
`orchestration-contract.md` v0.3 for the request loop; that file stays as history until this is approved.

**Sources:** vault `BOARD-INTAKE.md` (decisions 2026-10-23, item 6 is the architecture definition),
`CONTEXT.md`, `AGENTS.md` "Current stack", `docs/NPU-SERVE-USER-GUIDE.md`; this repo's
`protocol/classify.md`, `protocol/orchestration-contract.md` v0.3, `hooks/README.md`, `.claude/settings.json`;
the vault's `.mcp.json`; measurements in vault `Jev-Corpus-Triage/` (PR c10vis-poem/NovAExorpus#58).
Operator statements of 2026-10-26 in session: corpus upkeep is the wiki-admin layer; memory layers are
written in sequence each turn; episodic memory is `RESUME.md` plus its own SQLite; plugins are held until
the cross audit.

---

## 0. Rules this map follows

1. **Files as infrastructure; agents as packages; plugins as configurations; repos as marketplaces;
   memory, workflows and data extraction as skills, scripts and hooks** (BOARD-INTAKE item 6).
2. **Dropped, not routed through:** OmniRoute, mem0, Terrestrial Brain / OB1, OpenWiki, Qwen3-VL. Their useful
   ideas are kept (retrieval inside routing, context-scaled budget, success ledger); their servers are not.
3. **Judgments from Jev, decisions in code.** Jev answers typed questions; a truth table in a hook decides.
   A failed Jev call is an error routed to the fallback, never read as "no".
4. **Corpus upkeep is out of scope.** Ingesting, cleaning and indexing the vault is the wiki-admin agent
   package (NovusAExenti). This layer only reads the vault and writes each turn's memory.
5. **Plugins held:** no plugin is added, enabled or relied on until the cross audit (operator, 2026-10-26).
   Everything below works with hooks, scripts, skills and the one MCP server already in use.

---

## 1. Memory layers

| Layer | What it holds | Store | Read by | Written by |
|---|---|---|---|---|
| **Static** (semantic) | Vault knowledge: decisions, specs, references | vault markdown + `manifest.jsonl` + per-section Jev labels (`Jev-Corpus-Triage/runs/*/sections.jsonl`) | route hook (grep + manifest + labels, Jev re-rank) | wiki-admin (corpus); Stop hook (this turn's new decisions only) |
| **Structural** | Code: call graphs, dependencies, blast radius | code-review-graph per-repo SQLite (tree-sitter AST) | MCP `code-review-graph` | Stop hook (`code-review-graph update`) |
| **Navigational** | Concept graph over the vault | Graphify output | Graphify CLI / Obsidian | wiki-admin |
| **Episodic** | What agents did and decided, per session | `RESUME.md` (human-readable) + `episodic.sqlite` (one row per turn) | SessionStart hook; route hook | Stop hook |
| **Working** | This turn's context | the harness's context window | the model | the route hook's injection |

---

## 2. The turn loop (hooks in this repo, registered through `hooks/run-hook.sh`)

```
SessionStart
  session-start.sh      load AGENTS.md pointers + RESUME.md; print layer status (last turn id per layer)
  layer-status          refuse to start routing if the layers disagree on the last turn id (see §4)

UserPromptSubmit
  enforce-prompt.sh ─► classify.sh ─► CLASSIFY_URL = jev-route (loopback, §3)   [existing contract]
                        └ fallback: keyword rows in ENFORCEMENTS.md (2 s timeout, unchanged)
  route.sh  (new)       one Jev request per prompt → truth table → inject retrieved context

PreToolUse              existing guards unchanged (secret-guard, state-guard, settings-guard, build-doc-gate …)

Stop
  memory-write.sh (new) ordered writes with one turn id: static → structural → episodic (§4)
  stop-gate.sh          existing checks, plus: all layers carry this turn id
```

### 2.1 What the route hook asks Jev (one request, state = prompt + cwd + last RESUME entry)

| Question | Type | Feeds |
|---|---|---|
| `needs_static` | Noul: does the prompt depend on decisions or facts recorded in the vault? | retrieve static |
| `needs_structural` | Noul: does it ask about code in a repo? | call code-review-graph |
| `needs_episodic` | Noul: does it refer to earlier sessions or unfinished work? | retrieve episodic |
| `intent` | Choice: question, build/change, review, research, operate device | runtime row (§5) |
| `complexity` | Score: one-line answer … multi-step build | runtime row (§5) |
| `is_correction` | 3 Nouls: said wrong / said missed / said stop (measured: 14/14 caught, 0 false alarms) | observe queue |

Truth table (in `route.sh`, not in the model): a Noul above 0.7 retrieves that layer, below 0.3 skips it, between
retrieves it at half budget. Unsure `intent` (top option below 0.5) goes to a Sonnet subagent to classify;
measured on the corpus, this Jev-first cascade reached 91% against Sonnet alone at 94%, with Sonnet seeing 31% of
labels.

### 2.2 Retrieval and budget (kept from v0.3 operator decisions)
- Retrieval is part of routing; one prompt may pull every layer, none, or any mix.
- No fixed token cap: the budget is a share of the target model's context window (default 25%), split across
  the chosen layers by relevance, with a ceiling only so injected text never crowds out the prompt.
- Static retrieval: manifest + label filter first, then grep, then Jev ranks the candidate sections
  (one Noul per candidate: "is this section relevant to the prompt?").

---

## 3. MCP map

| Server | Status | Transport | Purpose |
|---|---|---|---|
| `code-review-graph` | **keep** (in use) | stdio, proot Debian venv | structural layer queries |
| `omniroute`, `mem0`, `terrestrial-brain` | **remove from the vault `.mcp.json`** (operator to confirm; `omniroute` is also listed twice) | http | dropped stack |
| `jev-route` | **new, not an MCP server**: loopback HTTP on `127.0.0.1` speaking the `classify.md` contract | HTTP | route hook backend; holds the TypeSafe key |
| `npu-serve` | existing, OpenAI-compatible, not MCP | `http://127.0.0.1:18181/v1` | on-device models (§5) |
| `dumbass-memory` | **optional later**: stdio server exposing `search_static`, `search_episodic`, `layer_status` | stdio | lets other harnesses read the layers; not needed for Claude Code, which reads the files directly |

Only `jev-route` holds the TypeSafe key (from the sops store, `nvaex-secret get TYPESAFE_API_KEY`). No other
component needs a provider key.

---

## 4. Write order and congruence (Stop hook `memory-write.sh`)

1. Take `turn_id = <session_id>:<turn number>`.
2. **Static:** if Jev marks the turn as recording a decision (`has_decision` > 0.7), append it to the vault
   decisions file with `turn_id`.
3. **Structural:** if the turn edited code, `code-review-graph update` on the touched repo; record `turn_id`
   in the graph's metadata row.
4. **Episodic:** one row in `episodic.sqlite` (`turn_id, ts, prompt_digest, files_touched, outcome`); the
   human summary goes to `RESUME.md` at wrap-up, citing the same ids.
5. **Check:** every layer's last `turn_id` equals this one. A mismatch blocks the stop and names the layer
   behind. Writes run in this fixed order, so a failure leaves a known point to resume from.

---

## 5. Agent runtime configuration

| Row (`intent` × `complexity`) | Runtime | Model | Where |
|---|---|---|---|
| typed judgment inside a hook | Jev | `jev-1.14.0` (pinned) | `jev-route` |
| device action, file move, triage | on-device executor | Qwen 3.5 0.8B | `npu-serve` |
| metaprompt compilation for a spoken prompt | on-device query model | Qwen 3.5 2B/4B (9B at home) | `npu-serve` |
| question, review, small change | Claude Code main loop | Sonnet 5.5 | phone / cloud |
| build, multi-step change | builder subagents | Opus 5.5 | phone / cloud |
| planning, audit, grill | orchestrator | Fable 5.1 (`.claude/agents/fable-orchestrator.md`, deliverable 1) | cloud |

Packaging (BOARD-INTAKE decision 1): agent packages in **NovusAExenti**, capabilities in **NovAExopia**,
these hooks, protocols and the route truth table in **Aesop-Xi**. Each repo is a marketplace that the harness
installs from, once the cross audit clears plugins.

---

## 6. Open for the operator

1. Remove `omniroute`, `mem0` and `terrestrial-brain` from the vault `.mcp.json` now, or after the cross audit?
2. `jev-route` as a loopback service on the phone (Termux) only, or also on the cloud side?
3. Where `episodic.sqlite` lives: per repo (`.agent/`), or one in the vault?
4. Keep `RESUME.md` rewritten each session (as now) with the SQLite as the per-turn ledger, or append per turn?
5. Approve this as the replacement for `orchestration-contract.md` v0.3.
