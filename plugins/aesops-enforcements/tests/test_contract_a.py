"""Contract A changes (2026-11-11). Run: python3 -I tests/test_contract_a.py"""
import json
import os
import sys
import tempfile
import unittest

TMP = tempfile.mkdtemp(prefix="contract-a-test-")
os.environ["HOME"] = os.path.join(TMP, "home")
os.environ["CONTRACT_STATE"] = os.path.join(TMP, "home", ".claude", "state")  # same layout as the device
os.environ["CONTRACT_OWNER_DIR"] = os.path.join(TMP, "owner")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import contract as C  # noqa: E402

ENV = {k: os.environ[k] for k in ("HOME", "CONTRACT_STATE", "CONTRACT_OWNER_DIR")}


def setUpModule():
    """Both test files share one imported contract module: put this file's folders back before its tests."""
    os.environ.update(ENV)
    C.HOME = ENV["HOME"]
    C.STATE = os.path.realpath(ENV["CONTRACT_STATE"])
    C.OWNER_DIR = os.path.realpath(ENV["CONTRACT_OWNER_DIR"])


HOME = os.environ["HOME"]
ROOT = os.path.realpath(os.path.join(TMP, "proj"))
OTHER = os.path.realpath(os.path.join(TMP, "other"))
for d in (os.path.join(ROOT, "docs"), os.path.join(ROOT, "out"), OTHER,
          os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-10"),
          os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-11")):
    os.makedirs(d, exist_ok=True)
DOC = os.path.join(ROOT, "docs", "guide.md")
DOC_TEXT = "\n".join(f"line {i} of the vendor guide, long enough to quote" for i in range(1, 21)) + "\n"
with open(DOC, "w") as f:
    f.write(DOC_TEXT)
with open(os.path.join(ROOT, "AGENTS.md"), "w") as f:
    f.write("# agents\nrule one\n")
with open(os.path.join(OTHER, "RULES.md"), "w") as f:
    f.write("# rules elsewhere\nthe owner's rules live in another repo\n")
OLD_H = os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-10", "handoff.md")
NEW_H = os.path.join(HOME, "repos", "NvAEx-Recaps", "handoff", "2026-11-11", "handoff.md")
for p, t in ((OLD_H, 1000), (NEW_H, 2000)):
    with open(p, "w") as f:
        f.write("handoff\n")
    os.utime(p, (t, t))


class Session:
    n = 0

    def __init__(self):
        Session.n += 1
        self.sid = f"testa{Session.n:03d}-0000-0000-0000-000000000000"
        self.tr = os.path.join(TMP, self.sid + ".jsonl")
        open(self.tr, "w").close()
        C.on_start(self.base(source="startup"))

    def base(self, **kw):
        d = {"session_id": self.sid, "cwd": ROOT, "transcript_path": self.tr}
        d.update(kw)
        return d

    def prompt(self, text):
        return C.on_prompt(self.base(prompt=text))["hookSpecificOutput"]["additionalContext"]

    def call(self, tool, agent=None, extra=None, **ti):
        inp = self.base(tool_name=tool, tool_input=ti, agent_id=agent)
        inp.update(extra or {})
        out = C.on_pretool(inp)
        if out is None:
            C.on_posttool(dict(inp, tool_response={}))
            return "allow"
        return out["hookSpecificOutput"]["permissionDecisionReason"]

    def read(self, path, start=1, num=None, lines=None):
        with open(path) as f:
            disk = f.read().split("\n")
        if disk and disk[-1] == "":
            disk = disk[:-1]
        sel = lines if lines is not None else disk[start - 1:start - 1 + (num or len(disk))]
        resp = {"type": "text", "file": {"filePath": path, "content": "\n".join(sel), "startLine": start,
                                         "numLines": len(sel), "totalLines": len(disk)}}
        r = C.on_pretool(self.base(tool_name="Read", tool_input={"file_path": path}))
        C.on_posttool(self.base(tool_name="Read", tool_input={"file_path": path}, tool_response=resp))
        return "allow" if r is None else r["hookSpecificOutput"]["permissionDecisionReason"]

    def propose(self, text):
        with open(C.proposal_path(self.sid), "w") as f:
            f.write(text)

    def stop(self, msg="done", active=False):
        out = C.on_stop(self.base(last_assistant_message=msg, stop_hook_active=active))
        return "end" if out is None or out.get("decision") != "block" else out["reason"]

    def state(self):
        return C.load_state(self.sid)

    def open_all(self):
        for p in (os.path.join(ROOT, "AGENTS.md"), NEW_H):
            self.read(p)


WORK = f"""CONTRACT   type: contract   project: test   root: {ROOT}
TOOLS   Read, Write, Bash, mcp__plugin_nvaex-memory_dumbass-memory__memory_task
SCOPE   Read: *
SCOPE   Write: {{root}}/out/
SCOPE   Bash: echo
SCOPE   Server: plugin_nvaex-memory_dumbass-memory
TASK 1  read the guide
  REQUIRE Read FULL: {{root}}/docs/guide.md
TASK 2  use memory
  REQUIRE Server: plugin_nvaex-memory_dumbass-memory
TASK 3  report
  REQUIRE File: {{root}}/out/report.md
"""


def signed():
    s = Session()
    s.open_all()
    s.propose(WORK)
    assert "signed" in s.prompt("#go")
    return s


class Opening(unittest.TestCase):
    def test_newest_handoff_required(self):
        # the reminder names the newest handoff only; the stop is never blocked in the opening
        s = Session()
        self.assertEqual(s.stop(), "end")
        left = " ".join(s.state()["opening_unmet"])
        self.assertIn(NEW_H, left)
        self.assertNotIn(OLD_H, left)
        s.open_all()
        s.stop()
        self.assertEqual(s.state()["opening_unmet"], [])

    def test_statusline_shows_opening_reminder(self):
        s = Session()
        s.stop()
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
        import statusline
        self.assertIn("opening:", statusline.render({"session_id": s.sid}))


class SalaryStep(unittest.TestCase):
    """A STEP that is also a GitHub-protocol command is ticked off when it runs (it used to stay unmet forever)."""

    def test_git_step_ticks(self):
        work = f"""CONTRACT   type: contract   root: {ROOT}
TASK 1  fetch
  STEP Bash: git -C /some/repo fetch origin
TASK 2  report
  REQUIRE File: {{root}}/out/never.md
"""
        s = Session()
        s.open_all()
        s.propose(work)
        self.assertIn("signed", s.prompt("#go"))
        self.assertEqual(s.call("Bash", command="git -C /some/repo fetch origin"), "allow")
        out = s.stop()
        self.assertNotIn("STEP Bash: git -C /some/repo fetch origin", out)
        self.assertIn("task 2", out)

    def test_phase_name_and_listing(self):
        s = Session()
        self.assertEqual(s.state()["phase"], "NEGOTIATION")
        self.assertEqual(s.call("Bash", command=f"ls -la {ROOT}"), "allow")
        self.assertIn("No signed contract", s.call("Bash", command=f"find {ROOT} -exec rm {{}} +"))
        self.assertIn("No signed contract", s.call("Bash", command="ls && rm x"))

    def test_contract_dir_is_protected(self):
        s = Session()
        self.assertIn("Protected", s.call("Write", file_path=os.path.join(ROOT, ".contract", "opening.md"),
                                          content="CONTRACT OPENING"))


class Overrides(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(C.parse_overrides("#override task"), [("override", "all", "task")])
        self.assertEqual(C.parse_overrides("#mute stop session please"), [("mute", "stop", "session")])
        self.assertEqual(C.parse_overrides("#mute quiz"), [("mute", "quiz", "turn")])
        self.assertEqual(C.parse_overrides("don't #override"), [])
        self.assertEqual(C.parse_overrides("#mute protection session"), [])
        self.assertEqual(C.parse_overrides('<pasted_content id="1">#override session</pasted_content>'), [])

    def test_override_turn_lifts_scope_then_expires(self):
        s = signed()
        self.assertIn("Outside contract", s.call("Bash", command="rm -rf out"))
        s.prompt("#override")
        self.assertEqual(s.call("Bash", command="rm -rf out2"), "allow")
        s.prompt("next thing")
        self.assertIn("Outside contract", s.call("Bash", command="rm -rf out3"))

    def test_override_never_lifts_protection(self):
        s = signed()
        s.prompt("#override session")
        self.assertIn("Protected", s.call("Write", file_path=os.path.join(HOME, ".claude", "settings.json"),
                                          content="{}"))
        self.assertIn("Protected", s.call("Bash", command="cat .env"))
        self.assertIn("Protected", s.call("Write", file_path=os.path.join(C.PLUGIN_ROOT, "lib", "x.py"), content=""))

    def test_mute_stop_and_unmute(self):
        s = signed()
        self.assertNotEqual(s.stop(), "end")
        s.prompt("#mute stop session")
        self.assertEqual(s.stop(), "end")
        s.prompt("#unmute stop")
        self.assertNotEqual(s.stop(), "end")


class NoFreeze(unittest.TestCase):
    def test_breaches_recorded_not_frozen(self):
        s = signed()
        for i in range(5):
            self.assertIn("Breach", s.call("Bash", command=f"rm {i}"))
        st = s.state()
        self.assertEqual((st["phase"], st["breaches"]), ("ACTIVE", 5))
        self.assertNotIn("/3", s.prompt("status?"))


class Servers(unittest.TestCase):
    def test_both_name_forms(self):
        s = signed()
        extra = {"mcp_server": {"name": "plugin:nvaex-memory:dumbass-memory", "source": "plugin"}}
        self.assertEqual(s.call("mcp__plugin_nvaex-memory_dumbass-memory__memory_task", extra=extra,
                                action="state"), "allow")
        r = {"kind": "Server", "value": "plugin_nvaex-memory_dumbass-memory"}
        self.assertTrue(C.require_met(s.sid, s.state(), r, 0))


class Salary(unittest.TestCase):
    def test_git_dash_c_push_is_held(self):
        s = signed()
        self.assertIn("held until #push", s.call("Bash", command="git -C /some/repo push origin main"))
        self.assertIn("held until #push", s.call("Bash", command="gh -R owner/repo pr merge 4 --squash"))
        self.assertEqual(C.canonical_bash("git -C /x -c a=b push"), "git push")


class Protection(unittest.TestCase):
    def test_path_tricks(self):
        s = signed()
        for cmd in ("ls $HOME/.claude/state", "ls ${HOME}/.claude/state",
                    f"ls {HOME}/.claude/../.claude/state", "wc ~/.claude/./state/x"):
            self.assertIn("Protected", s.call("Bash", command=cmd), cmd)


class ReadProof(unittest.TestCase):
    def test_edit_voids_only_changed_lines(self):
        s = signed()
        s.read(DOC)
        self.assertTrue(C.full_read(s.sid, s.state(), DOC, 0))
        lines = DOC_TEXT.split("\n")
        lines[4] = "line 5 was rewritten by an edit"
        with open(DOC, "w") as f:
            f.write("\n".join(lines))
        got = C.coverage(s.sid, s.state(), DOC, 0)[0]
        self.assertNotIn(5, got)
        self.assertTrue({1, 2, 3, 4, 6, 20} <= got)
        with open(DOC, "w") as f:
            f.write(DOC_TEXT)

    def test_truncated_long_line(self):
        s = signed()
        p = os.path.join(ROOT, "docs", "long.txt")
        long_line = "x" * 3000
        with open(p, "w") as f:
            f.write("short\n" + long_line + "\nend\n")
        s.read(p, lines=["short", long_line[:2000] + "... [truncated]", "end"])
        self.assertTrue(C.full_read(s.sid, s.state(), p, 0))

    def test_binary_read(self):
        s = signed()
        p = os.path.join(ROOT, "docs", "pic.png")
        with open(p, "wb") as f:
            f.write(b"\x89PNG fake")
        C.on_posttool(s.base(tool_name="Read", tool_input={"file_path": p}, tool_response={"type": "image"}))
        self.assertTrue(C.full_read(s.sid, s.state(), p, 0))


class Claims(unittest.TestCase):
    def test_questions_are_not_claims(self):
        s = signed()
        self.assertEqual(C.claim_check(s.sid, s.state(), "Should I read `AGENTS.md` first?"), [])
        self.assertEqual(C.claim_check(s.sid, s.state(), "I'll read `AGENTS.md` next."), [])

    def test_lie_is_caught(self):
        s = signed()
        self.assertTrue(C.claim_check(s.sid, s.state(), "I read `docs/guide.md` and it says so."))
        self.assertTrue(C.claim_check(s.sid, s.state(), f"As {DOC}:7 says, it works."))

    def test_bare_name_read_in_another_repo(self):
        s = signed()
        s.read(os.path.join(OTHER, "RULES.md"))
        self.assertEqual(C.claim_check(s.sid, s.state(), "I read `RULES.md` in full."), [])


class Quiz(unittest.TestCase):
    QW = f"""CONTRACT   type: contract   root: {ROOT}
TOOLS   Read
SCOPE   Read: *
TASK 1  read and prove it
  REQUIRE Read FULL: {{root}}/docs/guide.md
  REQUIRE Quiz: 1
"""

    def quiz_session(self):
        s = Session()
        s.open_all()
        s.propose(self.QW)
        s.prompt("#go")
        s.read(DOC)
        return s

    def test_count_between_3_and_8_drawn_by_hook(self):
        for _ in range(20):
            s = self.quiz_session()
            out = s.stop()
            self.assertIn("quiz: quote lines", out)
            n = len(s.state()["quote"]["lines"])
            self.assertTrue(C.QUIZ_MIN <= n <= C.QUIZ_MAX, n)

    def test_pass_and_taint(self):
        s = self.quiz_session()
        s.stop()
        q = s.state()["quote"]
        self.assertEqual(s.stop(msg="\n".join(q["lines"])), "end")
        s2 = self.quiz_session()
        s2.stop()
        q2 = s2.state()["quote"]
        s2.read(DOC)  # opening the file while the quiz is pending
        self.assertIn("opened while the quiz was pending", s2.stop(msg="\n".join(q2["lines"])))


class StopGate(unittest.TestCase):
    def test_lists_current_task_only_and_pins_a_skipped_line(self):
        s = signed()
        out = s.stop()
        self.assertIn("task 1", out)
        self.assertNotIn("task 3", out)
        # do task 3's work while task 1 is still open: allowed, and task 1 stays the one listed
        self.assertEqual(s.call("Write", file_path=os.path.join(ROOT, "out", "report.md"), content="x"), "allow")
        open(os.path.join(ROOT, "out", "report.md"), "w").close()
        out = s.stop()
        self.assertIn("task 1: REQUIRE Read FULL", out)
        os.remove(os.path.join(ROOT, "out", "report.md"))

    def test_refused_calls_are_reported(self):
        s = signed()
        s.call("Bash", command="rm x")
        self.assertIn("refused this turn", s.stop())

    def test_short_list(self):
        many = WORK.replace("TASK 2", "\n".join(f"  REQUIRE File: {{root}}/out/f{i}.md" for i in range(30))
                            + "\nTASK 2")
        s = Session()
        s.open_all()
        s.propose(many)
        s.prompt("#go")
        out = s.stop()
        self.assertIn("more (status bar)", out)
        self.assertLessEqual(out.count("\n- "), 13)


class Fingerprint(unittest.TestCase):
    """Owner, 2026-11-11: accept git changes, warn on the rest, never lock the owner."""

    def setUp(self):
        import shutil
        import subprocess
        self.run_git = lambda *a: subprocess.run(["git", "-C", self.plug, "-c", "user.name=t",
                                                  "-c", "user.email=t@t", *a], capture_output=True, check=True)
        self.real = C.PLUGIN_ROOT
        self.plug = tempfile.mkdtemp(prefix="plug-", dir=TMP)
        shutil.copytree(os.path.join(self.real, "salary"), os.path.join(self.plug, "salary"))
        self.f = os.path.join(self.plug, "lib.py")
        with open(self.f, "w") as fh:
            fh.write("one\n")
        self.run_git("init", "-q")
        self.run_git("add", "-A")
        self.run_git("commit", "-qm", "one")
        C.PLUGIN_ROOT = self.plug

    def tearDown(self):
        C.PLUGIN_ROOT = self.real

    def test_git_change_is_accepted_silently(self):
        s = signed()
        with open(self.f, "w") as fh:
            fh.write("two\n")
        self.run_git("commit", "-qam", "two")  # the owner's own terminal: no hook sees it
        out = s.prompt("go on")
        self.assertNotIn("changed outside git", out)
        self.assertEqual(s.state()["phase"], "ACTIVE")
        self.assertTrue(any(e.get("kind") == "fp-accept-git" for e in C.ledger(s.sid)))

    def test_other_change_warns_once_never_pauses(self):
        s = signed()
        with open(self.f, "w") as fh:
            fh.write("hand edit\n")
        self.assertEqual(s.call("Bash", command="echo hi"), "allow")  # no pause
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
        import statusline
        self.assertIn("WARN 1 protected", statusline.render({"session_id": s.sid}))
        self.assertIn("changed outside git", s.prompt("go on"))
        self.assertNotIn("changed outside git", s.prompt("and again"))
        self.assertEqual(s.state()["phase"], "ACTIVE")
        self.assertIn("Protected", s.call("Write", file_path=self.f, content="agent write"))

    def test_old_pause_is_lifted(self):
        s = signed()
        st = s.state()
        C._freeze(s.sid, st, ["x"])
        C.save_state(s.sid, st)
        self.assertIn("pause is gone", s.prompt("go on"))
        self.assertEqual(s.state()["phase"], "ACTIVE")


class Handback(unittest.TestCase):
    """Contract C: a sub-agent can hand its report back once its sub-contract is met."""

    def test_refused_until_met_then_allowed(self):
        out_dir = os.path.join(ROOT, "out", "sub")
        os.makedirs(out_dir, exist_ok=True)
        prog = os.path.join(out_dir, "progress.md")
        made = os.path.join(out_dir, "made.md")
        parent = f"""CONTRACT   type: contract   root: {ROOT}
AGENT general-purpose model: opus
SCOPE   Read: *
SCOPE   Write: {{root}}/out/
TASK 1  delegate
  REQUIRE Agent: general-purpose
"""
        s = Session()
        s.open_all()
        s.propose(parent)
        self.assertIn("signed", s.prompt("#go"))
        sub = f"""CONTRACT SUB   type: sub
SCOPE   Write: {out_dir}
TASK 1  make the file
  REQUIRE File: {made}
  REQUIRE Write-to-task: {prog}
"""
        self.assertEqual(s.call("Agent", subagent_type="general-purpose", model="opus",
                                prompt="do it\n\n" + sub), "allow")
        C.on_subagent_start(s.base(agent_type="general-purpose", agent_id="ag1"))
        with open(prog, "w") as f:
            f.write("## Plan\n- [ ] make it\n## Last action\nnow\n## Findings\n-\n## Blocked\nnone\n")
        r = s.call("SubagentHandback", agent="ag1", message="done")
        self.assertIn("not done", r)
        self.assertIn(made, r)
        with open(made, "w") as f:
            f.write("x\n")
        with open(prog, "w") as f:
            f.write("## Plan\n- [x] make it\n## Last action\nnow\n## Findings\nmade it\n## Blocked\nnone\n")
        self.assertEqual(s.call("SubagentHandback", agent="ag1", message="made it"), "allow")


class HookSkip(unittest.TestCase):
    """Contract C: --no-verify / hooksPath are blocked inside git commands only."""

    def test_text_mention_is_not_a_skip(self):
        s = signed()
        self.assertEqual(s.call("Bash", command="echo --no-verify"), "allow")
        self.assertEqual(s.call("Bash", command="echo set hooksPath later"), "allow")

    def test_git_skips_still_blocked(self):
        s = signed()
        for cmd in ("git commit --no-verify -m x", "git -c core.hooksPath=/dev/null commit -m x",
                    "git commit -n -m x", "git commit -an -m x", "git push --no-verify"):
            self.assertIn("Protected", s.call("Bash", command=cmd), cmd)
        self.assertNotIn("Protected", s.call("Bash", command="git commit -m 'add -signing'"))


class StatusLine(unittest.TestCase):
    def test_statusline_prints(self):
        s = signed()
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
        import statusline
        line = statusline.render({"session_id": s.sid})
        self.assertIn("A", line)
        self.assertIn("task 1", line)


if __name__ == "__main__":
    unittest.main()
