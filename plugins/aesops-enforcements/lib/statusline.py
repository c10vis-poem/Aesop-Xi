"""Status bar for the contract (Claude Code `statusLine`). Runs locally and costs no tokens.
Settings: {"statusLine": {"type": "command", "command": "python3 -I <plugin>/lib/statusline.py"}}
Shows: contract and phase, current task, unmet lines, breaches, push, owner overrides; second line: the first unmet
line, so persistent notices live here instead of in the agent's context."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import contract as C  # noqa: E402


def render(inp):
    sid = inp.get("session_id", "")
    st = C.load_state(sid)
    if not st:
        return "contract: no state"
    phase = st["phase"]
    parts = [f"contract {st['current']}", phase.lower()]
    first = ""
    if phase in ("ACTIVE", "DONE", "FROZEN"):
        c = C.load_contract(sid, st)
        if c:
            i, t = C.current_task(sid, st, c, st["current"], st["signed_at"])
            unmet = C.task_open(sid, st, t, st["current"], st["signed_at"])
            parts.append(f"task {i + 1}/{len(c['tasks'])}")
            parts.append(f"unmet {len(unmet)}")
            first = unmet[0] if unmet else ""
    parts.append(f"breaches {st.get('breaches', 0)}")
    parts.append("push ok" if st.get("push_ok") else "push held")
    ov = [f"{o['gate']}({o['scope']})" for o in st.get("overrides", [])]
    if ov:
        parts.append("lifted: " + ",".join(ov))
    if st.get("quote"):
        parts.append("quiz pending")
    if st.get("fp_warn"):
        parts.append(f"WARN {len(st['fp_warn'])} protected file(s) changed outside git")
    if phase in C.NEGOTIATION and st.get("opening_unmet"):
        parts.append(f"opening: {len(st['opening_unmet'])} read(s) left")
        first = first or st["opening_unmet"][0]
    line = " | ".join(parts)
    return line + ("\n" + first[:140] if first else "")


def main():
    try:
        inp = json.load(sys.stdin)
    except ValueError:
        inp = {}
    try:
        print(render(inp))
    except Exception as e:  # the status bar must never break the session
        print(f"contract: status unavailable ({type(e).__name__})")


if __name__ == "__main__":
    main()
