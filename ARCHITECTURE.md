# Æsop-Xi Architecture

**Agentic Executions Split Operations Protocol**

Æsop-Xi is a protocol for a split, multi-node agent stack with one shared, auditable
memory. It is defined in terms of **roles**, **memory types**, and **capability tiers**
— never specific hardware. A user's actual machines are declared in a *profile*
(`profiles/`), which maps hardware onto tiers. This separation is what makes Æsop-Xi
publishable: the protocol is device-agnostic; only the profile is personal.

---

## 1. Design principles

1. **Roles are fixed; runtimes are swappable.** An agent is defined by its *role*, not
   the box it runs on. The gateway binds role → runtime per profile and per context.
2. **Markdown is canonical; indexes are derived.** The wiki (markdown) is the single
   source of truth — git-versioned, diffable, human-reviewable. Vector stores (recall,
   strategic) are rebuildable indexes over it and never a competing truth.
3. **Audit lives on the write boundary, not on every thought.** Reads and reasoning run
   free. Only side-effecting actions pass the gate.
4. **Graceful tier degradation.** A missing tier's roles fall back to the next tier in
   the chain. Phone + laptop + cloud must run the whole system; a home node just makes
   it better.
5. **The auditor is independent by construction.** It never shares context or state with
   the executor it judges — so it cannot be co-opted by the same failure, nor gamed.

---

## 2. Node tiers (reference)

Tiers are **capability classes**, not devices. A node may span tiers; a tier may be
absent (degrade) or backed by multiple boxes.

| Tier | Class | Default role tenancy | Must provide |
| --- | --- | --- | --- |
| **T1 — Edge / Mobile** | always-on-person, sensors, constrained, intermittent | query/tool-exec + client UI (Omni-Claw) | local small model *or* passthrough; camera/mic; offline action queue |
| **T2 — Personal / Workstation** | laptop/desktop, CPU-class (± modest GPU), present when working | interactive executive, dev tools, heavier query | user terminal/browser; more compute |
| **T3 — Home Node / Hub** | always-on home box | **memory** (wiki + recall + strategic), gateway/router, librarian, local executive, TTS/audio | persistent storage; always reachable over LAN/Tailscale |
| **T4 — Cloud** | elastic + off-site | heavy training (ReasoningBank induction / MaTTS), out-of-band auditor, canonical backup | on-demand compute; durable storage; passthrough models |

**Composition rules**
- A role declares a **preferred tier** + an ordered **fallback chain**.
- If a tier is absent, its roles collapse onto the next reachable tier in the chain.
- Two boxes may back one tier (e.g. a compute box + a desktop box both serving T3).
- One box may serve several tiers (e.g. a laptop serving T2 and standing in for T3).
- The number and layout of tiers is a **profile** decision; the four above are a
  reference template, not a constraint.

---

## 3. Agent roles and binding

| Role | Responsibility | Preferred → fallback |
| --- | --- | --- |
| **Query / tool-exec** | Turns your input into meta-prompts; calls tools; reads memory; runs a self-recursive plan→act→observe loop. Reliable at narrow, structured work. | T1 → T2 |
| **Executive** | Heavy reasoning with direct file/memory access. | T3 → T4 → T2 |
| **Librarian / switchboard** | Intercepts prompts and outputs; selects which memory to surface; logs sessions; distills learnings and **commits them back** to the wiki (the flywheel). | T3 → T4 |
| **Auditor (red)** | Independent gate on side-effecting actions; judges trajectories pass/fail; that verdict is ReasoningBank's training signal. | T4 (out-of-band) |

Binding is a profile concern. Example: away (only T1 reachable) → query+exec collapse
onto the phone; executive heavy-lift defers to T4; auditor defers/queues. Home (T1–T4
reachable) → each role lands on its preferred tier.

---

## 4. Memory architecture

Four **distinct** memory types — the separation is the point. (Added 2026-08-31: the
original spec only named three; auditing the dev-process side of this project turned
up an unstated fourth — session-scoped state was already implicitly assumed by the
T3 docker-compose's Redis container, but never named as its own memory type until now.)

| Memory | Kind | Content | Backend |
| --- | --- | --- | --- |
| **Declarative** | authored | facts, docs, "what things are" — **source of truth** | wiki markdown (OpenWiki generates; Obsidian / Graphify render) |
| **Recall** | emergent | raw thoughts, sources, cross-domain search | OB1 / Open Brain (Postgres + vector, MCP-exposed) |
| **Strategic** | distilled | reasoning patterns from successes **and** failures | ReasoningBank (`{query, think, action, status}` → distilled item + embedding) |
| **Working / Ephemeral** | transient | in-flight session/task state — current conversation buffer, in-progress tool-call context — **deliberately not persisted** | Redis (already provisioned in `deploy/jetson/docker-compose.yml`, never previously named as a memory type) |

**Shared tooling & interchange**
- **notebooklm-py** is a shared *source/synthesis tool* any memory may call (grounded
  Q&A, summaries, podcast/quiz artifacts). Auth is a Google session, not a Gemini API key.
- **Markdown** is the interchange format across the three persistent types; embeddings
  are derived. Working/Ephemeral is intentionally outside this — it never gets
  serialized to markdown or embedded, that's what makes it ephemeral.
- Recall and Strategic are both vector stores and **may share one backend** (e.g. OB1's
  Postgres with a `thoughts` namespace and a `strategies` namespace).
- Working/Ephemeral is the boundary that keeps the other three clean: nothing moves
  from Redis into Declarative/Recall/Strategic except through an explicit write (the
  audit gate in §5), so mid-task scratch state never silently becomes "memory."

### The flywheel (closed loop)

```
OpenWiki writes repo docs → wiki (markdown, canonical)
        ↑                          ↓
   audited write-back        OB1 / ReasoningBank index it
        ↑                          ↓
   Librarian distills ← agents use it (query · executive)
```

Learnings re-enter the same wiki that serves Obsidian, Graphify, OpenWiki, and the
vector indexes. The loop **amplifies whatever it circulates**, which is why the write
path is gated (§5).

---

## 5. The audit gate

Audit is a **policy on the write boundary**, not a per-inference check. The
files-executor performs the write; the auditor approves it. They are the *write* and
*approve* halves of one gate and never talk directly.

| Tier | Action | Audit behavior (edge / away) |
| --- | --- | --- |
| **0** | read, reason, info tool-call | none — free recursive loop |
| **1** | reversible local write | self-audit pass (same model, adversarial prompt); logged |
| **2** | irreversible / outbound (email, calendar, spend, **memory commit**) | independent audit required → cloud auditor if reachable; else **queue for audit-on-reconnect** or hard-confirm |

Flywheel write-backs into the wiki are **Tier 2** by definition, so memory is never
mutated by an unaudited inference — it waits. On the edge this gives a self-recursive,
independently tool-calling agent for Tier 0–1, with teeth kept only where a mistake costs.

---

## 6. ReasoningBank integration (the auditor's memory)

ReasoningBank (Google Cloud AI; arxiv 2509.25140) distills reusable strategies from
**both** successful and failed trajectories, retrieves them before acting, and feeds new
learnings back. Its mechanism maps 1:1 onto Æsop-Xi's decoupled executor/auditor:

| Æsop-Xi | ReasoningBank |
| --- | --- |
| Files-executor (auditor-blind) | emits `{query, think_list, action_list}` — never calls a judge |
| **Auditor** | the `--judge autoeval` reward source; pass/flag → `reward` 1/0 |
| Shared protocol | the trajectory record + memory-item schema; executor and auditor meet only here |
| Self-improving loop | labeled trajectory → `induce_memory` distills strategy → retrieved before next act |

- **Retrieval reads free (Tier 0)** — even offline, the edge model is smarter from past
  lessons.
- **Distillation writes through the gate (Tier 2)** — a new strategy is minted only after
  a verdict, so the strategy bank can't be poisoned by an unaudited run.
- **Privacy note:** the reference impl embeds with Google `gemini-embedding-001` (cloud).
  The on-device / max-privacy tier **must** swap this for a local embedder.

---

## 7. Profiles & privacy tiers

Two axes select bindings: **reachability** (which tiers are up) × **privacy tier**.

| Privacy tier | Executive binds to | Notes |
| --- | --- | --- |
| Convenience | browser session / cloud model | hub hosts only librarian + gateway + memory |
| Hybrid | local terminal + cloud model | + routing/caching |
| Max privacy (closed loop) | on-device local model + local embedder | nothing leaves the perimeter |
| Walled training | enterprise cloud (e.g. GCP) | recursive JSONL / ReasoningBank induction inside a security boundary |

See `profiles/` for concrete hardware mappings.

---

## 8. Component mapping (reference implementations)

| Module | Fills | Repo |
| --- | --- | --- |
| Declarative memory (generation) | wiki docs from repos | OpenWiki |
| Declarative memory (render/graph) | vault + graph views | obsidian-skills (kepano), Graphify |
| Recall memory | vector + MCP memory | OB1 / Open Brain |
| Strategic memory | strategy distillation | reasoning-bank |
| Source/synthesis tool | grounded Q&A, artifacts | notebooklm-py |
| Gateway / router / "there-but-not-there" | role→runtime binding, passthrough, caching, audit logging | OmniRoute |
| On-device client (Omni-Claw) | UI + sensors + cloud connectors | Novus-Agenti |
| Skill/agent library | cs-* agents, red-team/adversarial-reviewer skills | claude-skills |

---

## 9. Open questions

- Auditor deployment: co-deployed-but-isolated vs strictly out-of-band. Leaning
  out-of-band (cloud GLM 5.2), which also satisfies independence for free.
- Whether Recall and Strategic share one vector backend or stay separate stores.
- Local embedder choice for the max-privacy tier.
- Memory sits on T3 (home node) by default in §2's tier table, but T3 doesn't exist
  yet (no Jetson procured — see `PENDING.md`). Until it does, memory has to
  actually work from T1 (phone) + T4 (cloud) alone; the doc's fallback language
  covers this but the emphasis reads as T3-first, which doesn't match current reality.

## 10. OmniRoute / OB1 / ReasoningBank routing — under active exploration, unresolved

Verified 2026-08-31 by reading OmniRoute's actual source tree (it isn't cloned on
this device — checked via `gh api` against the real repo), not assumed:

- OmniRoute's vector store (`src/lib/memory/vectorStore.ts`) is real and
  sophisticated: hybrid search combining `sqlite-vec` + SQLite FTS5 via Reciprocal
  Rank Fusion, int8 quantization, self-healing upsert — **but it's SQLite end to
  end, not Postgres/pgvector.** Functionally it can fill Recall memory's job; it is
  not literally the Postgres backend §4 currently names.
- "Stale information flagging" exists only narrowly: hardcoded tests
  (`free-note-freshness.test.ts`) checking that AI-provider free-tier pricing/quota
  text matches current reality. Not a general content-staleness detector for a
  memory/knowledge base. Other "stale" hits in the repo are connection/credential
  expiration handling (TLS clients, API-key encryption, session TTLs) — a different
  kind of staleness than "is this fact still true."
- **Zero references to ReasoningBank anywhere in OmniRoute's source.** Any
  adherence to ReasoningBank's trajectory schema (§6) would be net-new integration
  work, not something to wire up from existing code.

**Hypothesis being explored (not decided):** OmniRoute's SQLite hybrid store may be
better understood as **episodic memory** — day-to-day, moment-to-moment recall —
which may be a distinct 5th memory type rather than a subset of Recall as currently
modeled in §4. Where OB1 actually sits relative to OmniRoute and ReasoningBank is
unresolved: candidate framing is OB1 as a routing/audit-logging/agent-definition
layer that itself implements ReasoningBank's protocol, forming a
user ↔ OB1 ↔ OmniRoute stack, rather than OB1 being just a Postgres+vector store
sitting parallel to OmniRoute. Separately: Postgres+vector may turn out to matter
mainly as a **post-training evaluation store** (validating outputs after a
ReasoningBank induce_memory / MaTTS training pass) rather than as continuous
production recall — also unresolved. None of this is settled; resolve before
building against it, don't treat this section as spec.
