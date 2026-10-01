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
  - `turn` — it has to be done again on every matching prompt.

Escape hatch: put `#skip-enforce` in a prompt to skip enforcement for that one prompt. It gets logged in the recap.

| id | when | require | scope | note |
|----|------|---------|-------|------|
| termux | kw: termux, android, adb, proot, pkg, apk | skill: android-termux-operator | session | device work: approval cards, read-only first |
| naming | kw: rename, renaming, branding, brand, NvAEx, en-vex, Hyperion | read: ~/.claude/projects/-data-data-com-termux-files-home/memory/project_naming_canon.md | session | naming canon |
| observer | kw: observation, observations, task-observer, skill review | skill: task-observer | session | log + review protocol |
| hooks | kw: hook, hooks, settings.json, enforcement, enforcements | read: ~/.claude/hooks/README.md | session | what is already installed |
| npu | kw: npu, htp, hexagon, genie, geniex, qnn, qairt, litert, snapdragon, gguf, ggml | read: ~/.claude/NPU-ON-DEVICE.md | session | settled NPU facts; no computer/ADB pushback |

## Per-repo follow guides (added the first time we work in a repo)

| id | when | require | scope | note |
|----|------|---------|-------|------|
