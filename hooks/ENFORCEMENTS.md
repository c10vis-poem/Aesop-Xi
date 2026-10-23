# ENFORCEMENTS — what must be used, per task / repo / skill

Read by the `enforce-*` hooks on every prompt. Rows are written by the builder and Claude together, case by case.

Columns:
- **when**, either:
  - `kw: a, b, c` — any of these words in the prompt (case-insensitive, whole words)
  - `repo: <name>` — working inside `~/repos/<name>` or the vault (`repo: vault`)
- **require**, one of:
  - `skill: <name>` — that skill must be loaded with the Skill tool
  - `read: <path>` — that file must be read
  - `run: <command start>` — a Bash command starting with this must run
- **scope**:
  - `session` — doing it once per session satisfies it. A skill you preload with `/name` counts.
  - `turn` — it has to be done again on every matching prompt. A `/name` typed at the start of that prompt counts.
- **mode** (optional last column, after note): `always` (default, also when the column is absent) fires on any mention of the keyword. `command` fires only when the keyword sits within 6 words after an action verb (run, build, install, fix, test, load, benchmark, set up, ...; list in `classify.sh`) or the whole prompt is 6 words or fewer with no `?`. Use `command` for context-loading rows, `always` for safety rows. `repo:` rows ignore mode.
- A compaction re-arms every `session` row (`observe-event.sh` clears what was satisfied).

Operator corrections: prompts matching a line of `~/.claude/hooks/observe-corrections.txt` (one regex per line) queue a friction event, like gate blocks and tool failures. The Stop gate holds the turn until each one is logged as an observation or dismissed with `observe-dismiss <id> "<reason>"`.

Operator override (user-typed only): the operator puts `#skip-enforce` in a prompt to skip enforcement for that one prompt. It gets logged in the recap.

| id | when | require | scope | note | mode |
|----|------|---------|-------|------|------|
| termux | kw: termux, android, adb, proot, pkg, apk | skill: android-termux-operator | session | device work: approval cards, read-only first | command |
| naming | kw: rename, renaming, branding, brand, NvAEx, en-vex, Hyperion | read: ~/.claude/projects/-data-data-com-termux-files-home/memory/project_naming_canon.md | session | naming canon | always |
| observer | kw: observation, observations, task-observer, skill review | skill: task-observer | turn | log + review protocol | always |
| hooks | kw: hook, hooks, settings.json, enforcement, enforcements | read: ~/.claude/hooks/README.md | turn | what is already installed | always |
| npu | kw: npu, htp, hexagon, genie, geniex, qnn, qairt, litert, snapdragon, gguf, ggml | read: ~/.claude/NPU-ON-DEVICE.md | session | settled NPU facts; no computer/ADB pushback | command |
| wrapup | cmd: /wrapup (set by enforce-prompt.sh, not keywords) | read: ~/.claude/WRAP-UP.md | turn | session wrap-up protocol; unlocks git gate. Mentions of "wrap up" do NOT trigger it | always |
| inventory | kw: new hook, new script, new skill, new tool, write a hook, write a script, write a skill, build a tool, create a hook, create a script, create a skill, add a hook, add a script | read: ~/.claude/INVENTORY.md | session | check existing before building | command |
| vault | kw: vault, obsidian, wikilink, wikilinks | skill: obsidian-markdown | session | vault notes and edits | command |
| graphify | kw: graphify, graphify-out, knowledge graph | skill: graphify | session | operator's graphify trigger | command |
| voice | kw: voice, vv, tts, stt, whisper, moonshine, kokoro | skill: aesop-voice-pipeline | session | voice pipeline work | command |
| bench | kw: benchmark, benchmarks, bench.py | read: /storage/emulated/0/Documents/NovAExorpus/docs/NPU-BENCHMARKS.md | session | keep benchmark results consistent | command |

## Per-repo follow guides (added the first time we work in a repo)

| id | when | require | scope | note |
|----|------|---------|-------|------|
