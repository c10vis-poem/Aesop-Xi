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

    def test_split_settings_path(self):
        self.assertIsNotNone(self.prot(f"""python3 -c "open('{HOME}/.cla' + 'ude/settings.json','w').write('x')" """))

    def test_joined_parts(self):
        self.assertIsNotNone(self.prot(f"""python3 -c "import os;open(os.path.join('{HOME}','.claude','settings.json'),'w')" """))

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
                p = {"block": 0.9, "unsure": 0.5, "clean": 0.05}[outer.mode]
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

    def test_key_not_sent_in_output(self):
        out, _ = self.run_stop("block")
        self.assertNotIn("fake-test-key", out)


class PromptShape(unittest.TestCase):
    """3c: the shape of each prompt is logged (never its text), to tell a paste from typing."""

    def test_shape_logged(self):
        s = Session()
        s.prompt("look at this [Pasted text #1 +3 lines] #push")
        e = [x for x in C.ledger(s.sid) if x.get("kind") == "prompt-shape"][-1]
        self.assertIn("[Pasted text #1 +3 lines]", e["markers"])
        self.assertNotIn("look at this", json.dumps(e))


if __name__ == "__main__":
    print(f"plugin under test: {PLUGIN}")
    unittest.main(verbosity=1)
