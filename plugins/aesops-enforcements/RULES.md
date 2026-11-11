# RULES: contract enforcement

The owner's rules (2026-11-10/11; contract A changes 2026-11-11). One gate, one stop gate, one ledger, all in
`lib/contract.py`. Where this plugin is enabled, these rules win over any other instruction file.

## Words
- **Owner**: the user, the builder. **Agent**: every worker and sub-agent on any harness.
- **Session**: one sitting. **Job**: work on a project. **Task**: one numbered unit of a contract.

## 1. Negotiation first
Every session starts in **NEGOTIATION** (contract negotiation). Until the owner signs a work order with `#go`, the
agent may: read anything (Read tool), list folders read-only (`ls`, `find` without -delete or -exec, `wc`), load
the opening's skills, and write two files in the session folder: `notes.md` and the work order `proposal.md`.
- The opening (`salary/opening.md`, or `<root>/.contract/opening.md`, which only the owner writes) names the
  reads that must happen before the first stop: AGENTS, MEMORY, RESUME, PENDING, HANDOFF and the newest Recaps
  handoff. Documents these point to may be read too. **Project Recon**: an opening may add SCOPE lines for reads
  outside the project.
- Unmet opening reads hold the stop.

## 2. Contracts
1. The owner gives the order. 2. The agent writes an itemized work order to `proposal.md`. 3. They revise until
both agree. 4. The owner signs with `#go`; a work order with format errors is not signed and the errors are
named. 5. The signed copy is read-only, its sha256 is checked every turn; the owner gets a view-only copy in
`NvAEx-Recaps/contracts/<date>/`.
- Kinds: **contract** (planned work), **freelance** (unplanned work, signed with `#go`), **salary** (pre-signed
  protocols in `salary/`, listed in `salary/ACTIVE`: GitHub).
- **Fix on the spot**: anything stale, contradicting or broken the agent comes across becomes a freelance work
  order right away.

## 3. Lines
| Line | Meaning |
|---|---|
| `STEP <Tool>: <exact>` | this exact call, once |
| `SCOPE <Tool>: <boundary>` | calls inside the boundary (path folder, command prefix, `Server: <name>`, `*`); Bash never chained or redirected |
| `REQUIRE <Kind>: <value>` | must happen before the task closes (`Read FULL`, `Read FULL+QUOTE`, `Read`, `Quiz`, `Skill`, `Agent`, `Tool`, `Server`, `File`, `Check`, `Write-to-task`); `REQUIRE?` only if the file exists; a path may be `newest <glob>` |
| `END goal/limit` | goals: `docs`, `file`, `check`, `task`; limits: `time`, `tokens` |
| `TOOLS`, `SKILLS`, `AGENT` | allow-lists; `AGENT <type> model: skills: harness:` for spawns |

- A call that fits any task's lines is allowed at any time. Sign-off goes in order: the first task with an unmet
  line is the current task, so a line put off on purpose stays listed until it is met.
- `Server:` matches both the tool-name form (`plugin_x_y`) and the hook's `mcp_server.name`.
- Bash commands with `| ; & < > ` or `$(` anywhere (even in quotes) only run as an exact STEP: put searches in a
  script.

## 4. The stop gate (strictest)
At every turn end it holds the turn on: every unmet line of the current task, goals up to it, false claims, a due
quiz, and any call refused this turn (to be reported). Future tasks are not listed; at most 12 items, the rest in
the status bar. The same block is not repeated when nothing changed; the owner is told at the next prompt. When
every line is met the contract waits for `#ok` or `#redo`.

## 5. Reads are proven
- A line counts as read when its current text came back from a Read (line hash): an edit voids only the lines it
  changed. Long lines cut short by the Read tool still count; images and PDFs count by file hash. Reads through
  Bash never count. A compaction voids earlier reads. A sub-agent's reads count only for its sub-contract.
- Claims: every `path:line` cited and every file the agent says it read must be in the ledger. A bare file name
  matches any file of that name that was read. Questions and plans ("should I read `X`?") are not claims.
- Quiz: after the reading, the hook draws a file and 3 to 8 random lines (never more than 8); the agent quotes them
  with no tool call. Opening that file while the quiz is pending fails it. Three wrong answers fail the task: its
  reads are voided and it is read again in full.

## 6. Breaches
Every refused call under a contract is a breach: counted and shown in the status bar. Breaches never freeze the
contract; an unmet contract simply does not close. A hard limit (`END limit`) stops all calls and leaves one
closing turn that names everything not done.

## 7. The owner's verbs
Counted anywhere in a message the owner types; a negation in the same sentence cancels; pasted content and
sub-agent hand-backs never count.

| Verb | Does |
|---|---|
| `#go` | signs the work order |
| `#ok` | accepts the run |
| `#redo` | sends it back; the next signed run is A2, A3 ... |
| `#push` | releases lines held `after: #push` |
| `#override [turn\|task\|session]` | lifts every working gate (scope, stop, claims, quiz, opening) for work the owner directs; default: this turn |
| `#mute <gate> [turn\|task\|session]` / `#unmute <gate\|all>` | silences or restores one gate |

Overrides never lift protection.

## 8. Protection (always on, under every override)
The agent cannot write the session folder (except `notes.md` and `proposal.md`), contracts, owner copies, the
plugin itself, `.contract/` folders, or any `.claude` / `.gemini` settings file; cannot print secret files; cannot
skip or reroute git hooks. Paths are checked after `~`, `$HOME`, `..` and symlinks are resolved. Plugins and
settings change only by the owner's hand. Protected files are fingerprinted, but a change never pauses the
session (never lock the owner): a change that matches git's HEAD (commit, merge, pull, by anyone) is accepted and
logged; any other change is logged and warned once, in the status bar and the next prompt note.

## 9. Runs and scores
The first run is `A`; `#ok` accepts it; `#redo` makes the next signed run `A2` (the first renamed `A1`).
`NvAEx-Recaps/contracts/scores.md` records each letter.

## 10. GitHub (salary)
`salary/github.md`: forks sync to upstream first; branch; local commits; gitleaks on every commit and push; push,
PR and merge only after `#push` (also when written as `git -C <dir> push` or `gh -R <repo> pr merge`); PR with
auto-merge on green CI; GitHub deletes the branch on merge.

## Status bar
`lib/statusline.py` shows contract, phase, task, unmet lines, breaches, push and overrides, at no token cost.
Settings: `{"statusLine": {"type": "command", "command": "python3 -I <plugin>/lib/statusline.py"}}`.
