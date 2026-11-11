"""Hook entry: `python3 -I lib/hook.py <Event>` with the event JSON on stdin. hooks/hooks.json calls this."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import contract as C  # noqa: E402

HANDLERS = {"SessionStart": C.on_start, "UserPromptSubmit": C.on_prompt, "PreToolUse": C.on_pretool,
            "PostToolUse": C.on_posttool, "Stop": C.on_stop, "SubagentStart": C.on_subagent_start,
            "SubagentStop": C.on_subagent_stop}


def main(event):
    try:
        inp = json.load(sys.stdin)
    except ValueError:
        inp = {}
    sid = inp.get("session_id", "unknown")
    try:
        out = HANDLERS[event](inp)
    except Exception as e:  # a crash refuses tool calls and is logged; it never passes silently
        C.log(sid, kind="crash", event=event, error=repr(e))
        if event != "PreToolUse":
            print(f"contract hook {event} crashed: {e!r}", file=sys.stderr)
            return 0
        out = C.deny(f"Enforcement crashed ({e!r}); the call is refused. Log: {C.sdir(sid)}/ledger.jsonl")
    if out:
        print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ""))
