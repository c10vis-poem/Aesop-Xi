# Routing layer: what we learned (living document)

Grows until the routing layer is pinned down. Entries are dated and sourced; earlier entries are never rewritten.
Owner's order (2026-11-13 16:01): "a continuous growing document until we get this routing layer pinned down."

## 2026-11-13, session 88d5742c

### The plan it serves
- RULES.md rule 4.7: "Tools and skills are not loaded on every prompt. The indexes and the hooks bring in what the task
  needs, and nothing else." Every skill, tool and plugin sits "no more than two folders below those indexes"
  (manifest.jsonl, MAP.md, skills.json, chunk.jsonl).
- So once routing runs, Claude Code's per-prompt skill listing is dead weight: hide it, route from the indexes.

### Jev (TypeSafe System One), from the vendor docs on the phone
Source: `Documents/_File-Driven-Agent-Operating-Environment/_Jev/` (introduction, quickstart, how-to-build, patterns,
confidence, cookbooks).
- Jev answers typed questions about a state: Choice (pick one, with probabilities and confidence), Score (a rubric
  level), Noul (probability a statement is true). All questions in one request run in parallel.
- Judgments from Jev, decisions in code. Ask narrow, atomic questions; combine answers in code with thresholds.
- Noul thresholds to start: above 0.7 yes, below 0.3 no, between = unsettled.
- Choice confidence = (pmax - 1/n) / (1 - 1/n). Thresholds scale with the risk of the action.
- Speculative fan-out: put every question the code might need in one request; code reads only what applies.

### Patterns that map onto routing
- Skill suggestion (cookbook): request 1 = Choice over every skill (one-line descriptions) + three gate Nouls
  (acts on the user's system; would follow a documented procedure; prose suffices, inverted), gate mean 0.30;
  request 2 = Choice over the top 3 with 700 characters of each SKILL.md + one "fits" Noul each, threshold 0.30.
  Measured on 452 requests: wrong loads 15.7% -> 7.9%, needless loads 14.0% -> 5.2%.
- Function calling: one Choice picks the tool, one Choice per closed-set argument, a `stated` Noul makes an argument
  optional; confidence = the weakest judgment. This is the shape for one-word commands.
- Intent routing: classify intent and complexity in one request; low confidence goes to a human.
- Hierarchical classification: walk a tree with one Choice per level, beam search K=3, path score = geometric mean of
  the edge probabilities. This is how Jev can walk MAP.md / folder trees instead of loading them.
- Classification using confidence: report the leaf when confidence >= 0.9, else the parent level.
- Simple memory: after each answer, a Noul gate "does this state a lasting fact?" (save at >= 0.5); saved facts go
  into later requests' state. Only the request counts, never Jev's own answer.
- Autoresearch (CatBoost): an LLM proposes questions, Jev answers every row, answers become numeric columns, a model
  trains on labels and its worst misses drive the next round. Our labels exist: past contracts and the owner's
  #ok / #redo.

### The Claude mod shape (jev-skill-suggestion, read in full)
- `export const register: Register = (on, options) => {...}`; events `prompt.attachment` (answer the skill listing
  with `{text: null}` to withhold it), `prompt.submit` (attach one block: `next({...e, context: [...]})`),
  `skill.prompt`, `session.end`, `session.compact`.
- Runtime: `$.http.fetch`, `$.ui.log`, `$.ui.status`, `$.fs`, `$.env.get`, `$.command.list()`, `$.model.classify`.
- Fail-open, 800 ms budget: the mod never blocks a prompt.
- Options from plugin.json userConfig; the TypeSafe key sits in user settings
  `pluginConfigs."jev-skill-suggestion@skills-dir".options.typesafeApiKey` (no env-var option in the module).
- Candidates come from `$.command.list()`; one function, `catalog()` in policy.ts, picks them. Switching it to read
  our skills.json / manifest.jsonl is how the mod becomes the routing layer's loader.

### Installed (contract A task 0)
- `~/repos/NovAExopia-main/.claude/skills/jev-skill-suggestion/` (6 files, 2,122 lines), copied from the vendor
  folder after `npx claude-code-templates --mod ...` failed ("claude-code-templates: not found", exit 127);
  `cmp` against the sources: identical. Defaults: inject content, listing hidden. Key set by the owner 16:29.
- Live check: pending the restart.

### Next for the routing layer
- Our deck: the memory.* tools and greedy-crane commands as one-word commands (function-calling shape).
- A memory gate mod (simple-memory shape) writing through dumbass-memory.
- Owner's "two-sided blade": Jev picks and judges, a small fast model on the NPU executes.
