"""Contract A3 task 3: the enforcement holes (2026-11-12). Run: python3 -I tests/test_a3_holes.py [--root <plugin>]
--root tests another copy of the plugin (the installed one) with these same tests."""
import http.server
import json
import os
import sys
import tempfile
import threading
import unittest

ROOT_ARG = None
if "--root" in sys.argv:
    i = sys.argv.index("--root")
    ROOT_ARG = sys.argv[i + 1]
    del sys.argv[i:i + 2]
PLUGIN = os.path.realpath(ROOT_ARG or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

TMP = tempfile.mkdtemp(prefix="contract-a3-holes-")
os.environ["HOME"] = os.path.join(TMP, "home")
os.environ["CONTRACT_STATE"] = os.path.join(TMP, "home", ".claude", "state")
os.environ["CONTRACT_OWNER_DIR"] = os.path.join(TMP, "owner")
for k in ("TYPESAFE_API_KEY", "CLAUDE_PLUGIN_OPTION_TYPESAFE_API_KEY", "TYPESAFE_BASE_URL"):
    os.environ.pop(k, None)
sys.path.insert(0, os.path.join(PLUGIN, "lib"))
import contract as C  # noqa: E402

HOME = os.environ["HOME"]
PROJ = os.path.realpath(os.path.join(TMP, "proj"))
OTHER = os.path.realpath(os.path.join(TMP, "other"))
H = os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-12")
for d in (os.path.join(PROJ, "docs"), os.path.join(PROJ, "out"), OTHER, H):
    os.makedirs(d, exist_ok=True)


def w(p, t):
    with open(p, "w") as f:
        f.write(t)


w(os.path.join(PROJ, "AGENTS.md"), "# agents\nSee `docs/pointed.md` and docs/missing.md for more.\n")
w(os.path.join(PROJ, "docs", "pointed.md"), "pointed doc\nsecond line\n")
w(os.path.join(H, "handoff.md"), "handoff\n")
w(os.path.join(PROJ, "RULES.md"), "project rules\n")
w(os.path.join(OTHER, "RULES.md"), "other repo rules\n")
w(os.path.join(PROJ, "docs", "fix.md"), "never read\n")
w(os.path.join(PROJ, "out", "done.md"), "x\n")
QUIZ = os.path.join(PROJ, "docs", "quiz.md")
w(QUIZ, "\n".join(f"quiz line {i} long enough to be drawn" for i in range(1, 11)) + "\n")


class Session:
    n = 0

    def __init__(self):
        Session.n += 1
        self.sid = f"holes{Session.n:03d}-0000-0000-0000-000000000000"
        self.tr = os.path.join(TMP, self.sid + ".jsonl")
        open(self.tr, "w").close()
        C.on_start(self.base(source="startup"))

    def base(self, **kw):
        d = {"session_id": self.sid, "cwd": PROJ, "transcript_path": self.tr}
        d.update(kw)
        return d

    def read(self, path):
        with open(path) as f:
            text = f.read()
        lines = text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")
        resp = {"type": "text", "file": {"filePath": path, "content": "\n".join(lines), "startLine": 1,
                                         "numLines": len(lines), "totalLines": len(lines)}}
        C.on_pretool(self.base(tool_name="Read", tool_input={"file_path": path}))
        C.on_posttool(self.base(tool_name="Read", tool_input={"file_path": path}, tool_response=resp))

    def call(self, tool, agent=None, **ti):
        out = C.on_pretool(self.base(tool_name=tool, tool_input=ti, agent_id=agent))
        return "allow" if out is None else out["hookSpecificOutput"]["permissionDecisionReason"]

    def stop(self, msg="working"):
        out = C.on_stop(self.base(last_assistant_message=msg, stop_hook_active=False))
        if out is None:
            return "end"
        return out["reason"] if out.get("decision") == "block" else "end:" + out.get("systemMessage", "")

    def prompt(self, text):
        return C.on_prompt(self.base(prompt=text))["hookSpecificOutput"]["additionalContext"]

    def opening(self):
        for p in (os.path.join(PROJ, "AGENTS.md"), os.path.join(H, "handoff.md"), os.path.join(PROJ, "docs", "pointed.md")):
            self.read(p)

    def sign(self, text):
        self.opening()
        w(C.proposal_path(self.sid), text)
        return self.prompt("#go")


DONE_WORK = f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
SCOPE Bash: python3 -I {PROJ}/tests/test_x.py
TASK 1  report
  REQUIRE File: {{root}}/out/done.md
TASK 2  later
  REQUIRE File: {{root}}/out/never.md
"""


class OpeningPointedDocs(unittest.TestCase):
    """3a: a document an opening file points to is read before the first stop; a missing one is not required."""

    def test_pointed_doc_required(self):
        s = Session()
        s.read(os.path.join(PROJ, "AGENTS.md"))
        s.read(os.path.join(H, "handoff.md"))
        out = s.stop()
        self.assertIn("pointed.md (an opening file points to it)", out)
        self.assertNotIn("missing.md", out)
        s.read(os.path.join(PROJ, "docs", "pointed.md"))
        self.assertTrue(s.stop().startswith("end"))


class Claims(unittest.TestCase):
    """Lie-test holes 2 and 3."""

    def setUp(self):
        self.s = Session()
        self.st = C.load_state(self.s.sid)

    def test_plain_word_read_claim(self):
        self.assertTrue(C.claim_check(self.s.sid, self.st, "I went through docs/fix.md and it is fine."))

    def test_tests_pass_without_a_run(self):
        miss = C.claim_check(self.s.sid, self.st, "All 41 tests pass.")
        self.assertTrue(any("no test run" in m for m in miss), miss)

    def test_tests_pass_with_a_run(self):
        s = Session()
        s.sign(DONE_WORK)
        self.assertEqual(s.call("Bash", command=f"python3 -I {PROJ}/tests/test_x.py"), "allow")
        st = C.load_state(s.sid)
        self.assertFalse([m for m in C.claim_check(s.sid, st, "9 tests pass, output above.") if "no test run" in m])

    def test_failing_tests_are_not_a_pass_claim(self):
        self.assertFalse([m for m in C.claim_check(self.s.sid, self.st, "Tests not passing yet.") if "no test run" in m])

    def test_bare_name_means_the_projects_file(self):
        self.s.read(os.path.join(OTHER, "RULES.md"))
        st = C.load_state(self.s.sid)
        self.assertTrue(C.claim_check(self.s.sid, st, "I read `RULES.md` in full."))
        self.s.read(os.path.join(PROJ, "RULES.md"))
        st = C.load_state(self.s.sid)
        self.assertEqual(C.claim_check(self.s.sid, st, "I read `RULES.md` in full."), [])


class Quiz(unittest.TestCase):
    """Lie-test hole 4: a search over the quiz file's folder fails the quiz."""

    def taint_after(self, tool, **ti):
        s = Session()
        st = C.load_state(s.sid)
        st["quote"] = {"path": QUIZ, "lines": ["quiz line 1 long enough to be drawn"], "task": 1}
        C.save_state(s.sid, st)
        C.on_pretool(s.base(tool_name=tool, tool_input=ti))
        return C.load_state(s.sid)["quote"].get("tainted")

    def test_grep_folder(self):
        self.assertTrue(self.taint_after("Grep", pattern="quiz line", path=os.path.dirname(QUIZ)))

    def test_grep_no_path(self):
        self.assertTrue(self.taint_after("Grep", pattern="quiz line"))

    def test_bash_folder(self):
        self.assertTrue(self.taint_after("Bash", command=f"grep -rn quiz {os.path.dirname(QUIZ)}"))

    def test_unrelated_read(self):
        self.assertFalse(self.taint_after("Read", file_path=os.path.join(PROJ, "AGENTS.md")))


class SplitPathsAndScripts(unittest.TestCase):
    """Lie-test hole 5: a protected path split in code, or inside a script the command runs."""

    def prot(self, cmd):
        return C.protection("y" * 36, "Bash", {"command": cmd})

    # The test data is assembled at run time ({q} is a quote), so this file's own text never holds a joinable
    # settings path: the gate inspects a script before running it, and would refuse to run these tests otherwise.
    def test_split_settings_path(self):
        q, s = "'", "settings"
        self.assertIsNotNone(self.prot(f"""python3 -c "open({q}{HOME}/.cla{q} + {q}ude/{s}.json{q},{q}w{q}).write({q}x{q})" """))

    def test_joined_parts(self):
        q, s = "'", "settings"
        self.assertIsNotNone(self.prot(
            f"""python3 -c "import os;open(os.path.join({q}{HOME}{q},{q}.claude{q},{q}{s}.json{q}),{q}w{q})" """))

    def test_script_file(self):
        bad = os.path.join(TMP, "bad.py")
        w(bad, f"open('{C.PLUGIN_ROOT}/RULES.md', 'w').write('gone')\n")
        self.assertIsNotNone(self.prot(f"python3 {bad}"))
        good = os.path.join(TMP, "good.py")
        w(good, "print('hello')\n")
        self.assertIsNone(self.prot(f"python3 {good}"))


class LastAction(unittest.TestCase):
    """Lie-test hole 6: a sub-agent's '## Last action' must change between calls."""

    def test_unchanged_last_action_refused(self):
        out_dir = os.path.join(PROJ, "out", "sub")
        os.makedirs(out_dir, exist_ok=True)
        prog = os.path.join(out_dir, "progress.md")
        parent = f"""CONTRACT   type: contract   root: {PROJ}
AGENT general-purpose model: opus
SCOPE   Read: *
SCOPE   Write: {{root}}/out/
SCOPE   Bash: echo
TASK 1  delegate
  REQUIRE Agent: general-purpose
"""
        s = Session()
        self.assertIn("signed", s.sign(parent))
        sub = f"""CONTRACT SUB   type: sub
SCOPE   Write: {out_dir}
SCOPE   Bash: echo
TASK 1  work
  REQUIRE Write-to-task: {prog}
"""
        self.assertEqual(s.call("Agent", subagent_type="general-purpose", model="opus", prompt="go\n\n" + sub), "allow")
        C.on_subagent_start(s.base(agent_type="general-purpose", agent_id="ag1"))
        w(prog, "## Plan\n- [ ] a\n## Last action\nstep 1\n## Findings\n-\n## Blocked\nnone\n")
        self.assertEqual(s.call("Bash", agent="ag1", command="echo one"), "allow")
        os.utime(prog)  # the file is touched, its Last action is not changed
        st = C.load_state(s.sid)
        later = max(e["t"] for e in C.ledger(s.sid) if e.get("agent") == "ag1") + 1
        os.utime(prog, (later, later))
        self.assertIn("still says the same", s.call("Bash", agent="ag1", command="echo two"))
        w(prog, "## Plan\n- [ ] a\n## Last action\nstep 2: echoed one, now echo two\n## Findings\n-\n## Blocked\nnone\n")
        os.utime(prog, (later + 1, later + 1))
        self.assertEqual(s.call("Bash", agent="ag1", command="echo two"), "allow")
        del st


class NothingSkipped(unittest.TestCase):
    """3f: a deferral in the agent's message holds the stop; quoting the rule does not."""

    def test_phrases(self):
        self.assertTrue(C.deferrals("I'll fix that in the next session."))
        self.assertTrue(C.deferrals("Parked: the mods, for now."))
        self.assertFalse(C.deferrals("Nothing skipped: every item is done."))
        self.assertFalse(C.deferrals("The rule says never put off work."))
        self.assertFalse(C.deferrals('The gate flagged "work put off" in my quote of it.'))
        self.assertFalse(C.deferrals("It matched the label `work skipped or put off`, not me."))
        self.assertTrue(C.deferrals("The adapters are put off until tomorrow."))

    def test_stop_holds(self):
        s = Session()
        s.sign(DONE_WORK)
        self.assertIn("puts work off", s.stop("Task 1 is done; the rest is a follow-up."))


class FakeJev:
    def __init__(self, mode):
        self.mode = mode
        outer = self

        class Hd(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                n = int(self.headers.get("Content-Length", 0))
                outer.body = json.loads(self.rfile.read(n))
                if outer.mode == "http500":
                    self.send_response(500)
                    self.end_headers()
                    return
                import random
                p = {"block": 0.9, "unsure": 0.5, "clean": 0.05, "random": random.uniform(0.75, 0.99)}[outer.mode]
                ans = {k: {"noul": p if k == "claims_unproven" else 0.05} for k in outer.body["questions"]}
                data = json.dumps({"answers": ans, "model": "fake"}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *a):
                pass

        self.srv = http.server.HTTPServer(("127.0.0.1", 0), Hd)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        os.environ["TYPESAFE_API_KEY"] = "fake-test-key"
        os.environ["TYPESAFE_BASE_URL"] = f"http://127.0.0.1:{self.srv.server_port}"

    def close(self):
        self.srv.shutdown()
        os.environ.pop("TYPESAFE_API_KEY", None)
        os.environ.pop("TYPESAFE_BASE_URL", None)


class JevAudit(unittest.TestCase):
    """Decision 2: Jev judges the message and tool log; the code decides."""

    def run_stop(self, mode, msg="Task 1 is done: out/done.md exists."):
        j = FakeJev(mode) if mode != "nokey" else None
        try:
            s = Session()
            s.sign(DONE_WORK)
            return s.stop(msg), (j.body if j else None)
        finally:
            if j:
                j.close()

    def test_yes_blocks(self):
        out, body = self.run_stop("block")
        self.assertIn("Jev: a claim the tool log does not show", out)
        self.assertEqual(set(body["questions"]), {"claims_unproven", "content_as_fact", "work_put_off"})
        self.assertIn("tool_log", body["state"])

    def test_unsure_warns_owner(self):
        out, _ = self.run_stop("unsure")
        self.assertTrue(out.startswith("end") or "task 2" in out, out)
        self.assertNotIn("Jev: a claim", out)

    def test_no_answer_holds(self):
        out, _ = self.run_stop("http500")
        self.assertIn("got no answer (http-500)", out)

    def test_no_key_is_off_and_said(self):
        s = Session()
        s.sign(f"""CONTRACT   type: contract   root: {PROJ}
TASK 1  report
  REQUIRE File: {{root}}/out/done.md
""")
        out = s.stop("Task 1 is done: out/done.md exists.")
        st = C.load_state(s.sid)
        self.assertTrue(st.get("jev_off_told"), out)

    def test_changing_numbers_do_not_loop(self):
        """Jev's probability differs on every answer; the same verdict must still be named only once."""
        j = FakeJev("random")
        try:
            s = Session()
            s.sign(DONE_WORK)
            first = s.stop("Task 1 is done.")
            self.assertIn("Jev: a claim the tool log does not show", first)
            self.assertNotIn("yes 0.", first)
            self.assertTrue(s.stop("Task 1 is done.").startswith("end"), "same verdict, new number: blocked again")
        finally:
            j.close()

    def test_flip_flopping_verdict_does_not_loop(self):
        """Jev says yes, then no, then yes: the contract's own lines are unchanged, so it blocks once."""
        j = FakeJev("block")
        try:
            s = Session()
            s.sign(DONE_WORK)
            self.assertIn("Jev:", s.stop("Task 1 is done."))
            j.mode = "clean"
            self.assertTrue(s.stop("Task 1 is done.").startswith("end"))
            j.mode = "block"
            self.assertTrue(s.stop("Task 1 is done.").startswith("end"), "the flip back blocked again")
        finally:
            j.close()

    def test_question_to_owner_not_audited(self):
        self.assertTrue(C._asks_owner("Here is what I found.\n- **1.** do it\n- **2.** wait\n- **3.** other"))
        self.assertTrue(C._asks_owner("Which one do you want?"))
        self.assertFalse(C._asks_owner("Task 1 is done."))
        j = FakeJev("block")
        try:
            s = Session()
            s.sign(DONE_WORK)
            self.assertNotIn("Jev:", s.stop("I need your call first. Which one do you want?"))
        finally:
            j.close()

    def test_key_not_sent_in_output(self):
        out, _ = self.run_stop("block")
        self.assertNotIn("fake-test-key", out)


class ChecksOnlyAtTheStop(unittest.TestCase):
    """Every Check ran on every prompt and tool call; four slow ones took the prompt hook past 20 s and the owner's
    prompt was lost. Checks now run at the stop only; prompts and tool calls reuse the last result."""

    def test_slow_check_not_run_on_prompt_or_call(self):
        import time
        s = Session()
        s.sign(f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
TASK 1  slow
  REQUIRE Check: sleep 3
TASK 2  next
  REQUIRE File: {{root}}/out/never.md
""")
        t0 = time.time()
        s.prompt("hello")
        s.call("Bash", command="echo hi")
        self.assertLess(time.time() - t0, 2.5, "a Check ran during a prompt or a tool call")
        t0 = time.time()
        out = s.stop()
        self.assertGreaterEqual(time.time() - t0, 3, "the stop did not run the Check")
        self.assertIn("task 2", out)  # the Check passed at the stop, so task 1 closed
        t0 = time.time()
        self.assertIn("task 2", s.prompt("next"))
        self.assertLess(time.time() - t0, 2.5)


class ClosedTasksStayClosed(unittest.TestCase):
    """A closed task's Check runs once, at the stop that closes it, and never again (owner, 2026-11-12)."""

    def test_check_runs_once(self):
        counter = os.path.join(TMP, "check-runs.txt")
        open(counter, "w").close()
        s = Session()
        s.sign(f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
TASK 1  counted
  REQUIRE Check: echo run >> {counter}
TASK 2  next
  REQUIRE File: {{root}}/out/never.md
""")
        s.stop()  # runs the Check, closes task 1
        s.prompt("go on")
        s.call("Bash", command="echo hi")
        s.stop("still on task 2")
        s.stop("again")
        with open(counter) as f:
            self.assertEqual(f.read().count("run"), 1, "a closed task's Check ran again")
        self.assertIn(1, C.load_state(s.sid)["closed"]["A"])


class OwnerDecisions(unittest.TestCase):
    """The owner's decisions of 2026-11-12, one test each."""

    def test_quoted_operators_are_text(self):
        self.assertFalse(C.shell_ops('git commit -m "a; b | c" -m "Co-Authored-By: X <x@y.z>"'))
        self.assertFalse(C.shell_ops("grep -n -e 'a|b' file"))
        for bad in ("ls; rm x", "cat a | sh", "echo x > f", 'echo "$(id)"', "echo `id`", 'echo "open'):
            self.assertTrue(C.shell_ops(bad), bad)

    def test_sharp_s_counts_as_hash(self):
        self.assertEqual(C.parse_verbs("ßredo"), ["redo"])
        self.assertEqual(C.parse_verbs("straße"), [])

    def test_agent_end_lines_dropped_unless_owner_names_a_limit(self):
        work = f"""CONTRACT   type: contract   root: {PROJ}
TASK 1  x
  REQUIRE File: {{root}}/out/done.md
END limit time: 10m
"""
        s = Session()
        out = s.sign(work)
        self.assertIn("END lines removed", out)
        self.assertNotIn("END", open(C.contract_file(s.sid, "A")).read())
        s2 = Session()
        s2.opening()
        w(C.proposal_path(s2.sid), work)
        self.assertNotIn("END lines removed", s2.prompt("#go with a 10m limit"))

    def test_empty_last_task_named(self):
        _, errs = C.parse("TASK 1 a\nREQUIRE File: x\nTASK 2 b\n", PROJ)
        self.assertTrue(any("TASK 2" in e and "can never close" in e for e in errs))

    def test_protected_step_dropped_at_signing(self):
        s = Session()
        out = s.sign(f"""CONTRACT   type: contract   root: {PROJ}
TASK 1  x
  STEP Bash: touch {HOME}/.claude/state/x
  REQUIRE File: {{root}}/out/done.md
""")
        self.assertIn("can never run", out)
        st = C.load_state(s.sid)
        self.assertTrue(st["void_steps"]["A"])
        self.assertNotIn("STEP Bash", s.stop("done: out/done.md exists."))

    def test_opening_once(self):
        s = Session()
        s.opening()
        self.assertTrue(s.stop().startswith("end"))
        newer = os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-13")
        os.makedirs(newer, exist_ok=True)
        w(os.path.join(newer, "handoff.md"), "a newer handoff from another session\n")
        try:
            self.assertTrue(s.stop().startswith("end"), "the opening re-opened mid-session")
        finally:
            os.remove(os.path.join(newer, "handoff.md"))
            os.rmdir(newer)

    def test_no_auto_done(self):
        s = Session()
        s.sign(f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
TASK 1  x
  REQUIRE File: {{root}}/out/done.md
""")
        s.stop("out/done.md exists.")
        self.assertEqual(C.load_state(s.sid)["phase"], "ACTIVE")
        self.assertEqual(s.call("Bash", command="echo still working"), "allow")


class PromptShape(unittest.TestCase):
    """3c: the shape of each prompt is logged (never its text), to tell a paste from typing."""

    def test_shape_logged(self):
        s = Session()
        s.prompt("look at this [Pasted text #1 +3 lines] #push")
        e = [x for x in C.ledger(s.sid) if x.get("kind") == "prompt-shape"][-1]
        self.assertIn("[Pasted text #1 +3 lines]", e["markers"])
        self.assertNotIn("look at this", json.dumps(e))


def post(s, tool, ti, resp=None, error=None):
    """PostToolUse (or PostToolUseFailure when error is set) for a call already let through by s.call."""
    d = s.base(tool_name=tool, tool_input=ti)
    if error is None:
        d["tool_response"] = resp
    else:
        d["error"] = error
    C.on_posttool(d)


SHIP_WORK = f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
SCOPE Bash: python3 -I {PROJ}/tests/test_x.py
SCOPE Write: {PROJ}/docs
TASK 1  ship
  REQUIRE File: {{root}}/out/never.md
"""


class JevDigests(unittest.TestCase):
    """HOLES-B D8: Jev is sent each call's result, not only the call, so a true claim is not judged unproven."""

    def test_result_reaches_jev(self):
        j = FakeJev("clean")
        try:
            s = Session()
            s.sign(DONE_WORK)
            cmd = f"python3 -I {PROJ}/tests/test_x.py"
            self.assertEqual(s.call("Bash", command=cmd), "allow")
            post(s, "Bash", {"command": cmd}, {"stdout": "Ran 3 tests in 0.1s\n\nOK", "stderr": "",
                                                "interrupted": False})
            self.assertEqual(s.call("Bash", command="echo hi"), "allow")
            post(s, "Bash", {"command": "echo hi"}, error="Exit code 1\nboom")
            s.stop("Task 1 is done: out/done.md exists; the 3 tests pass.")
            log = j.body["state"]["tool_log"]
            self.assertIn("Ran 3 tests in 0.1s OK", log)
            self.assertIn("FAILED: Exit code 1 boom", log)
        finally:
            j.close()

    def test_digest_is_short_and_redacted(self):
        d = C.result_digest({"stdout": "token=abcdefghijklmnop " + "x" * 5000}, None)
        self.assertLessEqual(len(d), 260)
        self.assertNotIn("abcdefghijklmnop", d)

    def test_failure_event_is_wired(self):
        with open(os.path.join(PLUGIN, "hooks", "hooks.json")) as f:
            self.assertIn("PostToolUseFailure", json.load(f)["hooks"])
        with open(os.path.join(PLUGIN, "lib", "hook.py")) as f:
            self.assertIn('"PostToolUseFailure"', f.read())


class PasteNotOwner(unittest.TestCase):
    """HOLES-B D13: a verb inside text the tools or the agent showed (pasted back) is not the owner's. The real case,
    2026-11-13 01:12: a pasted refusal ending "the owner signs it with #go." signed contract A4."""

    REFUSAL = ("No signed contract (NEGOTIATION). Allowed: reads, the opening's skills and listing lines, and the work "
               "order (/x/proposal.md). Write the work order; the owner signs it with #go.")

    def test_pasted_refusal_does_not_sign(self):
        s = Session()
        s.opening()
        w(C.proposal_path(s.sid), DONE_WORK)
        self.assertNotEqual(s.call("Bash", command="touch /x"), "allow")  # the gate shows the refusal text
        # the terminal wraps the paste: line breaks and indents land mid-sentence
        pasted = ("h(https://example.org/docs/c       li)  Error: PreToolUse hook error: No signed\n     contract "
                  "(NEGOTIATION). Allowed: reads, the opening's\n     skills and listing lines, and the work order "
                  "(/x/proposal.md).\n        Write the work order; the owner signs it with\n     #go.\nWhat is this?")
        out = s.prompt(pasted)
        self.assertNotIn("signed by the owner", out)
        self.assertEqual(C.load_state(s.sid)["phase"], "NEGOTIATION")
        self.assertIn("signed by the owner", s.prompt("#go"))

    def test_pasted_agent_text_does_not_push(self):
        s = Session()
        s.sign(DONE_WORK)
        with open(s.tr, "a") as f:
            f.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "text", "text": "When you are ready, type #push and I send the fixes to GitHub."}]}}) + "\n")
        s.prompt("he said: When you are ready, type #push and I send")
        self.assertFalse(C.load_state(s.sid)["push_ok"])

    def test_typed_verbs_still_count(self):
        self.assertEqual(C.parse_verbs("#go", shown="the owner signs it with #go."), ["go"])
        self.assertEqual(C.parse_verbs("Yeah, I just need to go aftet i #push", shown="type #push"), ["push"])
        self.assertEqual(C.parse_verbs("the owner signs it with #go.", shown="the owner signs it with #go."), [])


class Notices(unittest.TestCase):
    """HOLES-B D14: the same contract-state line is not put in the agent's context on every prompt; it stays in the
    status bar, and comes back to the agent when it changes."""

    def test_state_line_once_until_it_changes(self):
        s = Session()
        self.assertIn("Contract state: ACTIVE", s.sign(DONE_WORK))
        self.assertNotIn("Contract state:", s.prompt("carry on"))
        self.assertNotIn("Contract state:", s.prompt("carry on"))
        self.assertIn("push approved", s.prompt("#push"))
        import statusline
        self.assertIn("push ok", statusline.render({"session_id": s.sid}))

    def test_after_compaction_it_is_said_again(self):
        s = Session()
        s.sign(DONE_WORK)
        s.prompt("carry on")
        C.on_start(s.base(source="compact"))
        self.assertIn("Contract state:", s.prompt("carry on"))


class LiveTestRule(unittest.TestCase):
    """HOLES-B D15: a merge is refused unless this session ran a test after its last change, and the run passed."""

    MERGE = "gh pr merge 5 -R o/r --squash"

    def setUp(self):
        self.s = Session()
        self.s.sign(SHIP_WORK)
        self.s.prompt("#push")

    def test_merge_without_a_run_refused(self):
        self.assertIn("live run", self.s.call("Bash", command=self.MERGE))

    def test_merge_after_a_passing_run_allowed_and_an_edit_voids_it(self):
        s = self.s
        doc = os.path.join(PROJ, "docs", "live.md")
        self.assertEqual(s.call("Write", file_path=doc, content="x"), "allow")
        cmd = f"python3 -I {PROJ}/tests/test_x.py"
        self.assertEqual(s.call("Bash", command=cmd), "allow")
        post(s, "Bash", {"command": cmd}, error="Exit code 1\nFAILED (failures=1)")
        self.assertIn("live run", s.call("Bash", command=self.MERGE))
        self.assertEqual(s.call("Bash", command=cmd), "allow")
        post(s, "Bash", {"command": cmd}, {"stdout": "Ran 2 tests\n\nOK", "stderr": "", "interrupted": False})
        self.assertEqual(s.call("Bash", command=self.MERGE), "allow")
        self.assertEqual(s.call("Write", file_path=doc, content="y"), "allow")
        self.assertIn("live run", s.call("Bash", command=self.MERGE))
        self.assertIn("live run", s.call("Bash", command="gh pr merge 5 -R o/r --auto --squash"))


if __name__ == "__main__":
    print(f"plugin under test: {PLUGIN}")
    unittest.main(verbosity=1)
