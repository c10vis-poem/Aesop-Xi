"""Contract A3 task 1 fixes (2026-11-12). Run: python3 -I tests/test_a3_fixes.py [--root <plugin folder>]
--root tests another copy of the plugin (the installed one) with these same tests."""
import multiprocessing
import os
import sys
import tempfile
import unittest

ROOT_ARG = None
if "--root" in sys.argv:
    i = sys.argv.index("--root")
    ROOT_ARG = sys.argv[i + 1]
    del sys.argv[i:i + 2]
PLUGIN = os.path.realpath(ROOT_ARG or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

TMP = tempfile.mkdtemp(prefix="contract-a3-test-")
os.environ["HOME"] = os.path.join(TMP, "home")
os.environ["CONTRACT_STATE"] = os.path.join(TMP, "home", ".claude", "state")
os.environ["CONTRACT_OWNER_DIR"] = os.path.join(TMP, "owner")
for _k in ("TYPESAFE_API_KEY", "CLAUDE_PLUGIN_OPTION_TYPESAFE_API_KEY", "TYPESAFE_BASE_URL"):
    os.environ.pop(_k, None)  # tests never use the owner's key or the network; the suites below inherit this
sys.path.insert(0, os.path.join(PLUGIN, "lib"))
import contract as C  # noqa: E402

PROJ = os.path.realpath(os.path.join(TMP, "proj"))
HOME = os.environ["HOME"]
H = os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-12")
for d in (os.path.join(PROJ, "docs"), H):
    os.makedirs(d, exist_ok=True)
with open(os.path.join(PROJ, "AGENTS.md"), "w") as f:
    f.write("# agents\n")
with open(os.path.join(H, "handoff.md"), "w") as f:
    f.write("handoff\n")
UNREAD = os.path.join(PROJ, "docs", "fix.md")
with open(UNREAD, "w") as f:
    f.write("a file nobody read\n")


class Session:
    n = 0

    def __init__(self):
        Session.n += 1
        self.sid = f"testa3{Session.n:03d}-0000-0000-0000-000000000000"
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
        resp = {"type": "text", "file": {"filePath": path, "content": text, "startLine": 1,
                                         "numLines": text.count("\n"), "totalLines": text.count("\n")}}
        C.on_pretool(self.base(tool_name="Read", tool_input={"file_path": path}))
        C.on_posttool(self.base(tool_name="Read", tool_input={"file_path": path}, tool_response=resp))

    def call(self, tool, **ti):
        out = C.on_pretool(self.base(tool_name=tool, tool_input=ti))
        return "allow" if out is None else out["hookSpecificOutput"]["permissionDecisionReason"]

    def stop(self, msg="working"):
        out = C.on_stop(self.base(last_assistant_message=msg, stop_hook_active=False))
        return "end" if out is None or out.get("decision") != "block" else out["reason"]

    def sign(self, text):
        self.read(os.path.join(PROJ, "AGENTS.md"))
        self.read(os.path.join(H, "handoff.md"))
        with open(C.proposal_path(self.sid), "w") as f:
            f.write(text)
        return C.on_prompt(self.base(prompt="#go"))["hookSpecificOutput"]["additionalContext"]


WORK = f"""CONTRACT   type: contract   root: {PROJ}
SCOPE Bash: echo
TASK 1  write a report
  REQUIRE File: {{root}}/out/report.md
"""


class StopRepeat(unittest.TestCase):
    """a) The same unmet list is named once, not after every turn."""

    def test_same_list_not_repeated_after_a_tool_call(self):
        s = Session()
        self.assertIn("signed", s.sign(WORK))
        first = s.stop()
        self.assertIn("report.md", first)
        self.assertEqual(s.call("Bash", command="echo hello"), "allow")  # a call adds a ledger line
        self.assertEqual(s.stop(), "end", "the same unmet list was blocked again after a tool call")
        self.assertEqual(s.stop(), "end")

    def test_changed_list_blocks_again(self):
        s = Session()
        s.sign(WORK)
        s.stop()
        miss_before = C.load_state(s.sid)["last_block"]
        st = C.load_state(s.sid)
        st["last_block"] = ["something else"]
        C.save_state(s.sid, st)
        self.assertIn("report.md", s.stop(), "a different unmet list must block")
        self.assertEqual(miss_before, C.load_state(s.sid)["last_block"])


class ReadOnlyIsNotAReadClaim(unittest.TestCase):
    """b) "read-only" is not a claim that a file was read; a real claim still is."""

    def test_read_only_word(self):
        s = Session()
        st = C.load_state(s.sid)
        self.assertEqual(C.claim_check(s.sid, st, f"Rule 8 refuses read-only listing `{UNREAD}`."), [])

    def test_real_claim_still_caught(self):
        s = Session()
        st = C.load_state(s.sid)
        self.assertTrue(C.claim_check(s.sid, st, f"I read `{UNREAD}` in full."))


class ReadOnlyListing(unittest.TestCase):
    """c) Read-only ls, find, wc, grep, stat, diff may look at protected folders; writes stay refused."""

    def check(self, cmd):
        return C.protection("x" * 36, "Bash", {"command": cmd})

    def test_allowed(self):
        p = C.PLUGIN_ROOT
        for cmd in (f'find {p} -name "*.md"', f"grep -n parse {p}/lib/contract.py", f"ls -la {p}",
                    f"wc -l {p}/RULES.md", f"diff {p}/RULES.md {p}/RULES.md", f"stat {p}/RULES.md"):
            self.assertIsNone(self.check(cmd), cmd)

    def test_refused(self):
        p = C.PLUGIN_ROOT
        for cmd in (f"find {p} -delete", f"find {p} -exec rm {{}} +", f"ls {p} > /tmp/x",
                    f"rm {p}/RULES.md", f"sed -i s/a/b/ {p}/RULES.md", f"grep x {p}/RULES.md | tee {p}/y",
                    f"cp /tmp/x {p}/RULES.md", "cat ~/.env", "grep KEY ~/.env"):
            self.assertIsNotNone(self.check(cmd), cmd)


class StateNotReadable(unittest.TestCase):
    """The enforcement state (quiz answers, ledger) is not read, by the Read tool or read-only Bash; the session's
    notes, work order and signed contract copies are."""

    def test_state(self):
        s = Session()
        d = C.sdir(s.sid)
        for p in (os.path.join(d, "state.json"), os.path.join(d, "ledger.jsonl")):
            self.assertIsNotNone(C.protection(s.sid, "Read", {"file_path": p}), p)
            self.assertIsNotNone(C.protection(s.sid, "Bash", {"command": f"grep -n quote {p}"}), p)
        for p in (C.notes_path(s.sid), C.proposal_path(s.sid), os.path.join(d, "contracts", "OPENING.md")):
            self.assertIsNone(C.protection(s.sid, "Read", {"file_path": p}), p)


def _hammer(sid, n):
    for i in range(n):
        st = C.load_state(sid) or {}
        st["k"] = i
        C.save_state(sid, st)


class StateWriteRace(unittest.TestCase):
    """Two hooks at once used to share one temp file name, so one crashed with FileNotFoundError."""

    def test_two_processes_save_at_once(self):
        sid = "race0000-0000-0000-0000-000000000000"
        C.save_state(sid, {"k": 0})
        ctx = multiprocessing.get_context("fork")
        ps = [ctx.Process(target=_hammer, args=(sid, 300)) for _ in range(2)]
        for p in ps:
            p.start()
        for p in ps:
            p.join()
        self.assertEqual([p.exitcode for p in ps], [0, 0])
        self.assertIsNotNone(C.load_state(sid))


class ExistingSuitesStillPass(unittest.TestCase):
    """No regressions: the plugin's own test files pass with these changes (only for the copy that holds them)."""

    def test_existing_suites(self):
        import subprocess
        here = os.path.join(PLUGIN, "tests")
        for name in ("test_contract.py", "test_contract_a.py"):
            p = os.path.join(here, name)
            if not os.path.isfile(p):
                continue
            r = subprocess.run([sys.executable, "-I", p], capture_output=True, text=True, timeout=600)
            self.assertEqual(r.returncode, 0, f"{name} failed:\n{r.stdout[-3000:]}\n{r.stderr[-3000:]}")


if __name__ == "__main__":
    print(f"plugin under test: {PLUGIN}")
    unittest.main(verbosity=1)
