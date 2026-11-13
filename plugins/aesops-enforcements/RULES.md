# RULES: contract enforcement

The owner's rules (2026-11-10/11; contract A changes 2026-11-11; holes closed 2026-11-12). One gate, one stop gate, one ledger, all in
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
  handoff, and every document (`.md`, `.txt`) those files point to that exists on this device: each is read in full
  before the first stop. **Project Recon**: an opening may add SCOPE lines for reads outside the project.
- Unmet opening reads hold the stop, each named. The opening happens once per session: once met it never re-opens,
  whatever another session changes.

## 2. Contracts
1. The owner gives the order. 2. The agent writes an itemized work order to `proposal.md`. 3. They revise until
both agree. 4. The owner signs with `#go`: his go always signs (owner, 2026-11-12: "If I say Go, that means go");
format errors are named for the agent to fix, and a line that cannot match is ignored; a STEP that protection would
refuse is dropped at signing and named, never left to deadlock. 5. The signed copy is read-only, its sha256 is
checked every turn; the owner gets a view-only copy in `NvAEx-Recaps/contracts/<date>/`.
- **Only the owner marks anything done.** When every line is met the agent is told once; the contract stays ACTIVE
  and nothing is locked until the owner's `#ok` (or `#redo`).
- **No code is pushed that was not tested in a live session** (owner, 2026-11-12): tests first, then the change run
  live in a session (a real stop, prompt, tool call), then `#push`. A merge (`gh pr merge`, `--auto` too) is
  refused until this session holds a test run after its last Write or Edit, and the newest such run passed.
- Kinds: **contract** (planned work), **freelance** (unplanned work, signed with `#go`), **salary** (pre-signed
  protocols in `salary/`, listed in `salary/ACTIVE`: GitHub).
- **Fix on the spot**: anything stale, contradicting or broken the agent comes across becomes a freelance work
  order right away.
- **Nothing skipped**: a task never closes while anything in it was skipped, put off or left out. Every item is
  done, or struck by the owner by name. The stop holds on a deferral in the agent's message ("later", "next
  session", "follow-up", "for now", "parked", "put off", "skipped", "out of scope", "TODO"), and Jev judges whether
  the message skips or puts off work (section 4). A line must be met by the work itself, never by a file about it.
- **The owner decides what a contract covers.** Only the owner adds `END` lines (time, token or goal limits).

## 3. Lines
| Line | Meaning |
|---|---|
| `STEP <Tool>: <exact>` | this exact call, once |
| `SCOPE <Tool>: <boundary>` | calls inside the boundary: a path folder for Read, Write, Edit, Glob, Grep; for Bash a command prefix (the command itself, or the prefix followed by a space: a folder path in a Bash scope never matches a file inside it); `Server: <name>`; `*`. Bash never chained or redirected |
| `REQUIRE <Kind>: <value>` | must happen before the task closes (`Read FULL`, `Read FULL+QUOTE`, `Read`, `Quiz`, `Skill`, `Agent`, `Tool`, `Server`, `File`, `Check`, `Write-to-task`); `REQUIRE?` only if the file exists; a path may be `newest <glob>`. A `Check` value is a shell command, run from the contract root with a 15 s limit: met when it exits 0. A sentence there never passes |
| `END goal/limit` | goals: `docs`, `file`, `check`, `task`; limits: `time`, `tokens`. Only the owner adds END lines |
| `TOOLS`, `SKILLS`, `AGENT` | allow-lists; `AGENT <type> model: skills: harness:` for spawns |

- A call that fits any task's lines is allowed at any time. Sign-off goes in order: the first task with an unmet
  line is the current task, so a line put off on purpose stays listed until it is met.
- `Server:` matches both the tool-name form (`plugin_x_y`) and the hook's `mcp_server.name`.
- Bash commands that chain, pipe or redirect (`| ; & < >` outside quotes), or hold `$(` or a backtick outside single
  quotes, only run as an exact STEP. Inside quotes these are text (a commit message, a pattern).
- **No read is ever blocked in a contract** (owner, 2026-11-12 21:03): Read, Grep, Glob and read-only Bash (`ls`,
  `find` without -delete/-exec, `wc`, `grep`, `cat`, `head`, `tail`, `stat`, `diff`) run under any contract.
  Secret files stay unprintable.
- The owner's verbs also count when the phone keyboard turns `#` into `ß` (`ßredo`).

## 4. The stop gate (strictest)
At every turn end it holds the turn on: every unmet line of the current task, goals up to it, false claims, a due
quiz, any call refused this turn (to be reported), any deferral in the agent's message, and Jev's verdict. Future
tasks are not listed; at most 12 items, the rest in the status bar. The same unmet list is named once: it blocks
again only when the list changes (a tool call alone is not a change); the agent is told at the next prompt. When
every line is met the contract waits for `#ok` or `#redo`.
- **Jev audits the stop** (owner decision 2): one request to TypeSafe Jev with one typed question per check, over
  the agent's message and its tool log: a claim the log does not show, a file's content stated as fact with the file
  never read, work skipped or put off. Yes (0.70 or more): the stop is held, naming the check. Unsure (0.30 to
  0.70): the owner is warned on screen. A key is set but Jev gives no answer: the stop is held. No key: the owner is
  told once that the audit is off. Jev judges; the code decides. The tool log holds each call and, under it, a
  short redacted line of what it returned (failures marked `FAILED`), so a true claim is not judged unproven.

## 5. Reads are proven
- A line counts as read when its current text came back from a Read (line hash): an edit voids only the lines it
  changed. Long lines cut short by the Read tool still count; images and PDFs count by file hash. Reads through
  Bash never count. A compaction voids earlier reads. A sub-agent's reads count only for its sub-contract.
- Claims: every `path:line` cited and every file the agent says it read, in backticks or in plain words, must be
  in the ledger. A bare file name means the project's own file when one exists, else any read file of that name.
  "Tests pass" (or checks, or the selftest) needs a test run in the ledger. Questions and plans ("should I read
  `X`?") are not claims; "read-only" is not a read.
- Quiz: after the reading, the hook draws a file and 3 to 8 random lines (never more than 8); the agent quotes them
  with no tool call. Opening that file while the quiz is pending fails it, and so does a Grep or Glob over its
  folder (or with no path), or a command naming the file or its folder. Three wrong answers fail the task: its
  reads are voided and it is read again in full.
- A sub-agent's `## Last action` must change between its calls, not only the file's time.

## 6. Breaches
Every refused call under a contract is a breach: counted and shown in the status bar. Breaches never freeze the
contract; an unmet contract simply does not close. A hard limit (`END limit`) stops all calls and leaves one
closing turn that names everything not done.

## 7. The owner's verbs
Counted anywhere in a message the owner types; a negation in the same sentence cancels; pasted content and
sub-agent hand-backs never count. A paste reaches the hook as plain text, so a verb counts as pasted when the 16
characters before it, with it, match what the tools or the agent showed (refusals, tool results, the agent's
text; spaces and line breaks ignored). The owner is told; he types the verb on its own to use it.

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
skip or reroute git hooks. Paths are checked after `~`, `$HOME`, `..` and symlinks are resolved, after string pieces
are joined (`'.cla' + 'ude'`, `os.path.join` parts), and inside a script file a command runs. Reads are never
blocked (section 3): read-only Bash may look anywhere a Read may, the enforcement state included, so the quiz keeps
only line numbers and fingerprints in `state.json`, never the lines. Secret files are not printed by any reader (`cat`, `grep`, `sed`, `awk`, `diff`, `python` ...). Plugins and
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
The contract-state line goes into the agent's context only when it changes (and again after a compaction).
Settings: `{"statusLine": {"type": "command", "command": "python3 -I <plugin>/lib/statusline.py"}}`.
