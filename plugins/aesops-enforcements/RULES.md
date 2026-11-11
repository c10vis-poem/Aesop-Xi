# RULES: contract enforcement

The owner's rules, written 2026-11-10/11. One gate, one stop gate, one ledger. Every rule below is enforced by
`lib/contract.py`; nothing is enforced anywhere else.

## Lexicon
- **Agent** = subcontractor: every worker, assistant and sub-agent, on any harness.
- **Owner** = contractor: the user, the Builder.
- **Session** = one sitting. Session start = job start.
- **Job** = work on a project. A job can take several sessions; a project has many jobs.
- **Project** = what lives in a repo or another file endpoint (`root:` in the contract).
- **Task** = one numbered unit of a contract.

## Rule 1: no work without a signed contract
An agent does no work at all (read beyond the opening, write, tool use, push, pull, commit, copy, clone, grep,
code, or anything else task related) without one of:
- a **contract** the owner signed with `#go`,
- a **freelance** (commission) contract the owner signed with `#go`,
- a **salary** task the owner approved once (a template in `salary/`, listed in `salary/ACTIVE`).

Until then the agent may only: use the Read tool, load the skills the opening names, and write two files,
the work order (`proposal.md`) and its notes (`notes.md`), in the session folder. After a contract's lines are met,
no calls at all until the owner's `#ok` or `#redo`.

## Rule 2: contracts
1. The owner gives the order: exact job scope and details.
2. The agent answers with an exact workflow and itemized work order, written to `proposal.md` in the format below.
3. The owner changes it; the agent rewrites it; this repeats until both agree.
4. The owner signs with `#go`. The hook checks the format first; a work order with any error is not signed and
   the errors are named.
5. The signed copy goes to `~/.claude/state/contract-<session>/contracts/<label>.md` (read-only, sha256 recorded)
   and the owner's view-only copy to `NvAEx-Recaps/contracts/<date>/<session8>-<label>.md`. The hash is checked
   every turn; a changed contract freezes the session.

Three kinds of work, one set of enforcements:

| Kind | Where the contract comes from | Signed by |
|---|---|---|
| Contract | negotiated for planned work | `#go` |
| Freelance (commission) | unplanned work the owner springs, or work the agent wants that no contract covers; negotiated on a strict request | `#go` |
| Salary | a pre-written template: protocols and repeated workflows (GitHub now; opening and wrap-up later) | approved once, listed in `salary/ACTIVE` |

## Rule 3: conditions and enforcements
- Every session starts in **OPENING**: the start hook names what the opening requires (`salary/opening.md`, or
  `<root>/.contract/opening.md`). The agent reads and writes notes only, then writes the planning work order.
- Every signed contract is enforced the same way, by four kinds of lines.

### The four line kinds
| Line | Meaning | Checked |
|---|---|---|
| `STEP <Tool>: <exact>` | this exact call, once (Bash command byte for byte; file tools by path; Skill by name; Agent by type; MCP tool by its JSON input or `*`) | as the call is made |
| `SCOPE <Tool>: <boundary>` | calls of that kind inside the boundary (file tools: under a folder; Bash: a command prefix, never chained or redirected; `Server: <name>`: that server's tools; `*`: any) | as the call is made; anything outside is blocked |
| `REQUIRE <Kind>: <value>` | must have happened before the task closes. Kinds: `Read FULL`, `Read FULL+QUOTE`, `Read`, `Skill`, `Agent`, `Tool`, `Server`, `File`, `Check`, `Write-to-task`. `REQUIRE?` = only if the file exists | at the turn end; missing items hold the turn and are named |
| `END goal <kind>: <value>` / `END limit <kind>: <value>` | goals: `docs` (N read in full), `file` (exists), `check` (command passes), `task` (reached). Limits: `time` (`40m`, `2h`, from signing), `tokens` (from the transcript, since signing). `share` of the session allowance is refused until a hook can measure it | goals at the turn end; limits at every call |

A line may carry `after: #push` or `after: <Tool>: <prefix>` (held until that has happened) and `when: fork`
(the hold applies to forks only).

### Tasks, tools, skills, agents
```
CONTRACT   type: contract   project: <name>   root: <path>
TOOLS   Read, Grep            (lines before the first TASK apply to every task)
TASK 1  <title>
  TOOLS   Read, Grep, mcp__claw__claw_scrape
  SKILLS  code-map
  SCOPE   Read: {root}/plugins/x/
  REQUIRE Skill: code-map
  REQUIRE Read FULL: {root}/plugins/x/README.md
TASK 2  <title>
  AGENT   builder   model: sonnet   skills: [verify-before-done]   harness: claude
  REQUIRE Agent: builder
  END     goal file: {root}/audit.md
  END     limit time: 40m
```
- Tasks run in order. A task closes when every REQUIRE is met and every STEP was used; then the next task's lines
  apply. Every task but the last needs at least one STEP or REQUIRE.
- `TOOLS` and `SKILLS` are allow-lists: anything not named is blocked.
- `AGENT` names the type, model, skills and harness a spawn must use. A `claude` harness spawns through the Agent
  tool; any other harness (agy, gemini, dsh) starts with its own exact Bash STEP.

### Sub-agents
- A spawn is allowed only by an `AGENT` line, and its prompt must carry its own `CONTRACT` block with the same line
  kinds plus `REQUIRE Write-to-task: <progress file>`.
- A sub-contract can never be wider than the parent task: every SCOPE inside a parent SCOPE, skills inside the
  AGENT line's skills.
- Write-to-task: the progress file (`## Plan`, `## Last action`, `## Findings`, `## Blocked`) is written before
  the first work call and updated after every work call; the sub-agent cannot stop with an unchecked Plan item
  that is not named under Blocked.
- A sub-agent's reads and calls count for its sub-contract only; its hand-back never signs or approves anything.

### Reads are proven, not claimed
- A read counts only for lines whose text, as the Read tool returned it, matches the file on disk (sha256 per line),
  against the file's current hash. A later change to the file voids the read.
- `Read FULL` = every line covered since the contract was signed. Reads through Bash never count.
- A compaction voids every read made before it.
- `Read FULL+QUOTE`: after the full read, the stop gate names three random lines; the agent quotes them with no
  tool call; a miss fails the read.
- `Quiz: N`: after every file of the task is read in full, the stop gate draws a random file (unknown in advance)
  and names three random lines; N must pass. A miss is a strike; three strikes fail the task: every read of it is
  voided, its passes are wiped, and it must be read in full again before the quiz restarts.
- Claims: every `path:line` the agent cites and every file it says it read must be covered in the ledger, or the
  turn is held.

### Breaches, limits, freezing
- Every blocked call under a contract is a breach. The third breach freezes the contract until `#ok` or `#redo`.
- When a hard limit is reached, every further call is blocked and the agent gets one closing turn; its report must
  name everything not done. The contract closes as unfinished.
- If a held turn ends with nothing done since the last hold, the turn ends and the owner is told at the next prompt.

### Runs
- The first run of a task is `A`. `#ok` accepts it; the next signed contract is `B`.
- `#redo` sends it back: the next signed contract is `A2`, and the first is renamed `A1` (same hash).
- `NvAEx-Recaps/contracts/scores.md` records each letter, e.g. "A: accepted at A3 after 3 run(s)".

## The owner's verbs
Counted anywhere in a message the owner types, with anything after them. A negation in the same sentence cancels
(`don't`, `do not`, `never`, `not`, `no`). Pasted content never counts. Sub-agent hand-backs never count.

| Verb | Forms | Does |
|---|---|---|
| `#go` | `#go` | signs the work order |
| `#ok` | `#ok` | accepts the run |
| `#redo` | `#redo` | sends the run back |
| `#push` | `#push` | releases the lines held `after: #push` |

## The GitHub protocol (salary)
`salary/github.md`: forks sync to upstream main first (`gh repo sync`); branch; local commits; every commit and
push is scanned by gitleaks (`git-hooks/scan`); push, PR and merge only after the owner's `#push`; PR with
auto-merge on green CI; GitHub deletes the branch on merge.

## Protection (always on, every phase)
The agent cannot write the session folder (except `proposal.md` and `notes.md`), any contract or owner copy, the
plugin itself, or any `.claude` / `.gemini` settings file; cannot print secret files; cannot skip or reroute git
hooks.

## Where it plugs in
Same points as before: the plugin name `aesops-enforcements`, the marketplace `aesop-xi`, project and user
`settings.json`, and `~/.claude/state/`. Other harnesses (Gemini CLI: SessionStart, BeforeAgent, BeforeTool,
AfterTool, AfterAgent in `.gemini/settings.json`) get adapters that call the same `contract hook <event>`.
