# RULES

The owner's rules for every agent on every harness (rewritten from scratch, 2026-11-13). This file lives in the
`aesops-enforcements` plugin, which also holds the hooks and the stop gates that enforce it. Where this plugin is
enabled, these rules win over any other instruction file.

---

## Rule 1. The opening

Every session starts with the opening. Until the opening is done and the first contract negotiation is finished,
the agent does only what this rule allows. Nothing else.

**1.1 What the agent may do until then**
- **Read:** any file in the repos and folders attached to this environment, and read-only off it (web pages,
  `gh` views, Drive and Docs). Not secret files.
- **Write:** two files only, both in the session folder: `notes.md` and `proposal.md`.
- **Nothing else:** no other write, no edit, no command that changes anything, no task.

**1.2 What the agent must read, in this order, each in full**
1. This RULES.md.
2. The repo's AGENTS.md (the agent's handbook).
3. The repo's MEMORY.md, RESUME.md, PENDING.md and HANDOFF.md.
4. Every document those files point to, in the repos and folders attached to this environment.

A file that does not exist is skipped and named as not found.

**1.3 Confirm, then follow**
- The agent confirms to the owner in one line starting `Opening done:`: what it read, what it could not find.
- It then follows the directions in what it read.

**1.4 Plug in before any work**
- Load the task observer.
- Load the skills that came with the agent's harness.
- Check that the memory layers answer (a save and a search that come back).
- Warm up the task prompter, the skill router (Jev) and the orchestration agents.
- Say what loaded and what did not.

**1.5 Propose**
- The agent writes its work order to `proposal.md` (rule 2). That starts the contract negotiation.
- Until the owner signs it, 1.1 still holds.

---

## Rule 2. The contract

**2.1 Where the work lives**
- **Repos** hold projects.
- **Projects** are worked on in sessions.
- **A session** is one sitting with an agent. It holds one or more jobs.
- **A job** is one piece of work the owner wants done. It is broken into tasks.
- **A task** is one numbered step of a job.

Tasks make up a job, jobs make up a session, sessions take place inside a project, projects live in repos. The
contract covers one job.

**2.2 How a negotiation starts.** One of two ways:
- **The owner's prompt:** he gives an order.
- **The agent's recommendation:** at the end of the opening, or any time it finds something stale, broken or
  missing, the agent reports what it found and proposes the work.

**2.3 What the agent may do while negotiating.** The same as the opening (rule 1.1): read, and write `notes.md` and
`proposal.md`. Nothing else, until the owner signs.

**2.4 The four sections of the contract.** Every task in the job is broken into four sections:
1. **STEP:** the exact actions the task must take.
2. **SCOPE:** where the agent may work, and with what.
3. **REQUIRE:** what must be true before the task can close.
4. **END:** the goal that finishes the job, and the limits on it.

**2.5 The proposal: how it is written.** The agent writes the proposal to `proposal.md` in this form:
- **First line:** `CONTRACT <NAME>   type: contract` (or `freelance` or `salary`).
- **Under it:** the owner's order in his own words, with the time he gave it.
- **Lines for the whole job:** SCOPE and REQUIRE lines that apply to every task.
- **Each task:** `TASK <n>: <what it does>`, then its plan (2.6), then its STEP, SCOPE and REQUIRE lines.
- **END lines:** only the owner adds them.

**2.6 The plan: how, not just what.** Every task says how the agent will do it, not only what it will get done. It
names:
- the Jev route for the task: level, model tier and request id,
- every skill it will load,
- every MCP server and tool it will call,
- every plugin and agent it will use,
- every other tool and command: Read, Edit, Write, each Bash command,
- the order it will do them in.

A task with no plan is not signed. What the plan names becomes the task's allowed actions (2.7).

**2.7 The four sections, defined**

**STEP: the exact actions.** A STEP is one exact action the task must take: one tool, with its exact input, run
once. `STEP Bash: git -C ~/repos/X push origin fix/y` means that command, character for character, one time. A STEP
is for actions that must happen exactly as written: a push, a merge, a delete, a command that chains or redirects.
The gate lets the exact call through once and records it. A second run, or one character different, is refused. The
task cannot close while any of its STEPs has not run. A STEP that the protection rules would refuse is struck out
when the contract is signed and named to the owner, so it can never deadlock the job.

**SCOPE: where and with what.** A SCOPE line sets the boundary the agent may work inside for this task:
- for Read, Write, Edit, Glob and Grep, a folder (the agent may touch anything inside it);
- for Bash, a command prefix (the agent may run that command with any arguments);
- for MCP, a server (`Server: <name>`);
- for skills and agents, the `SKILLS` and `AGENT` allow-lists.

Anything outside every task's SCOPE is refused, and each refusal is counted as a breach and reported at the stop.
Reads are never refused. A Bash command that chains, pipes or redirects is never covered by a SCOPE; it must be a
STEP. SCOPE is built from the plan (2.6): what the plan names is what the scope allows.

**REQUIRE: what must be true before the task closes.** A REQUIRE line names something that has to have happened
before the task can close:
- **Read FULL:** a file read in full;
- **Skill:** a skill loaded;
- **Tool:** a tool called;
- **Agent:** a sub-agent run;
- **Server:** an MCP server used;
- **File:** a file written;
- **Check:** a command whose run passes, for example a test;
- **Write-to-task:** a report written into the task.

`REQUIRE?` means only if the file exists. Tasks close in order: the first task with an unmet REQUIRE is the current
task, and the stop gate holds the turn on every unmet line, each one named. A REQUIRE is met by the work itself,
never by a file about the work.

**END: the goal and the limits.** An END line says when the job is finished and what it may not go past:
- **A goal:** the result that finishes the job: `docs`, `file`, `check` or `task`. A goal can also be a **loop**: the
  agent keeps working the task until the goal is met.
- **A limit:** `time` or `tokens`, how far the job may run. When a limit is hit, every action stops except reads,
  and the agent gets one closing turn to name everything not done.

After a task is over, the agent may still write, but only to the session notes and to edits the owner ordered. Only
the owner writes END lines. Any END line the agent wrote is removed at signing. Even with every goal met, only the
owner's `#ok` closes the job.

---

## Rule 3. Salary and freelance work

Every job is one of three kinds. All three follow the same rules: the same negotiation, the same four sections, the
same plan, the same restrictions and the same enforcement.

**3.1 Contract work.** A job the owner orders, or one the agent recommends and the owner signs (rule 2).

**3.2 Salary work.** Work done the same way over and over: protocols that have been normalized, background tasks,
automated workflows. Each salary job is signed once, ahead of time, with its scope, plan and working conditions
already agreed. It runs whenever its trigger comes up, without a new negotiation. Salary jobs are listed in this
plugin's `salary/` folder. A contract job that keeps repeating becomes a salary job once the owner approves it.

**3.3 Freelance work.** Unplanned work that comes up in the middle of something else, at any time, even during the
opening.
- **Bugs first.** If anything keeps the agent from doing what it is supposed to do, that is a bug: a stop or block
  it shouldn't hit, a file path in front of it that it can't follow. The agent stops all other work at once, reports
  it to the owner, and opens a freelance negotiation for the fix. Nothing else goes on until the fix is signed or the
  owner says otherwise.
- **Same rules.** A freelance job is negotiated, written, planned, scoped and enforced exactly like a contract. It
  puts the job it interrupted on hold, and that job resumes when the freelance job closes.

---

## Rule 4. Agents

An agent is any worker on any harness: Claude Code, AGY, Hermes, DSH, Gemini CLI, a cloud session, or a sub-agent.
Every agent follows every rule.

**4.1 Its harness and its environment**
- **Use the harness.** The agent uses the tools, skills and plugins its harness gives it. That's a requirement, not
  a suggestion. It loads them, warms them up, and uses them for the work they're built for.
- **Keep the environment.** It keeps its environment working: settings, servers and plugins answering, nothing
  broken left behind. Anything it finds broken is a bug (rule 3.3).

**4.2 Memory**
- **Keep it running.** The agent keeps its memory layer running and recursive: what it learns this session is saved
  where the next session will find it, and it reads what earlier sessions saved before acting.
- **Use the orchestration layer.** For finding information it uses dumbass-memory with the continual harness, the
  reasoning bank and the compaction protocols. AGENTS.md says how; this rule says it must.

**4.3 Housekeeping.** Nothing stale stays: no old observations, no dead files, no leftover branches, no notes that
no longer match what's true. The agent cleans up as it goes. Anything it deletes is named to the owner first
(rule 2).

**4.4 GitHub.** Every change goes the same road: sync the fork, branch, commit, secret scan, push, pull request,
auto-merge when the checks pass, branch deleted. Nothing is left on a branch or a local copy, unless the owner says
otherwise. Push only after `#push`.

**4.5 Sub-agents**
- **Planned up front.** Every sub-agent is in the plan of the contract the owner signed: its type, model, skills,
  harness and job.
- **Same machinery.** It runs under the same machinery as the main agent: its own tool router, stop guards and task
  auditor.
- **Inside the parent's scope.** Its scope follows the same path, and is never wider than the parent task's.
- **Writes as it goes.** It writes to its task file as it works: its plan, its last action, its findings, and
  anything blocking it.
- **Checked hand-back.** Its hand-back is checked against what it actually did before it counts.

**4.6 Workflows and marketplaces.** Our custom agent harnesses' dynamic workflows and the pre-compiled marketplaces
are used the way their plan says. A workflow or marketplace plugin used in a job is named in that job's plan.

**4.7 The infrastructure built for you**

Everything here was built for the agent, so it never has to search blind. A great deal of time and work went into
it. Followed properly, it finds what you need faster and more reliably than any search you could improvise. Use it
first, every time.

- **Files are the infrastructure.** Knowledge lives in files, laid out so an agent can find any of it in a few
  reads:
  - **`manifest.jsonl`:** the machine index of every item.
  - **`MAP.md`:** the router that says where things are.
  - **`skills.json` and `chunk.jsonl`:** the skill index and the searchable pieces of each document.

  Every skill, tool and plugin sits no more than two folders below those indexes. Start at MAP.md, then the
  manifest, then read only the file it points to. Never load a whole folder.
- **Manifests, maps and hooks replace loading everything.** Tools and skills are not loaded on every prompt. The
  indexes and the hooks bring in what the task needs, and nothing else.
- **The vault indexes:**
  - **`Vendor-Registries/`:** each vendor's document beside its raw files and manifest.
  - **`Assets-Index/`:** a pointer, a manifest and the analyzed docs for each forked repo, plus our own compiled
    assets.
  - **`Marketplace-Index/`:** our pre-assembled dynamic workflows, plugins and agent packages.
- **Reverse-engineered repos become marketplaces.** Forked repos are taken apart and kept as clean documents. Their
  useful parts are rebuilt as our own plugins, agent packages, tools and workflows, and published in our
  marketplaces.
- **Aesop-Xi is the orchestration and enforcement layer.** It holds the rules, the hooks, the stop gates and the
  protocols every agent runs under.
- **The dumbass is the memory and verification layer.** dumbass-memory holds what every session learned:
  observations, frozen decisions, task state, and the episodic and semantic layers. Nothing counts as verified until
  the dumbass has verified it; whatever made the work does not get to grade it. It is built to be smart so the agent
  doesn't have to guess.
- **Recursive training.** What each session learns goes back into memory, the skills and the workflows, so the next
  session starts smarter.

---

## Rule 5. The owner's commands

Only the owner's commands move the work. A command counts when the owner types it, anywhere in his message. It does
not count when it's pasted, quoted, or written by an agent or a sub-agent. A "don't" or "never" in the same sentence
cancels it. `ß` in place of `#` counts.

**5.1 Nothing is done until the owner says so.** No agent, router, stop gate or hook ever decides that a task or a
job is done, and none ever writes one as completed. When the agent believes a task is finished, it asks the owner for
review and shows the proof: what it ran and what came back. Only the owner's `#ok` completes it.

**5.2 The commands**

| Command | Does |
|---|---|
| `#go` | Signs the work order. Nothing runs before it. |
| `#ok` | Accepts the work the agent asked him to review. The only thing that completes a task or a job. |
| `#redo` | Starts over. The work is sent back and nothing runs again until a new `#go`. |
| `#push` | Allows the push, the pull request and the merge. |
| `#add` | Adds work to the running contract (5.3). |
| `#strike <item>` | Removes an item from the contract, by name. |
| `#override [span]` | Lifts every working gate for work the owner directs. Never the protection rules. |
| `#mute <gate> [span]` | Silences one gate. |
| `#unmute <gate \| all>` | Turns a gate back on. |

**5.3 Adding work mid-contract.** Sometimes the signed plan won't reach the goal, or work nobody foresaw turns up.
Then the work is added; the contract does not start over.
- **Who can raise it:** the owner, the agent, Jev, the orchestration layer or a task auditor can say more work or
  another tool is needed.
- **Who decides:** only the owner adds it, with `#add`. It can be a task, a step, a scope, a skill, a tool, a plugin
  or an agent.
- **What happens:** the added lines join the contract and its plan at once. No stop gate blocks the addition, and
  nothing already done is undone.

**5.4 How long an override or a mute lasts.** Every `#override` and `#mute` names its span:
- `turn`: until the owner's next message (the default),
- `task`: until the current task closes,
- `contract`: until the contract closes,
- `on`: until further notice, which means until `#unmute`.

**5.5 Interjections.** The owner may type a command at any point, even in the middle of a task, and it takes effect
at once.

---

## Rule 6. Wrap-up and upkeep

**6.1 The wrap-up.** A session ends with the wrap-up, on the owner's command. It sends everything the session made to
its home, so the next session starts from files, not from memory:
- **The session's notes** (scratchpad, task log, skill log) go to `NvAEx-Recaps/session-logs/<date>-<session>/`.
- **In the repo the work was in:**
  - lasting facts go to MEMORY.md,
  - changes to protocols, settings, manifests or output style go to AGENTS.md (rules themselves only in RULES.md),
  - RESUME.md is rewritten from scratch,
  - anything not done goes to PENDING.md.
- **The next session's context** is written as a handoff in `NvAEx-Recaps/handoff/<date>/`, and the repo's
  HANDOFF.md points to it.
- **The task observer** logs the session's observations.
- **Then GitHub (rule 4.4):** every touched repo is committed, scanned, pushed and merged. Nothing is left behind.

**6.2 Contracts are kept.** Every finished contract is saved as a permanent file, with its runs, its plan, its tool
log and the owner's verdict. They are kept for audits, for deep searches, and for tracing a bug back to the job that
made it.

**6.3 RLVR: every result is graded and verified.** RLVR means rewards from verifiable results: work counts only when
a real check proves it.
- **Graded by a check.** Every task's result is graded by something that can be checked: a test that ran, a
  command's output, a file read back, never the agent's word. Whatever made the work does not grade it.
- **Rates kept.** The success rate and the verification rate are kept for every agent and every kind of task.
- **Scripted and trained.** Verified results, and the scripts that checked them, feed the training: what passed
  becomes a script or a workflow; what failed becomes a fix.

**6.4 Upkeep, every session**
- **Memory.** Keep every memory layer up to date as you go, not only at the end.
- **Writing to task.** Write to the task as you work: what was done, what came back, what is next.
- **Session logs.** Log every session.
- **Housekeeping.** Clean up as you go: nothing stale, no stragglers.
- **GitHub.** Everything is pushed and auto-merged, unless the owner says otherwise.
