#!/usr/bin/env python3
"""subagent_audit.py -- Rule 10 audit of one sub-agent, from its own transcript (operator, 2026-11-10).

Usage: subagent_audit.py <agent_transcript.jsonl> <agent_type> <progress_file or "">
Prints one JSON object:
  assigned  files the spawn prompt assigned:  a "Files:" / "## Files" block of paths, a "Paths file: <f>"
            (or any <ID>-paths.txt named), or a "Folder: <dir>" (every text file under it)
  full      assigned files opened whole       partial  opened, but not every line    unread  never opened
  tools_equipped / tools_unused, skills_equipped / skills_unused  (from the agent definition's frontmatter)
"Opened whole": Read ranges (offset/limit; a plain Read covers lines 1-2000) cover every line, or a Bash
command that prints or loads the whole file (cat, bat, jq, pandoc, markitdown, python/node naming it).
A skill counts as used: a Skill call, a Read of its SKILL.md, or a "## Skills used" line in the progress
file naming it with how it was used (preloaded skills make no call). Fails open: any error -> {}.
"""
import glob, json, os, re, sys

HOME = os.path.expanduser("~")
SKIP_DIRS = {".git", "node_modules", "__pycache__", "dist", "build", ".venv"}
SKIP_RE = re.compile(r"\.(png|jpe?g|gif|webp|svg|ico|mp[34]|m4a|wav|ogg|zip|gz|tgz|woff2?|ttf|otf|eot|pyc|so|bin|db|sqlite)$"
                     r"|(^|/)(LICENSE|LICENCE|COPYING)[^/]*$|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|poetry\.lock)$", re.I)
PATH_RE = r"(?:~|/)[^\s`'\"<>|;,)]+"


def ex(p):
    return os.path.realpath(os.path.expanduser(p.strip().rstrip(".:")))


def text_of(c):
    if isinstance(c, str):
        return c
    return "\n".join(x.get("text", "") for x in c or [] if isinstance(x, dict) and x.get("type") == "text")


def load(tp):
    rows = []
    with open(tp) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


def assigned(spawn):
    out = []
    # Files: block
    for m in re.finditer(r"(?im)^(?:#+\s*files|files:)[^\n]*\n((?:[ \t]*(?:[-*]\s*)?" + PATH_RE + r"[^\n]*\n?)+)", spawn):
        out += [ex(p) for p in re.findall(PATH_RE, m.group(1))]
    for m in re.finditer(r"(?im)^files:\s*(" + PATH_RE + r"(?:[ ,]+" + PATH_RE + r")*)\s*$", spawn):
        out += [ex(p) for p in re.findall(PATH_RE, m.group(1))]
    # paths files
    pfs = re.findall(r"(?i)paths file:\s*(" + PATH_RE + ")", spawn) + re.findall(r"(" + PATH_RE + r"-paths\.txt)", spawn)
    for pf in pfs:
        try:
            with open(ex(pf)) as f:
                out += [ex(l) for l in f if l.strip() and not l.startswith("#")]
        except OSError:
            pass
    # folders
    for d in re.findall(r"(?im)^(?:#+\s*)?folder:\s*(" + PATH_RE + ")", spawn):
        d = ex(d)
        for root, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
            for fn in files:
                p = os.path.join(root, fn)
                if not SKIP_RE.search(p):
                    out.append(os.path.realpath(p))
    seen, res = set(), []
    for p in out:
        if p not in seen:
            seen.add(p); res.append(p)
    return res


def nlines(p):
    try:
        with open(p, "rb") as f:
            data = f.read()
        return max(1, data.count(b"\n") + (0 if data.endswith(b"\n") or not data else 1))
    except OSError:
        return 0


def coverage(rows, files):
    rng = {p: [] for p in files}
    full = set()
    for r in rows:
        if r.get("type") != "assistant":
            continue
        for c in (r.get("message") or {}).get("content") or []:
            if not isinstance(c, dict) or c.get("type") != "tool_use":
                continue
            i = c.get("input") or {}
            if c.get("name") == "Read":
                p = ex(i.get("file_path", ""))
                if p in rng:
                    s = int(i.get("offset") or 1); n = int(i.get("limit") or 2000)
                    rng[p].append((max(1, s), max(1, s) + n - 1))
            elif c.get("name") == "Bash":
                cmd = i.get("command", "")
                for p in files:
                    short = p.replace(HOME, "~")
                    if p not in cmd and short not in cmd and os.path.basename(p) not in cmd.split():
                        continue
                    if re.search(r"(^|[;&|(\s])(cat|bat|jq|pandoc|markitdown|python3?|node|read_packet\.py)\s", cmd):
                        full.add(p)
                    m = re.search(r"sed -n '?(\d+),(\d+)p", cmd)
                    if m:
                        rng[p].append((int(m.group(1)), int(m.group(2))))
                    m = re.search(r"head -(?:n\s*)?(\d+)", cmd)
                    if m:
                        rng[p].append((1, int(m.group(1))))
    res = {"full": [], "partial": [], "unread": []}
    for p in files:
        if p in full:
            res["full"].append(p); continue
        if not rng[p]:
            res["unread"].append(p); continue
        need, got, cur = nlines(p), 0, 0
        for s, e in sorted(rng[p]):
            if e <= cur:
                continue
            got += e - max(s, cur + 1) + 1; cur = e
        (res["full"] if got >= need or cur >= need else res["partial"]).append(p)
    return res


def agent_def(at):
    name = at.split(":")[-1]
    dirs = [os.path.join(HOME, ".claude", "agents"), os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", "."), ".claude", "agents")]
    dirs += os.environ.get("AESOP_AGENT_DIRS", "").split(":")
    pats = [os.path.join(d, name + ".md") for d in dirs if d]
    pats += [os.path.join(HOME, ".claude", "plugins", "**", "agents", name + ".md"),
             os.path.join(HOME, "repos", "*", "plugins", "*", "agents", name + ".md")]
    for pat in pats:
        for f in sorted(glob.glob(pat, recursive=True)):
            try:
                txt = open(f).read()
            except OSError:
                continue
            m = re.match(r"---\n(.*?)\n---", txt, re.S)
            if m:
                return m.group(1)
    return ""


def fm_list(fm, key):
    m = re.search(r"(?m)^" + key + r":[ \t]*(.*)$", fm)
    if not m:
        return []
    if m.group(1).strip():
        return [x.strip().strip("'\"") for x in m.group(1).strip("[] ").split(",") if x.strip()]
    items, start = [], m.end()
    for line in fm[start:].split("\n")[1:]:
        mm = re.match(r"\s+-\s*(.+)", line)
        if not mm:
            if line.strip():
                break
            continue
        items.append(mm.group(1).strip().strip("'\""))
    return items


def main():
    tp, at, pf = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
    rows = load(tp)
    spawn = "\n".join(text_of((r.get("message") or {}).get("content")) for r in rows if r.get("type") == "user")[:40000]
    files = assigned(spawn)
    cov = coverage(rows, files)
    used = [c.get("name", "") for r in rows if r.get("type") == "assistant"
            for c in (r.get("message") or {}).get("content") or [] if isinstance(c, dict) and c.get("type") == "tool_use"]
    fm = agent_def(at) if at else ""
    tools = [re.sub(r"\(.*", "", t) for t in fm_list(fm, "tools") if t not in ("*", "")]
    skills = fm_list(fm, "skills")
    tunused = [t for t in tools if not any(u == t or u.startswith(t) for u in used)]
    called = []
    for r in rows:
        if r.get("type") != "assistant":
            continue
        for c in (r.get("message") or {}).get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                i = c.get("input") or {}
                if c.get("name") == "Skill":
                    called.append(str(i.get("skill", "")).split(":")[-1])
                if c.get("name") == "Read":
                    m = re.search(r"/skills/([^/]+)/SKILL\.md$", i.get("file_path", ""))
                    if m:
                        called.append(m.group(1))
    su = ""
    if pf and os.path.isfile(pf):
        m = re.search(r"(?ms)^## Skills used\s*\n(.*?)(?=^## |\Z)", open(pf).read())
        su = m.group(1) if m else ""
    def skill_used(s):
        b = s.split(":")[-1]
        if b in called:
            return True
        return any(b in l and len(l.strip()) >= len(b) + 20 for l in su.splitlines())
    sunused = [s for s in skills if not skill_used(s)]
    print(json.dumps({"assigned": files, **cov, "tools_equipped": tools, "tools_unused": tunused,
                      "skills_equipped": skills, "skills_unused": sunused}))


def cov_cli():
    """--coverage <transcript> <path>...: whole-file coverage of each path (a folder: its text files)."""
    rows = load(sys.argv[2]); files = []
    for t in sys.argv[3:]:
        t = ex(t)
        if os.path.isdir(t):
            for root, dirs, fs in os.walk(t):
                dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
                files += [os.path.realpath(os.path.join(root, f)) for f in fs if not SKIP_RE.search(f)]
        else:
            files.append(t)
    print(json.dumps(coverage(rows, files)))


try:
    cov_cli() if len(sys.argv) > 1 and sys.argv[1] == "--coverage" else main()
except Exception:
    print("{}")
