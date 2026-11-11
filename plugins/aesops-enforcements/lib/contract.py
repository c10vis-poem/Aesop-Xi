"""Contract enforcement core. Every hook calls one function here; nothing else decides.

A requirement exists only if it is written in a contract the owner signed with #go
(or in a salary template). Every check is a match, a count or a file on disk.
"""
import fnmatch
import glob
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import time
from datetime import datetime

HOME = os.path.expanduser("~")
PLUGIN_ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
STATE = os.path.realpath(os.environ.get("CONTRACT_STATE") or os.path.join(HOME, ".claude", "state"))
OWNER_DIR = os.path.realpath(os.environ.get("CONTRACT_OWNER_DIR")
                             or os.path.join(HOME, "repos", "NvAEx-Recaps", "contracts"))

# Tools that never need a contract: planning and talking, no effect on files or the world.
FREE_TOOLS = {"TodoWrite", "ToolSearch", "AskUserQuestion", "ExitPlanMode"}
PATH_TOOLS = {"Read": "file_path", "Write": "file_path", "Edit": "file_path",
              "NotebookEdit": "notebook_path", "Glob": "path", "Grep": "path"}
WRITE_TOOLS = {"Write", "Edit", "NotebookEdit"}
SHELL_OPS = re.compile(r";|&&|\|\||\||`|\$\(|>|<|\n")
# Phases where no contract is active: the owner and the agent negotiate the work order.
NEGOTIATION = {"NEGOTIATION", "OPENING", "IDLE"}
# Gates the owner can lift (#override) or silence (#mute). Protection is never one of them.
GATES = {"scope", "stop", "claims", "quiz", "opening"}
QUIZ_MIN, QUIZ_MAX = 3, 8
RECON_UNSAFE = re.compile(r"\s-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b")
RNG = random.SystemRandom()


# ---------------------------------------------------------------- paths and state

def sdir(sid):
    return os.path.join(STATE, "contract-" + sid)


def norm(p, root=None):
    if not p:
        return ""
    p = p.replace("{root}", root or "").replace("<root>", root or "")
    p = os.path.expanduser(p)
    if root and not os.path.isabs(p):
        p = os.path.join(root, p)
    return os.path.realpath(p)


def under(path, d):
    return path == d or path.startswith(d.rstrip("/") + "/")


def resolve(val, root):
    """A REQUIRE path; `newest <glob>` picks the most recently changed match (e.g. the newest handoff)."""
    v = val.strip()
    if v.startswith("newest "):
        pat = norm(v[len("newest "):], root)
        hits = [p for p in glob.glob(pat) if os.path.isfile(p)]
        return max(hits, key=os.path.getmtime) if hits else pat
    return norm(v, root)


def line_hash(s):
    return hashlib.sha256(s.rstrip("\r").encode()).hexdigest()[:16]


def now():
    return time.time()


def load_state(sid):
    try:
        with open(os.path.join(sdir(sid), "state.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_state(sid, st):
    d = sdir(sid)
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, ".state.tmp")
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1)
    os.replace(tmp, os.path.join(d, "state.json"))


def log(sid, **e):
    e.setdefault("t", now())
    os.makedirs(sdir(sid), exist_ok=True)
    with open(os.path.join(sdir(sid), "ledger.jsonl"), "a") as f:
        f.write(json.dumps(e) + "\n")


def ledger(sid):
    out = []
    try:
        with open(os.path.join(sdir(sid), "ledger.jsonl")) as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return out


def proposal_path(sid):
    return os.path.join(sdir(sid), "proposal.md")


def notes_path(sid):
    return os.path.join(sdir(sid), "notes.md")


def git_root(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd or ".", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return os.path.realpath(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.realpath(cwd or HOME)


def new_state(sid, cwd):
    return {"phase": "NEGOTIATION", "current": "OPENING", "root": git_root(cwd), "letters": {},
            "redo": None, "push_ok": False, "breaches": 0, "signed_at": now(),
            "compact_at": 0, "hash": None, "limit_hit": False, "spawns": [], "agents": {},
            "quote": None, "quote_passed": [], "last_block": None, "forks": {},
            "overrides": [], "turn_start": now(), "frozen_from": None}


def ensure(sid, cwd):
    st = load_state(sid)
    if st is None:
        st = new_state(sid, cwd)
        open_contract(sid, st, "OPENING", opening_text(st["root"]))
        fp_save(sid)
        save_state(sid, st)
    return st


# ---------------------------------------------------------------- contract format

LINE = re.compile(r"^(STEP|SCOPE|REQUIRE\??|END|TOOLS|SKILLS|AGENT|TASK|CONTRACT)(?=\s|$)\s*(.*)$")
REQ_KINDS = {"Read FULL", "Read FULL+QUOTE", "Read", "Skill", "Agent", "Tool", "Server",
             "File", "Check", "Write-to-task", "Quiz"}
GOAL_KINDS = {"docs", "file", "check", "task"}
LIMIT_KINDS = {"time", "tokens", "share"}


def _split_after(rest):
    after = when = None
    m = re.search(r"\s+when:\s*(\S+)\s*$", rest)
    if m:
        when, rest = m.group(1), rest[:m.start()]
    m = re.search(r"\s+after:\s*(.+?)\s*$", rest)
    if m:
        after, rest = m.group(1), rest[:m.start()]
    return rest.strip(), after, when


def parse(text, root=None):
    """Return (contract dict, list of errors). Lines before the first TASK apply to every task."""
    c = {"header": {}, "global": _task(0, "all tasks"), "tasks": []}
    errs = []
    cur = c["global"]
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("|") or line.startswith("```"):
            continue
        m = LINE.match(line)
        if not m:
            continue  # prose lines are allowed and ignored
        kw, rest = m.group(1), m.group(2).strip()
        if kw == "CONTRACT":
            for k, v in re.findall(r"(\w+):\s*(\S+)", rest):
                c["header"][k] = v
            continue
        if kw == "TASK":
            cur = _task(len(c["tasks"]) + 1, rest)
            c["tasks"].append(cur)
            continue
        if kw in ("TOOLS", "SKILLS"):
            items = [x.strip() for x in re.split(r"[,\s]+", rest) if x.strip()]
            if not items:
                errs.append(f"line {n}: {kw} lists nothing")
            cur["tools" if kw == "TOOLS" else "skills"].extend(items)
            continue
        if kw == "AGENT":
            parts = rest.split()
            if not parts:
                errs.append(f"line {n}: AGENT names no agent type")
                continue
            a = {"type": parts[0], "model": None, "skills": [], "harness": "claude"}
            for k, v in re.findall(r"(model|skills|harness):\s*(\[[^\]]*\]|\S+)", rest):
                a[k] = [s.strip() for s in v.strip("[]").split(",") if s.strip()] if k == "skills" else v
            cur["agents"].append(a)
            continue
        if kw == "END":
            mm = re.match(r"(goal|limit)\s+(\w+):\s*(.+)$", rest)
            if not mm:
                errs.append(f"line {n}: END must be 'END goal <kind>: <value>' or 'END limit <kind>: <value>'")
                continue
            side, kind, val = mm.groups()
            kinds = GOAL_KINDS if side == "goal" else LIMIT_KINDS
            if kind not in kinds:
                errs.append(f"line {n}: END {side} kind '{kind}' unknown (use {', '.join(sorted(kinds))})")
                continue
            if kind == "share":
                errs.append(f"line {n}: END limit share is not measurable by a hook yet; state the budget as time or tokens")
                continue
            if kind == "time" and not re.fullmatch(r"\d+\s*(m|min|h)", val.strip()):
                errs.append(f"line {n}: END limit time needs a number and m or h, e.g. 40m")
                continue
            if kind in ("tokens", "docs", "task") and not val.strip().isdigit():
                errs.append(f"line {n}: END {side} {kind} needs a whole number")
                continue
            cur["end"].append({"side": side, "kind": kind, "value": val.strip(), "line": n})
            continue
        # STEP / SCOPE / REQUIRE
        body, after, when = _split_after(rest)
        mm = re.match(r"([A-Za-z_][\w+\- ]*?):\s*(.+)$", body)
        if not mm:
            errs.append(f"line {n}: {kw} needs '<Kind>: <value>'")
            continue
        kind, val = mm.group(1).strip(), mm.group(2).strip()
        item = {"kind": kind, "value": val, "after": after, "when": when, "line": n,
                "id": f"{kw}@{n}"}
        if kw.startswith("REQUIRE"):
            if kind not in REQ_KINDS:
                errs.append(f"line {n}: REQUIRE kind '{kind}' unknown (use {', '.join(sorted(REQ_KINDS))})")
                continue
            item["optional"] = kw.endswith("?")
            cur["require"].append(item)
        elif kw == "SCOPE":
            if kind in PATH_TOOLS and val != "*" and not norm(val, root):
                errs.append(f"line {n}: SCOPE {kind} has no path")
                continue
            cur["scope"].append(item)
        else:
            cur["step"].append(item)
    if not c["tasks"]:
        c["tasks"] = [c["global"]]
        c["global"] = _task(0, "all tasks")
    for t in c["tasks"][:-1]:
        if not t["step"] and not t["require"]:
            errs.append(f"TASK {t['n']} ({t['title']}) has no STEP or REQUIRE, so it can never close")
    return c, errs


def _task(n, title):
    return {"n": n, "title": title, "tools": [], "skills": [], "agents": [],
            "step": [], "scope": [], "require": [], "end": []}


def opening_text(root):
    p = os.path.join(root, ".contract", "opening.md")
    if not os.path.isfile(p):
        p = os.path.join(PLUGIN_ROOT, "salary", "opening.md")
    with open(p) as f:
        return f.read()


def salary_contracts(root):
    out = []
    try:
        with open(os.path.join(PLUGIN_ROOT, "salary", "ACTIVE")) as f:
            names = [x.strip() for x in f if x.strip() and not x.startswith("#")]
    except OSError:
        names = []
    for n in names:
        try:
            with open(os.path.join(PLUGIN_ROOT, "salary", n + ".md")) as f:
                out.append((n, parse(f.read(), root)[0]))
        except OSError:
            pass
    return out


def contract_file(sid, label):
    return os.path.join(sdir(sid), "contracts", label + ".md")


def load_contract(sid, st, label=None):
    label = label or st["current"]
    try:
        with open(contract_file(sid, label)) as f:
            return parse(f.read(), st["root"])[0]
    except OSError:
        return None


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()


FP_SKIP = {"state.json", ".state.tmp", "ledger.jsonl", "fingerprint.json", "scores.md"}


def fingerprint(sid):
    """sha256 of every protected file: the plugin, this session's contracts, this session's owner copies."""
    out = {}
    for base in (PLUGIN_ROOT, os.path.join(sdir(sid), "contracts"), OWNER_DIR):
        for dp, dn, fn in os.walk(base):
            dn[:] = [d for d in dn if d not in ("__pycache__", ".git")]
            for n in fn:
                if n in FP_SKIP or (base == OWNER_DIR and not n.startswith(sid[:8])):
                    continue
                p = os.path.join(dp, n)
                try:
                    out[p] = sha(p)
                except OSError:
                    pass
    return out


def fp_save(sid):
    os.makedirs(sdir(sid), exist_ok=True)
    with open(os.path.join(sdir(sid), "fingerprint.json"), "w") as f:
        json.dump(fingerprint(sid), f)


def fp_changed(sid):
    """Protected files added, removed or changed since the last fingerprint. A missing fingerprint counts."""
    try:
        with open(os.path.join(sdir(sid), "fingerprint.json")) as f:
            old = json.load(f)
    except (OSError, ValueError):
        return ["fingerprint.json (missing or unreadable)"]
    new = fingerprint(sid)
    return sorted(p for p in set(old) | set(new) if old.get(p) != new.get(p))


def _git_matches_head(path):
    """True when the file on disk is exactly what git's HEAD holds for it (or both lack it): the change came
    through git (commit, merge, pull, switch), whoever ran it, the agent or the owner in his own terminal."""
    try:
        r = subprocess.run(["git", "-C", PLUGIN_ROOT, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode != 0 or not r.stdout.strip():
            return False
        top = os.path.realpath(r.stdout.strip())
        if not under(path, top):
            return False
        r = subprocess.run(["git", "-C", top, "show", "HEAD:" + os.path.relpath(path, top)],
                           capture_output=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return False
    if r.returncode != 0:
        return not os.path.exists(path)  # gone from HEAD and from disk
    try:
        with open(path, "rb") as f:
            return f.read() == r.stdout
    except OSError:
        return False


def fp_review(sid, st):
    """Never pauses the session (owner, 2026-11-11: never lock the owner). Changes that match git's HEAD are
    accepted and logged; any other change is logged, kept in st['fp_warn'] for the status bar and the next
    prompt note, and warned once: the fingerprint is re-taken either way. Agent writes stay refused by
    protection(), which this does not touch. Returns the warned paths."""
    bad = fp_changed(sid)
    if not bad:
        return []
    by_git = [p for p in bad if _git_matches_head(p)]
    other = [p for p in bad if p not in by_git]
    if by_git:
        log(sid, kind="fp-accept-git", files=by_git)
    if other:
        log(sid, kind="fp-warn", files=other)
        st["fp_warn"] = sorted(set(st.get("fp_warn") or []) | set(other))[:20]
    fp_save(sid)
    return other


def open_contract(sid, st, label, text):
    d = os.path.join(sdir(sid), "contracts")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, label + ".md")
    if os.path.exists(p):
        os.chmod(p, 0o644)
    with open(p, "w") as f:
        f.write(text)
    os.chmod(p, 0o444)
    st.update(current=label, hash=sha(p), signed_at=now(), breaches=0, limit_hit=False,
              quote=None, quote_passed=[], last_block=None)
    log(sid, kind="contract", label=label, hash=st["hash"])
    return p


def owner_copy(sid, label, src):
    d = os.path.join(OWNER_DIR, datetime.now().strftime("%Y-%m-%d"))
    try:
        os.makedirs(d, exist_ok=True)
        dst = os.path.join(d, f"{sid[:8]}-{label}.md")
        if os.path.exists(dst):
            os.chmod(dst, 0o644)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o444)
        return dst
    except OSError as e:
        return f"(owner copy failed: {e})"


# ---------------------------------------------------------------- verbs (owner only)

VERBS = [("go", r"#go\b"), ("ok", r"#ok\b"), ("redo", r"#redo\b"),
         ("push", r"#push\b")]
NEG = re.compile(r"\b(don'?t|do not|never|not|no)\b")
SCOPES = ("turn", "task", "session")


def _owner_text(prompt):
    return re.sub(r"<pasted_content[^>]*>.*?</pasted_content>", " ", prompt or "", flags=re.S | re.I)


def parse_verbs(prompt):
    found = []
    for sentence in re.split(r"[.!?;\n]+", _owner_text(prompt).lower()):
        for verb, pat in VERBS:
            m = re.search(pat, sentence)
            if m and not NEG.search(sentence[:m.start()]) and verb not in found:
                found.append(verb)
    return found


def parse_overrides(prompt):
    """Owner-only: `#override [turn|task|session]`, `#mute <gate> [turn|task|session]`, `#unmute <gate|all>`.
    Returns a list of (action, gate, scope). Default scope: turn. Protection is never a gate."""
    out = []
    for sentence in re.split(r"[.!?;\n]+", _owner_text(prompt).lower()):
        for m in re.finditer(r"#(override|mute|unmute)\b((?:\s+[\w-]+){0,2})", sentence):
            if NEG.search(sentence[:m.start()]):
                continue
            words = m.group(2).split()
            act = m.group(1)
            if act == "override":
                scope = words[0] if words and words[0] in SCOPES else "turn"
                out.append(("override", "all", scope))
            elif act == "mute" and words and words[0] in GATES:
                scope = words[1] if len(words) > 1 and words[1] in SCOPES else "turn"
                out.append(("mute", words[0], scope))
            elif act == "unmute" and words and (words[0] in GATES or words[0] == "all"):
                out.append(("unmute", words[0], None))
    return out


def lifted(st, gate, task_n=None):
    """True when the owner lifted this gate (override = every gate) and the lift has not expired."""
    for o in st.get("overrides", []):
        if o["gate"] not in ("all", gate):
            continue
        if o["scope"] == "task" and task_n is not None and o.get("task") not in (None, task_n):
            continue
        return True
    return False


def _expire_overrides(st, task_n=None):
    keep = []
    for o in st.get("overrides", []):
        if o["scope"] == "turn":
            continue  # a turn ends at the next owner prompt
        if o["scope"] == "task" and task_n is not None and o.get("task") is not None and o["task"] != task_n:
            continue
        keep.append(o)
    st["overrides"] = keep


def next_letter(st):
    used = sorted(st["letters"])
    if not used:
        return "A"
    last = used[-1]
    return chr(ord(last) + 1) if last != "Z" else "Z" + str(len(used))


def on_prompt(inp):
    sid = inp.get("session_id", "")
    st = ensure(sid, inp.get("cwd"))
    verbs = parse_verbs(inp.get("prompt", ""))
    notes = []
    fp_review(sid, st)
    warned = st.pop("fp_warn", None) or []
    if st["phase"] == "FROZEN" and st.get("frozen_from"):
        st["phase"], st["frozen_from"] = st["frozen_from"], None  # an old fingerprint pause: lifted
        notes.append("The fingerprint pause is gone (protected-file changes now only warn); the session continues.")
    st["turn_start"] = now()
    task_n = _task_number(sid, st)
    _expire_overrides(st, task_n)
    for act, gate, scope in parse_overrides(inp.get("prompt", "")):
        log(sid, kind="override", action=act, gate=gate, scope=scope)
        if act == "unmute":
            st["overrides"] = [o for o in st["overrides"] if gate != "all" and o["gate"] != gate]
            notes.append(f"Owner: {gate} gate back on.")
        else:
            st["overrides"].append({"gate": gate, "scope": scope, "task": task_n if scope == "task" else None,
                                    "t": now()})
            notes.append(f"Owner: {'every working gate' if gate == 'all' else gate + ' gate'} lifted for this "
                         f"{scope}. Protection stays on.")
    letter = st["current"].rstrip("0123456789") if st["current"] != "OPENING" else None
    for v in verbs:
        log(sid, kind="verb", verb=v)
    if "ok" in verbs and letter and st["phase"] in ("ACTIVE", "DONE", "FROZEN"):
        st["letters"][letter]["status"] = "accepted"
        st["phase"] = "NEGOTIATION"
        runs = st["letters"][letter]["runs"]
        _score(st, letter, f"accepted at {st['current']} after {runs} run(s)")
        notes.append(f"Contract {st['current']} accepted by the owner. Next signed contract gets a new letter.")
    if "redo" in verbs and letter and st["phase"] in ("ACTIVE", "DONE", "FROZEN"):
        st["redo"] = letter
        st["phase"] = "NEGOTIATION"
        notes.append(f"Contract {st['current']} sent back by the owner (#redo). Write the revised work order to "
                     f"{proposal_path(sid)}; when signed it becomes the next numbered run of {letter}.")
    if "go" in verbs:
        notes.append(_sign(sid, st))
    if "push" in verbs:
        st["push_ok"] = True
        notes.append("The owner approved the push (#push): lines held 'after: #push' are now open.")
    if st.get("stopped_unmet"):
        notes.append("Last turn ended with requirements unmet: " + "; ".join(st.pop("stopped_unmet")))
    if warned:
        notes.append("Protected files changed outside git (not paused, warned once): " + ", ".join(warned[:10]))
    fp_save(sid)  # takes in what this prompt itself wrote (a signed contract, its owner copy)
    save_state(sid, st)
    notes.append(status_line(sid, st))
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                   "additionalContext": "\n".join(n for n in notes if n)}}


def _sign(sid, st):
    pp = proposal_path(sid)
    if not os.path.isfile(pp):
        return f"#go received, but there is no work order at {pp} to sign. Nothing was signed."
    with open(pp) as f:
        text = f.read()
    c, errs = parse(text, st["root"])
    if errs:
        return "#go received, but the work order did not pass the format check, so nothing was signed:\n- " + "\n- ".join(errs)
    if st["redo"]:
        L = st["redo"]
        info = st["letters"][L]
        info["runs"] += 1
        if info["runs"] == 2 and os.path.exists(contract_file(sid, L)):
            _rename_run(sid, L, L + "1")
        label = f"{L}{info['runs']}"
        st["redo"] = None
    else:
        L = next_letter(st)
        st["letters"][L] = {"runs": 1, "status": "open"}
        label = L
    if "root" in c["header"]:
        st["root"] = norm(c["header"]["root"])
    p = open_contract(sid, st, label, text)
    os.remove(pp)
    st["phase"] = "ACTIVE"
    copy = owner_copy(sid, label, p)
    return (f"Contract {label} signed by the owner (#go). sha256 {st['hash'][:16]}. "
            f"State copy {p} (read-only); owner copy {copy}. {summary(c)}")


def _rename_run(sid, old, new):
    d = os.path.join(sdir(sid), "contracts")
    os.rename(os.path.join(d, old + ".md"), os.path.join(d, new + ".md"))
    day = os.path.join(OWNER_DIR, datetime.now().strftime("%Y-%m-%d"))
    o = os.path.join(day, f"{sid[:8]}-{old}.md")
    if os.path.exists(o):
        os.rename(o, os.path.join(day, f"{sid[:8]}-{new}.md"))
    log(sid, kind="rename", old=old, new=new)


def _score(st, letter, text):
    proj = st["root"]
    try:
        os.makedirs(OWNER_DIR, exist_ok=True)
        with open(os.path.join(OWNER_DIR, "scores.md"), "a") as f:
            f.write(f"- {datetime.now():%Y-%m-%d %H:%M} {os.path.basename(proj)} {letter}: {text}\n")
    except OSError:
        pass


def summary(c):
    parts = []
    for t in c["tasks"]:
        parts.append(f"task {t['n']}: {len(t['step'])} step, {len(t['scope'])} scope, "
                     f"{len(t['require'])} require, {len(t['end'])} end")
    return "Parsed " + "; ".join(parts) + "."


def status_line(sid, st):
    """One short line for the agent. The full picture (unmet lines, breaches, overrides) is in the status bar."""
    if st["phase"] in NEGOTIATION:
        return (f"Contract state: {st['phase']} (no signed contract). Work order: {proposal_path(sid)}; "
                f"notes: {notes_path(sid)}.")
    n = _task_number(sid, st)
    return (f"Contract state: {st['phase']}, contract {st['current']}" + (f", task {n}" if n else "")
            + f", push {'approved' if st['push_ok'] else 'held'}.")


def _task_number(sid, st):
    if st["phase"] in NEGOTIATION:
        return None
    c = load_contract(sid, st)
    if not c:
        return None
    return current_task(sid, st, c, st["current"], st["signed_at"])[0] + 1


def _freeze(sid, st, bad):
    if st["phase"] != "FROZEN":
        st["frozen_from"] = st["phase"]
    st["phase"] = "FROZEN"
    log(sid, kind="tamper", files=bad)


# ---------------------------------------------------------------- session start

def on_start(inp):
    sid = inp.get("session_id", "")
    st = load_state(sid)
    if inp.get("source") == "compact" and st:
        st["compact_at"] = now()
        save_state(sid, st)
        log(sid, kind="compact")
        return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext":
                "Context was compacted: every read made before now no longer counts toward a REQUIRE Read. "
                + status_line(sid, st)}}
    if st is None:
        st = new_state(sid, inp.get("cwd"))
        open_contract(sid, st, "OPENING", opening_text(st["root"]))
        save_state(sid, st)
    if not os.path.exists(os.path.join(sdir(sid), "fingerprint.json")):
        fp_save(sid)
    c = load_contract(sid, st, "OPENING")
    req = [f"{r['kind']}: {resolve(r['value'], st['root'])}" + (" (if it exists)" if r.get("optional") else "")
           for t in c["tasks"] + [c["global"]] for r in t["require"]]
    allowed = [f"{s['kind']}: {s['value']}" for t in c["tasks"] + [c["global"]] for s in t["scope"] + t["step"]]
    msg = ("The session is in NEGOTIATION (contract negotiation). Allowed until the owner signs a work order with "
           "#go: the Read tool, the skills the opening names, writing notes and the work order"
           + (", and " + ", ".join(allowed) if allowed else "") + ". Opening reads: "
           + ("; ".join(req) or "none") + ". Documents these point to may be read too. " + status_line(sid, st))
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg}}


# ---------------------------------------------------------------- protection (always on)

def protected_paths(sid):
    return [STATE, PLUGIN_ROOT, OWNER_DIR, os.path.join(HOME, ".claude", "settings.json"),
            os.path.join(HOME, ".claude", "settings.local.json"), os.path.join(HOME, ".claude.json"),
            os.path.join(HOME, ".gemini", "settings.json")]


SETTINGS_RE = re.compile(r"(^|/)\.(claude|gemini)/settings(\.local)?\.json$")
SECRET_FILE = re.compile(r"(^|/)(\.env(\..*)?|.*\.pem|.*\.key|id_rsa.*|id_ed25519.*|credentials.*|secrets?(\.enc)?\.ya?ml)$")
SECRET_BASH = re.compile(r"\b(cat|less|more|head|tail|bat|strings|xxd|od|base64)\b[^\n]*"
                         r"(\.env\b|\.pem\b|\.key\b|id_rsa|id_ed25519|credentials|secrets?(\.enc)?\.ya?ml)"
                         r"|\bsops\s+(-d|--decrypt)\b|\bprintenv\b|--no-verify\b|hooksPath")


CONTRACT_DIR = re.compile(r"(^|/)\.contract(/|$)")
PATHISH = re.compile(r"""[^\s'"=:,()\[\]{}]*/[^\s'"=:,()\[\]{}]*""")


def _cmd_paths(cmd):
    """Every path-like token of a command, with ~, $HOME and ${HOME} expanded and .. and symlinks resolved."""
    text = cmd.replace("${HOME}", HOME).replace("$HOME", HOME)
    out = []
    for tok in PATHISH.findall(text):
        tok = tok.strip("'\"")
        if tok.startswith("~"):
            tok = os.path.expanduser(tok)
        if tok.startswith("/"):
            out.append(os.path.realpath(tok))
    return out


def _protected_hit(sid, path):
    return SETTINGS_RE.search(path) or CONTRACT_DIR.search(path) or any(under(path, d) for d in protected_paths(sid))


def protection(sid, tool, ti):
    allowed_writes = {proposal_path(sid), notes_path(sid)}
    if tool in WRITE_TOOLS:
        p = norm(ti.get(PATH_TOOLS[tool], ""))
        if p in allowed_writes:
            return None
        if _protected_hit(sid, p):
            return f"Protected path: {p} is enforcement state, settings, an opening file or the enforcement plugin. Only the owner changes it."
    if tool == "Read":
        p = norm(ti.get("file_path", ""))
        if SECRET_FILE.search(p):
            return f"Protected: {p} looks like a secret file. Reading it would put the secret in the transcript."
    if tool == "Bash" or tool.startswith("mcp__"):
        cmd = ti.get("command", "") if tool == "Bash" else json.dumps(ti)
        if SECRET_BASH.search(cmd):
            return "Protected: this command prints secrets or skips or reroutes git hooks."
        for d in protected_paths(sid):
            if d in cmd or d.replace(HOME, "~") in cmd:
                return f"Protected: the command touches {d.replace(HOME, '~')}. Use the Read tool to look; only the owner changes it."
        for p in _cmd_paths(cmd):
            if _protected_hit(sid, p):
                return f"Protected: the command touches {p.replace(HOME, '~')}. Use the Read tool to look; only the owner changes it."
        if SETTINGS_RE.search(cmd) or re.search(r"\.(claude|gemini)/settings", cmd):
            return "Protected: the command touches a settings file. Only the owner changes settings."
    return None


# ---------------------------------------------------------------- matching

def primary(tool, ti):
    if tool == "Bash":
        return ti.get("command", "").strip()
    if tool in PATH_TOOLS:
        return ti.get(PATH_TOOLS[tool]) or ti.get("cwd") or ""
    if tool == "Skill":
        return ti.get("skill", "")
    if tool in ("Agent", "Task"):
        return ti.get("subagent_type", "general-purpose")
    if tool == "WebFetch":
        return ti.get("url", "")
    if tool == "WebSearch":
        return ti.get("query", "")
    return json.dumps(ti, sort_keys=True)


def server_names(tool, inp):
    """Every name a contract may use for an MCP server: the tool-name segment (`plugin_x_y`, `claude_ai_Supabase`),
    the hook input's `mcp_server.name`, and its `plugin:x:y` form folded to `plugin_x_y`."""
    names = set()
    if tool.startswith("mcp__"):
        names.add(tool.split("__")[1])
    s = (inp.get("mcp_server") or {}).get("name")
    if s:
        names.add(s)
        names.add(s.replace(":", "_"))
        names.add(s.split(":")[-1])
    return names


def server_of(tool, inp):
    if tool.startswith("mcp__"):
        return tool.split("__")[1]
    return (inp.get("mcp_server") or {}).get("name")


def tool_listed(tool, inp, names):
    srvs = server_names(tool, inp)
    for n in names:
        if n == tool or fnmatch.fnmatch(tool, n):
            return True
        bare = n[len("server:"):] if n.startswith("server:") else n.rstrip(":")
        if bare in srvs:
            return True
    return False


GIT_GLOBAL = re.compile(r"^(git)((?:\s+(?:-C\s+\S+|-c\s+\S+|--git-dir=\S+|--work-tree=\S+|--no-pager))+)(\s|$)")
GH_REPO = re.compile(r"\s(?:-R|--repo)(?:\s+|=)\S+")


def canonical_bash(cmd):
    """`git -C x push` -> `git push`; `gh -R o/r pr merge` -> `gh pr merge`: so salary holds see the real verb."""
    c = GIT_GLOBAL.sub(r"\1\3", cmd.strip(), count=1)
    if c.startswith("gh "):
        c = GH_REPO.sub("", c)
    return c


def after_met(sid, st, item, root):
    if item.get("when") == "fork" and not _is_fork(st, root):
        return True, None  # the hold applies to forks only
    a = item.get("after")
    if a and not _event_met(sid, st, a):
        return False, a
    return True, None


def _event_met(sid, st, a):
    a = a.strip()
    if a == "#push":
        return st.get("push_ok", False)
    m = re.match(r"(\w+):\s*(.+)$", a)
    if not m:
        return False
    tool, val = m.groups()
    for e in ledger(sid):
        if e.get("kind") == "call" and e.get("tool") == tool and str(e.get("key", "")).startswith(val):
            return True
    return False


def _is_fork(st, root):
    if root in st["forks"]:
        return st["forks"][root]
    try:
        r = subprocess.run(["gh", "repo", "view", "--json", "isFork", "--jq", ".isFork"], cwd=root,
                           capture_output=True, text=True, timeout=5)
        v = r.stdout.strip() == "true"
    except (OSError, subprocess.SubprocessError):
        v = False
    st["forks"][root] = v
    return v


def line_matches(tool, inp, item, root, exact):
    kind, val = item["kind"], item["value"]
    if kind == "Server":
        srvs = server_names(tool, inp)
        return bool(srvs) and (val == "*" or val in srvs)
    if kind != tool and not fnmatch.fnmatch(tool, kind):
        return False
    if val == "*":
        return True
    key = primary(tool, inp.get("tool_input", {}))
    if tool in PATH_TOOLS:
        p, v = norm(key, root), norm(val, root)
        return p == v if exact else under(p, v)
    if tool == "Bash":
        if exact:
            return key == val
        return (key == val or key.startswith(val + " ")) and not SHELL_OPS.search(key)
    if tool.startswith("mcp__") and exact:
        try:
            return json.loads(val) == inp.get("tool_input", {})
        except ValueError:
            return False
    return key == val if exact else key.startswith(val)


def used_steps(sid, label):
    return {e.get("step") for e in ledger(sid) if e.get("kind") == "call" and e.get("label") == label and e.get("step")}


# ---------------------------------------------------------------- requirement checks

def coverage(sid, st, path, since, agent=None):
    """Lines of `path` proven read since `since`. A line counts when its current text was returned by a Read
    (line hash), so an edit voids only the lines it changed. `agent` None = the main session's own reads only."""
    try:
        cur = sha(path)
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
    except OSError:
        return set(), 0, None
    total = len(lines)
    since = max(since, st.get("compact_at", 0), st.get("void", {}).get(path, 0))  # a failed round voids its reads
    got, seen = set(), set()
    for e in ledger(sid):
        if e.get("kind") != "read" or e.get("path") != path or e["t"] < since or e.get("agent") != agent:
            continue
        if e.get("binary"):
            if e.get("sha") == cur:
                got.update(range(1, total + 1))
            continue
        if "hashes" in e:
            seen.update(e["hashes"])
        elif e.get("sha") == cur:
            for a, b in e.get("ranges", []):
                got.update(range(a, b + 1))
    if seen:
        got.update(i for i, x in enumerate(lines, 1) if line_hash(x) in seen)
    return got, total, cur


def full_read(sid, st, path, since, agent=None):
    got, total, _ = coverage(sid, st, path, since, agent)
    lines = _real_line_count(path)
    return total > 0 and all(i in got for i in range(1, lines + 1))


def _real_line_count(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return 0
    n = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
    return max(n, 1) if text else 0


def require_met(sid, st, r, since, agent=None):
    kind, root = r["kind"], st["root"]
    val = r["value"]
    calls = [e for e in ledger(sid) if e["t"] >= since and e.get("agent") == agent]
    if kind in ("Read FULL", "Read FULL+QUOTE", "Read"):
        p = resolve(val, root)
        if r.get("optional") and not os.path.exists(p):
            return True
        if kind == "Read":
            return bool(coverage(sid, st, p, since, agent)[0])
        if not full_read(sid, st, p, since, agent):
            return False
        return kind == "Read FULL" or p in st.get("quote_passed", [])
    if kind == "Skill":
        return any(e.get("kind") == "skill" and e.get("name", "").split(":")[-1] == val.split(":")[-1]
                   for e in calls)
    if kind == "Agent":
        return any(e.get("kind") == "agent" and e.get("type") == val for e in calls)
    if kind == "Tool":
        return any(e.get("kind") == "call" and e.get("tool") == val for e in calls)
    if kind == "Server":
        return any(e.get("kind") == "call" and (e.get("server") == val or val in (e.get("servers") or []))
                   for e in calls)
    if kind == "File":
        return os.path.exists(norm(val, root))
    if kind == "Check":
        return run_check(val, root)
    if kind == "Write-to-task":
        return progress_ok(norm(val, root))[0]
    return False


def run_check(cmd, root):
    try:
        return subprocess.run(cmd, shell=True, cwd=root, capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def task_open(sid, st, task, label, since, agent=None):
    """A task is closed when all its REQUIRE lines are met and all its STEP lines were used."""
    used = used_steps(sid, label)
    missing = [f"STEP {s['kind']}: {s['value']}" for s in task["step"] if s["id"] not in used]
    missing += [f"REQUIRE {r['kind']}: {r['value']}" for r in task["require"]
                if r["kind"] != "Quiz" and not require_met(sid, st, r, since, agent)]
    for r in task["require"]:
        if r["kind"] == "Quiz":
            paths = [norm(x["value"], st["root"]) for x in task["require"] if x["kind"].startswith("Read FULL")]
            done = len([p for p in paths if p in st.get("quote_passed", [])])
            if done < int(r["value"]):
                missing.append(f"REQUIRE Quiz: {done} of {r['value']} passed")
    return missing


def current_task(sid, st, c, label, since, agent=None):
    for i, t in enumerate(c["tasks"]):
        if i == len(c["tasks"]) - 1 or task_open(sid, st, t, label, since, agent):
            return i, t
    return len(c["tasks"]) - 1, c["tasks"][-1]


def limits(sid, st, c, transcript):
    for t in [c["global"]] + c["tasks"]:
        for e in t["end"]:
            if e["side"] != "limit":
                continue
            if e["kind"] == "time":
                n = int(re.match(r"\d+", e["value"]).group())
                secs = n * 3600 if e["value"].strip().endswith("h") else n * 60
                if now() - st["signed_at"] >= secs:
                    return f"time limit {e['value']} reached"
            if e["kind"] == "tokens" and tokens_since(transcript, st["signed_at"]) >= int(e["value"]):
                return f"token limit {e['value']} reached"
    return None


def tokens_since(transcript, since):
    total = 0
    try:
        with open(transcript) as f:
            for line in f:
                try:
                    j = json.loads(line)
                except ValueError:
                    continue
                if j.get("type") != "assistant":
                    continue
                ts = j.get("timestamp")
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() if ts else 0
                except ValueError:
                    t = 0
                if t < since:
                    continue
                u = j.get("message", {}).get("usage", {})
                total += u.get("input_tokens", 0) + u.get("output_tokens", 0) + u.get("cache_creation_input_tokens", 0)
    except OSError:
        pass
    return total


def goals_missing(sid, st, c, since):
    miss = []
    for t in [c["global"]] + c["tasks"]:
        for e in t["end"]:
            if e["side"] != "goal":
                continue
            k, v = e["kind"], e["value"]
            if k == "file" and not os.path.exists(norm(v, st["root"])):
                miss.append(f"END goal file: {v} does not exist")
            elif k == "check" and not run_check(v, st["root"]):
                miss.append(f"END goal check: {v} does not pass")
            elif k == "docs":
                n = len({e2["path"] for e2 in ledger(sid) if e2.get("kind") == "read" and e2["t"] >= since
                         and full_read(sid, st, e2["path"], since)})
                if n < int(v):
                    miss.append(f"END goal docs: {n} of {v} documents read in full")
            elif k == "task":
                i, _ = current_task(sid, st, c, st["current"], since)
                if i + 1 < int(v):
                    miss.append(f"END goal task: task {v} not reached (on task {i + 1})")
    return miss


def progress_ok(path):
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return False, f"progress file {path} does not exist"
    for h in ("## Plan", "## Last action", "## Findings", "## Blocked"):
        if h not in text:
            return False, f"progress file {path} lacks '{h}'"
    plan = text.split("## Plan", 1)[1].split("\n## ", 1)[0]
    blocked = text.split("## Blocked", 1)[1].split("\n## ", 1)[0].strip()
    if "- [ ]" in plan and (not blocked or blocked.lower() in ("none", "-", "nothing")):
        return False, f"progress file {path} has unchecked Plan items and nothing under Blocked"
    return True, ""


# ---------------------------------------------------------------- the gate (PreToolUse)

def deny(reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def on_pretool(inp):
    sid = inp.get("session_id", "")
    st = ensure(sid, inp.get("cwd"))
    tool, ti = inp.get("tool_name", ""), inp.get("tool_input", {}) or {}
    agent = inp.get("agent_id")
    if fp_review(sid, st):
        save_state(sid, st)
    r = protection(sid, tool, ti)
    if r:
        return _deny(sid, st, tool, ti, agent, r, count=st["phase"] == "ACTIVE")
    _quiz_taint(sid, st, tool, ti)
    if tool == "Read":
        if norm(ti.get("file_path", "")) in (proposal_path(sid), notes_path(sid)):
            return None
    if st["phase"] == "DONE":
        if tool == "Read":
            return None
        return _deny(sid, st, tool, ti, agent, f"Contract {st['current']} waits for the owner's #ok or #redo. "
                     "Only reads, to show the owner the results, until then.", count=False)
    if tool in FREE_TOOLS:
        return None
    if tool in WRITE_TOOLS and norm(ti.get(PATH_TOOLS[tool], "")) in (proposal_path(sid), notes_path(sid)):
        return None
    # salary templates (pre-signed, always in force). Bash is matched as written and in canonical form, so
    # `git -C x push` meets the same #push hold as `git push`.
    for name, sc in salary_contracts(st["root"]):
        for t in sc["tasks"] + [sc["global"]]:
            for item in t["scope"] + t["step"]:
                exact = item in t["step"]
                hit = line_matches(tool, inp, item, st["root"], exact=exact)
                if not hit and tool == "Bash":
                    canon = dict(inp, tool_input=dict(ti, command=canonical_bash(ti.get("command", ""))))
                    hit = line_matches(tool, canon, item, st["root"], exact=exact)
                if hit:
                    ok, need = after_met(sid, st, item, st["root"])
                    save_state(sid, st)
                    if ok:
                        _allow(sid, st, tool, ti, agent, inp=inp, label="salary:" + name)
                        return None
                    return _deny(sid, st, tool, ti, agent,
                                 f"Salary protocol {name}: '{item['kind']}: {item['value']}' is held until {need}.",
                                 count=False)
    if agent and agent in st["agents"]:
        return _sub_gate(sid, st, inp, tool, ti, agent)
    phase = st["phase"]
    if phase in NEGOTIATION:
        c = load_contract(sid, st, "OPENING")
        skills = [s for t in c["tasks"] + [c["global"]] for s in t["skills"]]
        if tool == "Read" or (tool == "Skill" and tool_skill(ti) in [s.split(":")[-1] for s in skills]):
            return None
        # Project Recon: the opening's own SCOPE and STEP lines (read-only listing by default)
        for t in c["tasks"] + [c["global"]]:
            for item in t["scope"] + t["step"]:
                if line_matches(tool, inp, item, st["root"], exact=item in t["step"]) \
                        and not (tool == "Bash" and RECON_UNSAFE.search(ti.get("command", ""))):
                    _allow(sid, st, tool, ti, agent, inp=inp, label="OPENING")
                    return None
        if lifted(st, "scope"):
            _allow(sid, st, tool, ti, agent, inp=inp, label="OPENING", override=True)
            return None
        return _deny(sid, st, tool, ti, agent,
                     f"No signed contract ({phase}). Allowed: reads, the opening's skills and listing lines, and "
                     f"the work order ({proposal_path(sid)}). Write the work order; the owner signs it with #go.",
                     count=False)
    if phase == "FROZEN" and tool == "Read":
        return None
    if phase == "FROZEN":
        return _deny(sid, st, tool, ti, agent, f"Contract {st['current']} is paused: protected files changed. "
                     "The owner re-fingerprints the session to continue.", count=False)
    c = load_contract(sid, st)
    if c is None:
        return _deny(sid, st, tool, ti, agent, "The signed contract file is missing.", count=False)
    hit = limits(sid, st, c, inp.get("transcript_path", ""))
    if hit:
        st["limit_hit"] = hit
        save_state(sid, st)
        return _deny(sid, st, tool, ti, agent, f"Hard limit: {hit}. No more calls; write the closing report and "
                     "name everything not done.", count=False)
    return _contract_gate(sid, st, c, inp, tool, ti, st["current"], st["signed_at"], agent)


def tool_skill(ti):
    return (ti.get("skill") or "").split(":")[-1]


def _union(c):
    """Every task's lines plus the global ones: a call that fits any task is allowed at any time. Order is kept
    for sign-off only: the first task with an unmet line stays the current task until that line is met."""
    u = _task(0, "union")
    for t in [c["global"]] + c["tasks"]:
        for k in ("tools", "skills", "agents", "step", "scope"):
            u[k] = u[k] + t[k]
    return u


def _contract_gate(sid, st, c, inp, tool, ti, label, since, agent):
    root = st["root"]
    i, _task_now = current_task(sid, st, c, label, since, agent)
    u = _union(c)
    g = c["global"]
    tools = u["tools"]
    if tools and not tool_listed(tool, inp, tools):
        return _gate_deny(sid, st, tool, ti, agent, inp, label, i,
                          f"Contract {label}: {tool} is not in TOOLS ({', '.join(tools)}).")
    if tool == "Skill":
        skills = [s.split(":")[-1] for s in u["skills"]]
        if tool_skill(ti) not in skills:
            return _gate_deny(sid, st, tool, ti, agent, inp, label, i,
                              f"Contract {label}: skill {tool_skill(ti)} is not in SKILLS ({', '.join(skills) or 'none'}).")
        _allow(sid, st, tool, ti, agent, inp=inp, label=label, task=i + 1)
        return None
    if tool in ("Agent", "Task"):
        return _spawn(sid, st, c, u, g, inp, tool, ti, label, i, agent)
    used = used_steps(sid, label)
    for s in u["step"]:
        if s["id"] not in used and line_matches(tool, inp, s, root, exact=True):
            ok, need = after_met(sid, st, s, root)
            if not ok:
                return _deny(sid, st, tool, ti, agent, f"STEP held until {need}.")
            _allow(sid, st, tool, ti, agent, inp=inp, label=label, task=i + 1, step=s["id"])
            return None
    for s in u["scope"]:
        if line_matches(tool, inp, s, root, exact=False):
            ok, need = after_met(sid, st, s, root)
            if not ok:
                return _deny(sid, st, tool, ti, agent, f"SCOPE held until {need}.")
            _allow(sid, st, tool, ti, agent, inp=inp, label=label, task=i + 1)
            return None
    if tools and tool_listed(tool, inp, tools) and not u["step"] and not u["scope"]:
        _allow(sid, st, tool, ti, agent, inp=inp, label=label, task=i + 1)
        return None
    key = primary(tool, ti)
    if tool == "Bash" and SHELL_OPS.search(key):
        why = " (the command holds | ; & < > ` or $( somewhere, even in quotes: write it as a script, or as an exact STEP)"
    else:
        why = ""
    return _gate_deny(sid, st, tool, ti, agent, inp, label, i, f"Outside contract {label}: {tool} {key[:160]}{why}.")


def _gate_deny(sid, st, tool, ti, agent, inp, label, i, reason):
    """A scope refusal, unless the owner lifted the scope gate (#override / #mute scope)."""
    if lifted(st, "scope", i + 1):
        _allow(sid, st, tool, ti, agent, inp=inp, label=label, task=i + 1, override=True)
        return None
    return _deny(sid, st, tool, ti, agent, reason)


def _spawn(sid, st, c, task, g, inp, tool, ti, label, i, agent):
    agents = task["agents"] + g["agents"]
    typ = ti.get("subagent_type", "general-purpose")
    match = [a for a in agents if a["type"] == typ]
    if not match:
        return _deny(sid, st, tool, ti, agent, f"Contract {label} task {i + 1}: no AGENT line for {typ}.")
    a = match[0]
    if a.get("model") and ti.get("model") != a["model"]:
        return _deny(sid, st, tool, ti, agent, f"AGENT {typ} must run with model {a['model']}.")
    if a.get("harness", "claude") != "claude":
        return _deny(sid, st, tool, ti, agent, f"AGENT {typ} runs on harness {a['harness']}: start it with its "
                     "exact Bash STEP, not the Agent tool.")
    prompt = ti.get("prompt", "")
    m = re.search(r"(?ms)^CONTRACT\b.*", prompt)
    if not m:
        return _deny(sid, st, tool, ti, agent, "The spawn prompt carries no sub-contract (a CONTRACT block with "
                     "STEP/SCOPE/REQUIRE/END and REQUIRE Write-to-task).")
    sub, errs = parse(m.group(0), st["root"])
    if errs:
        return _deny(sid, st, tool, ti, agent, "Sub-contract format errors: " + "; ".join(errs))
    if not any(r["kind"] == "Write-to-task" for t in sub["tasks"] + [sub["global"]] for r in t["require"]):
        return _deny(sid, st, tool, ti, agent, "The sub-contract has no REQUIRE Write-to-task: <progress file>.")
    parent = task["scope"] + g["scope"]
    for t in sub["tasks"] + [sub["global"]]:
        for s in t["scope"]:
            if not any(_scope_within(s, p, st["root"]) for p in parent):
                return _deny(sid, st, tool, ti, agent, f"Sub-contract SCOPE {s['kind']}: {s['value']} is wider than "
                             f"contract {label} task {i + 1}.")
        for sk in t["skills"]:
            if a["skills"] and sk.split(":")[-1] not in [x.split(":")[-1] for x in a["skills"]]:
                return _deny(sid, st, tool, ti, agent, f"Sub-contract skill {sk} is not in AGENT {typ} skills.")
    n = sum(1 for sp in st["spawns"] if sp["parent"] == label) + 1
    sub_label = f"{label}.sub{n}"
    d = os.path.join(sdir(sid), "contracts")
    p = os.path.join(d, sub_label + ".md")
    with open(p, "w") as f:
        f.write(m.group(0))
    os.chmod(p, 0o444)
    fp_save(sid)
    st["spawns"].append({"label": sub_label, "type": typ, "parent": label, "agent_id": None, "t": now()})
    _allow(sid, st, tool, ti, agent, label=label, task=i + 1, sub=sub_label)
    return None


def _scope_within(s, p, root):
    if s["kind"] != p["kind"]:
        return False
    if p["value"] == "*":
        return True
    if s["kind"] in PATH_TOOLS:
        return under(norm(s["value"], root), norm(p["value"], root))
    return s["value"] == p["value"] or s["value"].startswith(p["value"] + " ")


def on_subagent_start(inp):
    sid = inp.get("session_id", "")
    st = load_state(sid)
    if not st:
        return None
    for sp in st["spawns"]:
        if sp["agent_id"] is None and sp["type"] == inp.get("agent_type"):
            sp["agent_id"] = inp.get("agent_id")
            st["agents"][inp.get("agent_id")] = sp["label"]
            save_state(sid, st)
            log(sid, kind="subagent", agent=inp.get("agent_id"), label=sp["label"])
            break
    return None


def _sub_gate(sid, st, inp, tool, ti, agent):
    label = st["agents"][agent]
    sp = next(s for s in st["spawns"] if s["label"] == label)
    c = load_contract(sid, st, label)
    prog = [norm(r["value"], st["root"]) for t in c["tasks"] + [c["global"]] for r in t["require"]
            if r["kind"] == "Write-to-task"]
    if tool in WRITE_TOOLS and norm(ti.get(PATH_TOOLS[tool], "")) in prog:
        _allow(sid, st, tool, ti, agent, label=label, work=False)
        return None
    for p in prog:
        last_work = max([e["t"] for e in ledger(sid) if e.get("kind") == "call" and e.get("agent") == agent
                         and e.get("work")] or [0])
        try:
            mt = os.path.getmtime(p)
        except OSError:
            return _deny(sid, st, tool, ti, agent, f"Write the progress file {p} (Plan, Last action, Findings, "
                         "Blocked) before any work.")
        if last_work and mt < last_work:
            return _deny(sid, st, tool, ti, agent, f"Update '## Last action' in {p} before the next call.")
    return _contract_gate(sid, st, c, inp, tool, ti, label, sp["t"], agent)


def _allow(sid, st, tool, ti, agent, work=True, inp=None, **kw):
    srv = server_of(tool, inp or {"tool_input": ti}) if tool.startswith("mcp__") else None
    srvs = sorted(server_names(tool, inp or {})) if tool.startswith("mcp__") else None
    log(sid, kind="call", tool=tool, key=primary(tool, ti)[:400], agent=agent, server=srv, servers=srvs,
        work=work, **kw)
    save_state(sid, st)


def _deny(sid, st, tool, ti, agent, reason, count=True):
    """Refuse the call. Under a contract it is recorded as a breach (counted, shown in the status bar); breaches
    no longer freeze anything: an unmet contract simply does not close."""
    log(sid, kind="deny", tool=tool, key=primary(tool, ti)[:400], agent=agent, reason=reason, breach=bool(
        count and st["phase"] == "ACTIVE"))
    if count and st["phase"] == "ACTIVE":
        st["breaches"] += 1
        reason += f" Breach {st['breaches']} (recorded)."
    save_state(sid, st)
    return deny(reason)


def _quiz_taint(sid, st, tool, ti):
    """A Read, Grep or Bash call that touches the file of a pending quiz fails that quiz."""
    q = st.get("quote")
    if not q or q.get("tainted"):
        return
    p = q["path"]
    hit = (tool in PATH_TOOLS and norm(ti.get(PATH_TOOLS[tool], "")) == p) or \
        (tool == "Bash" and (p in ti.get("command", "") or os.path.basename(p) in ti.get("command", "")))
    if hit:
        q["tainted"] = True
        log(sid, kind="quiz-taint", tool=tool, path=p)
        save_state(sid, st)


# ---------------------------------------------------------------- ledger (PostToolUse)

def on_posttool(inp):
    sid = inp.get("session_id", "")
    st = load_state(sid)
    if st is None:
        return None
    tool, ti, tr = inp.get("tool_name", ""), inp.get("tool_input", {}) or {}, inp.get("tool_response")
    agent = inp.get("agent_id")
    if tool == "Read":
        rec = read_proof(ti, tr)
        if rec:
            log(sid, kind="read", agent=agent, **rec)
    elif tool == "Skill":
        log(sid, kind="skill", name=tool_skill(ti), agent=agent)
    elif tool in ("Agent", "Task"):
        log(sid, kind="agent", type=ti.get("subagent_type", "general-purpose"), agent=agent,
            agent_id=(tr or {}).get("agentId") if isinstance(tr, dict) else None)
    return None


def read_proof(ti, tr):
    """Line-hash proof: only lines whose returned text equals the file's text on disk count as read."""
    if not isinstance(tr, dict):
        return None
    f = tr.get("file") if isinstance(tr.get("file"), dict) else {}
    path = norm(f.get("filePath") or ti.get("file_path", ""))
    content = f.get("content")
    if not isinstance(content, str):
        # images, PDFs, notebooks: the Read returned the whole file in another form; record it by file hash
        try:
            return {"path": path, "sha": sha(path), "binary": True, "type": tr.get("type")} if path else None
        except OSError:
            return None
    start = int(f.get("startLine") or 1)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            disk = fh.read().split("\n")
        cur = sha(path)
    except OSError:
        return None
    got = content.split("\n")
    if content.endswith("\n"):
        got = got[:-1]
    ranges, hashes, a = [], [], None
    for k, line in enumerate(got):
        n = start + k
        d = disk[n - 1] if n - 1 < len(disk) else None
        ok = d is not None and (line.rstrip("\r") == d.rstrip("\r") or _truncated_match(line, d))
        if ok:
            hashes.append(line_hash(d))
        if ok and a is None:
            a = n
        if not ok and a is not None:
            ranges.append([a, n - 1])
            a = None
    if a is not None:
        ranges.append([a, start + len(got) - 1])
    return {"path": path, "sha": cur, "ranges": ranges, "hashes": hashes, "total": f.get("totalLines"),
            "returned": len(got), "chars": len(content)}


def _truncated_match(returned, disk_line):
    """The Read tool cuts very long lines; the returned start of the line still proves it was read."""
    r = returned.rstrip("\r")
    if len(disk_line) <= len(r) or len(r) < 1000:
        return False
    for cut in ("... [truncated]", "…", "..."):
        if r.endswith(cut):
            r = r[: -len(cut)]
            break
    return disk_line.startswith(r[:1000]) and disk_line.startswith(r)


# ---------------------------------------------------------------- the stop gate

CITE = re.compile(r"`?((?:~|/|\.{1,2}/|[\w.-]+/)[\w./~-]*\.\w+):(\d+)(?:[-–](\d+))?`?")
READ_CLAIM = re.compile(r"\b(?:i\s+)?(?:read|re-read|reread|went through|opened)\b[^.\n]{0,80}?`([^`]+\.\w+)`", re.I)


NOT_A_CLAIM = re.compile(r"\b(should|shall|will|would|could|can|may|might|must|need to|needs to|going to|want to|"
                         r"have to|let me|i'?ll|to|please|before|if|whether|never|not|don'?t|didn'?t|haven'?t)\s+"
                         r"(?:\w+\s+){0,2}$", re.I)


def _claim_paths(sid, st, name):
    """Files a cited name can mean: the name itself when absolute, else every read file whose path ends with it,
    else the name under the contract root. Fixes bare names resolved against the wrong repo."""
    if name.startswith(("/", "~")):
        return [norm(name)]
    tail = "/" + name.lstrip("./")
    read = sorted({e["path"] for e in ledger(sid) if e.get("kind") == "read" and e.get("agent") is None
                   and e.get("path", "").endswith(tail)})
    return read or [norm(name, st["root"])]


def claim_check(sid, st, msg):
    """Every path:line cited and every file said to be read must be in the main session's ledger. Questions and
    plans ("should I read `X`?", "I'll read `X`") are not claims."""
    miss = []
    for m in CITE.finditer(msg or ""):
        a = int(m.group(2))
        b = int(m.group(3) or a)
        paths = [p for p in _claim_paths(sid, st, m.group(1)) if os.path.isfile(p)]
        if not paths:
            continue  # not a file on this device (a URL, a line in another machine's file): nothing to check
        if not any(all(i in coverage(sid, st, p, 0)[0] for i in range(a, b + 1)) for p in paths):
            miss.append(f"cited {m.group(1)}:{m.group(2)}{'-' + m.group(3) if m.group(3) else ''} but those lines were never read")
    for m in READ_CLAIM.finditer(msg or ""):
        start = (msg or "").rfind("\n", 0, m.start()) + 1
        before = msg[start:m.start()]
        end = re.search(r"[.!?\n]", msg[m.end():])
        sentence_end = msg[m.end() + end.start()] if end else ""
        if NOT_A_CLAIM.search(before + " ") or sentence_end == "?":
            continue
        paths = [p for p in _claim_paths(sid, st, m.group(1)) if os.path.isfile(p)]
        if paths and not any(coverage(sid, st, p, 0)[0] for p in paths):
            miss.append(f"said {m.group(1)} was read, but no read of it is in the ledger")
    return miss


def quote_check(sid, st, c, msg, since):
    """For REQUIRE Read FULL+QUOTE: ask for 3 random lines, then check the quote exactly."""
    q = st.get("quote")
    if q:
        ok = not q.get("tainted") and all(line.strip() and line.strip() in (msg or "") for line in q["lines"])
        st["quote"] = None
        if ok:
            st["quote_passed"].append(q["path"])
            log(sid, kind="quote", path=q["path"], passed=True)
            return None
        log(sid, kind="quote", path=q["path"], passed=False)
        n = q.get("task")
        if n is not None:
            k = str(n)
            st.setdefault("strikes", {})[k] = st.get("strikes", {}).get(k, 0) + 1
            if st["strikes"][k] >= 3:
                t = next(x for x in c["tasks"] if x["n"] == n)
                paths = [norm(x["value"], st["root"]) for x in t["require"] if x["kind"].startswith("Read FULL")]
                for p in paths:
                    st.setdefault("void", {})[p] = now()
                st["quote_passed"] = [p for p in st["quote_passed"] if p not in paths]
                st["strikes"][k] = 0
                log(sid, kind="round-failed", task=n)
                return (f"quiz failed 3 times: task {n} is failed. Every file of task {n} must be read again in full; "
                        "the quiz starts over after that")
            why = "the file was opened while the quiz was pending" if q.get("tainted") else "the quote did not match"
            return f"quiz on {q['path']} failed: {why}. Strike {st['strikes'][k]}/3 for task {n}"
        return f"the quote of {q['path']} did not match; read it in full again"
    for t in c["tasks"] + [c["global"]]:
        for r in t["require"]:
            if r["kind"] != "Read FULL+QUOTE":
                continue
            p = norm(r["value"], st["root"])
            if p in st["quote_passed"] or not full_read(sid, st, p, since):
                continue
            with open(p, encoding="utf-8", errors="replace") as f:
                lines = [(i + 1, x) for i, x in enumerate(f.read().split("\n")) if len(x.strip()) > 12]
            pick = sorted(RNG.sample(lines, min(RNG.randint(QUIZ_MIN, QUIZ_MAX), len(lines))))
            st["quote"] = {"path": p, "lines": [x for _, x in pick]}
            return (f"quote lines {', '.join(str(i) for i, _ in pick)} of {p} exactly, each on its own line, "
                    "with no tool call")
    for t in c["tasks"]:
        for r in t["require"]:
            if r["kind"] != "Quiz":
                continue
            paths = [norm(x["value"], st["root"]) for x in t["require"] if x["kind"].startswith("Read FULL")]
            if not paths or not all(full_read(sid, st, p, since) for p in paths):
                continue  # the quiz comes only after every file of the task is read
            left = [p for p in paths if p not in st["quote_passed"]]
            if len(paths) - len(left) >= int(r["value"]) or not left:
                continue
            p = RNG.choice(left)  # drawn now, after the reading: unknown in advance
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = [(i + 1, x) for i, x in enumerate(fh.read().split("\n")) if len(x.strip()) > 12]
            if not lines:
                st["quote_passed"].append(p)
                continue
            # the hook draws both the count (3 to 8, never more than 8) and the lines
            pick = sorted(RNG.sample(lines, min(RNG.randint(QUIZ_MIN, QUIZ_MAX), len(lines))))
            st["quote"] = {"path": p, "lines": [x for _, x in pick], "task": t["n"]}
            return (f"quiz: quote lines {', '.join(str(i) for i, _ in pick)} of {p} exactly, each on its own line, "
                    "with no tool call")
    return None


def block(reason, event="Stop"):
    return {"decision": "block", "reason": reason}


def on_stop(inp):
    sid = inp.get("session_id", "")
    st = load_state(sid)
    if st is None:
        return None
    fp_review(sid, st)  # warns, never pauses
    msg = inp.get("last_assistant_message", "")
    phase = st["phase"]
    task_n = _task_number(sid, st)
    miss = [] if lifted(st, "claims", task_n) else claim_check(sid, st, msg)
    if phase in NEGOTIATION and st["current"] == "OPENING" and not lifted(st, "opening"):
        c = load_contract(sid, st, "OPENING")
        miss += [f"{r['kind']}: {resolve(r['value'], st['root'])}" for t in c["tasks"] + [c["global"]]
                 for r in t["require"] if not require_met(sid, st, r, 0)]
    elif phase == "ACTIVE":
        p = contract_file(sid, st["current"])
        if not os.path.exists(p) or sha(p) != st["hash"]:
            st["phase"] = "FROZEN"
            save_state(sid, st)
            log(sid, kind="tamper", label=st["current"])
            return block(f"Contract {st['current']} no longer matches its signed hash: frozen. Tell the owner.")
        c = load_contract(sid, st)
        if st.get("limit_hit"):
            st["phase"] = "DONE"
            log(sid, kind="closed", label=st["current"], finished=False, why=st["limit_hit"])
            save_state(sid, st)
            return None  # one closing turn; the report must name what is not done
        since = st["signed_at"]
        # strict, but only for what is due: the current task (the first with an unmet line, so a line put off
        # on purpose keeps showing) and goals up to it; future tasks are not listed.
        i, t = current_task(sid, st, c, st["current"], since)
        # grade a pending quiz answer first, so a pass counts in this same stop
        q = None if lifted(st, "quiz", i + 1) else quote_check(sid, st, c, msg, since)
        i, t = current_task(sid, st, c, st["current"], since)
        due = [f"task {t['n']}: {m}" for m in task_open(sid, st, t, st["current"], since)]
        upto = dict(c, tasks=c["tasks"][:i + 1])
        due += goals_missing(sid, st, upto, since)
        if q:
            due.append(q)
        denied = [e for e in ledger(sid) if e.get("kind") == "deny" and e["t"] >= st.get("turn_start", 0)
                  and e.get("agent") is None]
        if denied:
            due.append(f"{len(denied)} call(s) refused this turn, e.g. {denied[0]['tool']} {denied[0]['key'][:80]}: "
                       "report them to the owner")
        all_met = not due and i == len(c["tasks"]) - 1 and not task_open(sid, st, t, st["current"], since)
        if lifted(st, "stop", i + 1):
            if due:
                log(sid, kind="stop-lifted", missing=due)
            due = []
        miss += due
        if not miss and all_met:
            st["phase"] = "DONE"
            log(sid, kind="closed", label=st["current"], finished=True)
            save_state(sid, st)
            return {"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext":
                    f"Every line of contract {st['current']} is met. Report each step you did. Do not call it done: only the owner's #ok closes it. No calls until #ok or #redo."}}
    if not miss:
        save_state(sid, st)
        return None
    sig = sorted(miss)
    n_ledger = len(ledger(sid))
    if inp.get("stop_hook_active") and st.get("last_block") == [sig, n_ledger]:
        st["stopped_unmet"] = miss
        log(sid, kind="stopped-unmet", missing=miss)
        save_state(sid, st)
        return None  # nothing changed since the last block: end the turn and report it to the owner
    st["last_block"] = [sig, n_ledger]
    save_state(sid, st)
    shown = miss[:12] + ([f"... and {len(miss) - 12} more (status bar)"] if len(miss) > 12 else [])
    return block(f"Contract {st['current']} is not done:\n- " + "\n- ".join(shown))


def on_subagent_stop(inp):
    sid = inp.get("session_id", "")
    st = load_state(sid)
    agent = inp.get("agent_id")
    if not st or agent not in st["agents"]:
        return None
    label = st["agents"][agent]
    sp = next(s for s in st["spawns"] if s["label"] == label)
    c = load_contract(sid, st, label)
    miss = []
    for t in c["tasks"]:
        miss += task_open(sid, st, t, label, sp["t"], agent)
    miss += [m for m in goals_missing(sid, st, c, sp["t"])]
    for t in c["tasks"] + [c["global"]]:
        for r in t["require"]:
            if r["kind"] == "Write-to-task":
                ok, why = progress_ok(norm(r["value"], st["root"]))
                if not ok:
                    miss.append(why)
    if not miss:
        log(sid, kind="closed", label=label, finished=True, agent=agent)
        return None
    if inp.get("stop_hook_active") and st.get("sub_block", {}).get(agent) == sorted(miss):
        log(sid, kind="stopped-unmet", label=label, agent=agent, missing=miss)
        return None
    st.setdefault("sub_block", {})[agent] = sorted(miss)
    save_state(sid, st)
    return block(f"Sub-contract {label} is not done:\n- " + "\n- ".join(sorted(set(miss))))
