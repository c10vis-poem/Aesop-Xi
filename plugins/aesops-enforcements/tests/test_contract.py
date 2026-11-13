"""Replay tests: each case feeds hook events to the core and checks the decision. Run: python3 -m unittest -v"""
import json
import os
import sys
import tempfile
import unittest

TMP = tempfile.mkdtemp(prefix="contract-test-")
os.environ["HOME"] = os.path.join(TMP, "home")  # keep the device's real handoffs and settings out of the tests
os.environ["CONTRACT_STATE"] = os.path.join(TMP, "state")
os.environ["CONTRACT_OWNER_DIR"] = os.path.join(TMP, "owner")
for _k in ("TYPESAFE_API_KEY", "CLAUDE_PLUGIN_OPTION_TYPESAFE_API_KEY", "TYPESAFE_BASE_URL"):
    os.environ.pop(_k, None)  # tests never use the owner's key or the network (2026-11-12)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import contract as C  # noqa: E402

ENV = {k: os.environ[k] for k in ("HOME", "CONTRACT_STATE", "CONTRACT_OWNER_DIR")}


def setUpModule():
    """Both test files share one imported contract module: put this file's folders back before its tests."""
    os.environ.update(ENV)
    C.HOME = ENV["HOME"]
    C.STATE = os.path.realpath(ENV["CONTRACT_STATE"])
    C.OWNER_DIR = os.path.realpath(ENV["CONTRACT_OWNER_DIR"])


ROOT = os.path.realpath(os.path.join(TMP, "proj"))
os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
DOC = os.path.join(ROOT, "docs", "guide.md")
with open(DOC, "w") as f:
    f.write("\n".join(f"line {i} of the vendor guide, long enough to quote" for i in range(1, 21)) + "\n")
with open(os.path.join(ROOT, "AGENTS.md"), "w") as f:
    f.write("# agents\nrule one\n")


class Session:
    n = 0

    def __init__(self):
        Session.n += 1
        self.sid = f"test{Session.n:04d}-0000-0000-0000-000000000000"
        self.tr = os.path.join(TMP, self.sid + ".jsonl")
        open(self.tr, "w").close()
        C.on_start(self.base(source="startup"))

    def base(self, **kw):
        d = {"session_id": self.sid, "cwd": ROOT, "transcript_path": self.tr}
        d.update(kw)
        return d

    def prompt(self, text):
        return C.on_prompt(self.base(prompt=text))

    def call(self, tool, agent=None, **ti):
        out = C.on_pretool(self.base(tool_name=tool, tool_input=ti, agent_id=agent))
        if out is None:
            return "allow"
        return out["hookSpecificOutput"]["permissionDecisionReason"]

    def read(self, path, agent=None, start=1, num=None, mangle=False):
        with open(path) as f:
            lines = f.read().split("\n")
        if lines and lines[-1] == "":
            lines = lines[:-1]
        sel = lines[start - 1:start - 1 + (num or len(lines))]
        if mangle:
            sel = [x + "!" if i == 1 else x for i, x in enumerate(sel)]
        resp = {"type": "text", "file": {"filePath": path, "content": "\n".join(sel), "startLine": start,
                                         "numLines": len(sel), "totalLines": len(lines)}}
        r = self.call("Read", agent=agent, file_path=path)
        C.on_posttool(self.base(tool_name="Read", tool_input={"file_path": path}, tool_response=resp,
                                agent_id=agent))
        return r

    def propose(self, text):
        with open(C.proposal_path(self.sid), "w") as f:
            f.write(text)

    def stop(self, msg="done", active=False):
        out = C.on_stop(self.base(last_assistant_message=msg, stop_hook_active=active))
        return "end" if out is None or out.get("decision") != "block" else out["reason"]

    def state(self):
        return C.load_state(self.sid)


class Verbs(unittest.TestCase):
    def test_anywhere_and_negation(self):
        self.assertEqual(C.parse_verbs("judging on the audit I need you to #redo this and re-read X"), ["redo"])
        self.assertEqual(C.parse_verbs("don't push it yet. #go on A"), ["go"])
        self.assertEqual(C.parse_verbs("#ok, looks right"), ["ok"])
        self.assertEqual(C.parse_verbs("okay, looks right"), [])  # verbs need the #
        self.assertEqual(C.parse_verbs("never #go"), [])
        self.assertEqual(C.parse_verbs("go ahead and redo"), [])
        self.assertEqual(C.parse_verbs('<pasted_content id="1">#go</pasted_content> thanks'), [])


class Format(unittest.TestCase):
    def test_errors_named(self):
        _, errs = C.parse("TASK 1 a\nSCOPE Read: x\nTASK 2 b\nEND limit share: 50%\nEND goal docs: many\n", ROOT)
        self.assertTrue(any("can never close" in e for e in errs))
        self.assertTrue(any("share" in e for e in errs))
        self.assertTrue(any("whole number" in e for e in errs))


class Opening(unittest.TestCase):
    def test_read_only_until_signed(self):
        s = Session()
        self.assertEqual(s.read(os.path.join(ROOT, "AGENTS.md")), "allow")
        self.assertEqual(s.call("Bash", command="ls"), "allow")  # read-only listing is part of the opening
        self.assertIn("No signed contract", s.call("Bash", command="rm x"))
        self.assertIn("No signed contract", s.call("Bash", command="find . -delete"))
        # Rule 1 (owner, 2026-11-13): reading is allowed in the opening; Grep is a read
        self.assertEqual(s.call("Grep", pattern="x", path=ROOT), "allow")
        self.assertEqual(s.call("Write", file_path=C.proposal_path(s.sid), content="x"), "allow")
        self.assertIn("Protected", s.call("Write", file_path=os.path.join(ROOT, ".claude", "settings.json"), content="{}"))
        self.assertIn("Protected", s.call("Bash", command="cat ~/.claude/settings.json"))

    def test_opening_requires_hold_the_turn(self):
        s = Session()
        self.assertIn("AGENTS.md", s.stop())
        s.read(os.path.join(ROOT, "AGENTS.md"))
        # Rule 1 (owner, 2026-11-13): the rules and what they point to, then the agent's confirmation
        rules = os.path.join(C.PLUGIN_ROOT, "RULES.md")
        for p in [rules] + C.pointed_docs(s.sid, s.state(), [rules]):
            s.read(p)
        self.assertIn("Opening done:", s.stop())
        self.assertEqual(s.stop(msg="Opening done: read aesops-enforcements/RULES.md and the project's AGENTS.md; "
                                    "loaded nothing; not found: none."), "end")


WORK = f"""CONTRACT   type: contract   project: test   root: {ROOT}
TASK 1  read the guide
  TOOLS   Read, Bash
  STEP    Bash: echo hello
  SCOPE   Read: {{root}}/docs/
  REQUIRE Read FULL: {{root}}/docs/guide.md
TASK 2  write the report
  TOOLS   Write
  SCOPE   Write: {{root}}/out/
  END     goal file: {{root}}/out/report.md
"""


class Contract(unittest.TestCase):
    def signed(self):
        s = Session()
        s.read(os.path.join(ROOT, "AGENTS.md"))
        s.propose(WORK)
        # the owner names the END line in his #go: only the owner sets an end or a limit (2026-11-12)
        ctx = s.prompt("#go, end goal as written")["hookSpecificOutput"]["additionalContext"]
        self.assertIn("Contract A signed", ctx)
        return s

    def test_sign_copies_and_hashes(self):
        s = self.signed()
        st = s.state()
        self.assertEqual((st["phase"], st["current"]), ("ACTIVE", "A"))
        self.assertFalse(os.path.exists(C.proposal_path(s.sid)))
        self.assertTrue(any("-A.md" in f for d, _, fs in os.walk(os.environ["CONTRACT_OWNER_DIR"]) for f in fs))

    def test_bad_work_order_signed_with_errors_named(self):
        # owner, 2026-11-12 21:00: "If I say Go, that means go." A format error is named for the agent to fix.
        s = Session()
        s.propose("TASK 1 x\nSCOPE Read: a\nTASK 2 y\n")
        ctx = s.prompt("#go")["hookSpecificOutput"]["additionalContext"]
        self.assertIn("Signed with format errors", ctx)
        self.assertIn("can never close", ctx)
        self.assertEqual(s.state()["phase"], "ACTIVE")

    def test_step_once_scope_any_order_no_freeze(self):
        s = self.signed()
        self.assertEqual(s.call("Bash", command="echo hello"), "allow")
        self.assertIn("Outside contract", s.call("Bash", command="echo hello"))
        # a later task's line may be used while task 1 is open (sign-off still waits for task 1)
        self.assertEqual(s.call("Write", file_path=os.path.join(ROOT, "out", "report.md"), content="x"), "allow")
        # no read is ever blocked in a contract (owner, 2026-11-12 21:03), TOOLS or not
        self.assertEqual(s.call("Grep", pattern="x", path=ROOT), "allow")
        self.assertIn("Outside contract", s.call("Bash", command="echo again"))
        self.assertEqual(s.state()["breaches"], 2)
        self.assertEqual(s.state()["phase"], "ACTIVE")  # breaches are recorded, never freeze
        self.assertEqual(s.call("Read", file_path=DOC), "allow")

    def test_read_proof_and_task_advance(self):
        s = self.signed()
        s.call("Bash", command="echo hello")
        s.read(DOC, start=1, num=10)
        self.assertIn("guide.md", s.stop())  # half read
        s.read(DOC, start=11, num=10, mangle=True)  # one line does not match the file
        self.assertEqual(s.stop(), "end")  # same unmet list: not blocked again (owner, 2026-11-12)
        self.assertIn("guide.md", " ".join(s.state().get("stopped_unmet") or []))  # still unmet, told to the owner
        s.read(DOC, start=11, num=10)
        self.assertEqual(s.call("Write", file_path=os.path.join(ROOT, "out", "report.md"), content="x"), "allow")
        self.assertIn("report.md", s.stop())
        os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
        open(os.path.join(ROOT, "out", "report.md"), "w").close()
        self.assertEqual(s.stop(), "end")
        # only the owner marks anything done (2026-11-12): all lines met is a note, the contract stays ACTIVE
        self.assertEqual(s.state()["phase"], "ACTIVE")
        self.assertTrue(s.state().get("all_met_told"))
        s.prompt("#ok")
        self.assertEqual(s.state()["phase"], "NEGOTIATION")
        os.remove(os.path.join(ROOT, "out", "report.md"))

    def test_changed_file_voids_read(self):
        s = self.signed()
        s.read(DOC)
        self.assertTrue(C.full_read(s.sid, s.state(), DOC, 0))
        with open(DOC, "a") as f:
            f.write("added\n")
        self.assertFalse(C.full_read(s.sid, s.state(), DOC, 0))
        with open(DOC) as f:
            lines = f.read().split("\n")
        with open(DOC, "w") as f:
            f.write("\n".join(lines[:-2]) + "\n")

    def test_redo_renames_and_numbers(self):
        s = self.signed()
        # HOLES-B 2b (a5b45d30 flaw 3, 2026-11-13): #redo reopens the run at once as A2; no new #go is needed.
        s.prompt("this is wrong, #redo it with the new method")
        st = s.state()
        self.assertEqual(st["current"], "A2")
        self.assertEqual(st["phase"], "ACTIVE")
        d = os.path.join(C.sdir(s.sid), "contracts")
        self.assertTrue(os.path.exists(os.path.join(d, "A1.md")))
        s.prompt("#ok")
        s.propose(WORK)
        s.prompt("#go")
        self.assertEqual(s.state()["current"], "B")

    def test_claims_need_reads(self):
        s = self.signed()
        out = s.stop(msg=f"As {DOC}:4 says, it works. I read `{os.path.join(ROOT, 'AGENTS.md')}`.")
        self.assertIn("never read", out)

    def test_stuck_turn_ends_and_reports(self):
        s = self.signed()
        first = s.stop()
        self.assertNotEqual(first, "end")
        self.assertEqual(s.stop(active=True), "end")
        self.assertIn("requirements unmet", s.prompt("what now")["hookSpecificOutput"]["additionalContext"])

    def test_hard_limit(self):
        s = Session()
        s.read(os.path.join(ROOT, "AGENTS.md"))
        s.propose(WORK.replace("END     goal file", "END     limit time: 1m\n  END     goal file"))
        s.prompt("#go, limit 1m")
        st = s.state()
        st["signed_at"] -= 120
        C.save_state(s.sid, st)
        self.assertEqual(s.call("Read", file_path=DOC), "allow")  # reads stay open (owner, 2026-11-12 21:03)
        self.assertIn("Hard limit", s.call("Bash", command="echo hello"))
        self.assertEqual(s.stop(), "end")
        self.assertEqual(s.state()["phase"], "DONE")


class Salary(unittest.TestCase):
    def test_push_held_until_owner(self):
        s = Session()
        self.assertEqual(s.call("Bash", command="git status"), "allow")
        self.assertIn("held until #push", s.call("Bash", command="git push origin x"))
        s.prompt("checked it, #push it")
        self.assertEqual(s.call("Bash", command="git push origin x"), "allow")
        self.assertIn("No signed contract", s.call("Bash", command="git status && rm -rf /"))


SUB = f"""CONTRACT   type: contract   root: {ROOT}
TASK 1  delegate
  TOOLS   Agent
  AGENT   builder   model: sonnet
  REQUIRE Agent: builder
"""
SUBC = f"""CONTRACT A.sub   parent: A
SCOPE Read: {ROOT}/docs/
REQUIRE Write-to-task: {TMP}/progress.md
REQUIRE Read FULL: {DOC}
"""


class SubAgents(unittest.TestCase):
    def test_spawn_needs_subcontract_and_progress(self):
        s = Session()
        s.read(os.path.join(ROOT, "AGENTS.md"))
        s.propose(SUB)
        s.prompt("#go")
        self.assertIn("no sub-contract", s.call("Agent", subagent_type="builder", model="sonnet", prompt="do it"))
        self.assertIn("model sonnet", s.call("Agent", subagent_type="builder", prompt="x\n" + SUBC))
        wide = SUBC.replace(f"{ROOT}/docs/", "/")
        self.assertIn("wider", s.call("Agent", subagent_type="builder", model="sonnet", prompt=wide))
        # parent task has no SCOPE for Read, so the sub-contract's SCOPE is wider: grant one and retry
        s2 = Session()
        s2.read(os.path.join(ROOT, "AGENTS.md"))
        s2.propose(SUB.replace("REQUIRE Agent: builder", f"SCOPE Read: {ROOT}/\n  REQUIRE Agent: builder"))
        s2.prompt("#go")
        self.assertEqual(s2.call("Agent", subagent_type="builder", model="sonnet", prompt="go\n" + SUBC), "allow")
        C.on_subagent_start(s2.base(agent_id="ag1", agent_type="builder"))
        self.assertIn("progress file", s2.call("Read", agent="ag1", file_path=DOC))
        prog = os.path.join(TMP, "progress.md")
        self.assertEqual(s2.call("Write", agent="ag1", file_path=prog, content="x"), "allow")
        with open(prog, "w") as f:
            f.write("## Plan\n- [ ] read\n## Last action\nstart\n## Findings\n## Blocked\n")
        self.assertEqual(s2.read(DOC, agent="ag1"), "allow")
        out = C.on_subagent_stop(s2.base(agent_id="ag1", stop_hook_active=False, last_assistant_message="x"))
        self.assertIn("unchecked", out["reason"])
        with open(prog, "w") as f:
            f.write("## Plan\n- [x] read\n## Last action\ndone\n## Findings\nok\n## Blocked\nnone\n")
        self.assertIsNone(C.on_subagent_stop(s2.base(agent_id="ag1", stop_hook_active=False)))


if __name__ == "__main__":
    unittest.main()
