"""Hook entry: `python3 -I lib/hook.py <Event>` with the event JSON on stdin. hooks/hooks.json calls this.
Fails closed: if anything breaks during PreToolUse, including loading contract.py, exit 2 refuses the call."""
import json
import os
import sys


def main(event):
    try:
        sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
        import contract as C
    except Exception as e:
        print(f"contract.py failed to load ({e!r}); the call is refused.", file=sys.stderr)
        return 2 if event == "PreToolUse" else 0
    if event == "refingerprint":  # owner only, from a terminal: python3 -I lib/hook.py refingerprint <session id>
        C.fp_save(sys.argv[2])
        print("fingerprint taken for session", sys.argv[2])
        return 0
    handlers = {"SessionStart": C.on_start, "UserPromptSubmit": C.on_prompt, "PreToolUse": C.on_pretool,
                "PostToolUse": C.on_posttool, "PostToolUseFailure": C.on_posttool, "Stop": C.on_stop, "SubagentStart": C.on_subagent_start,
                "SubagentStop": C.on_subagent_stop}
    try:
        inp = json.load(sys.stdin)
    except ValueError:
        inp = {}
    sid = inp.get("session_id", "unknown")
    try:
        out = handlers[event](inp)
    except Exception as e:
        try:
            C.log(sid, kind="crash", event=event, error=repr(e))
        except Exception:
            pass
        print(f"contract hook {event} crashed: {e!r}; the call is refused.", file=sys.stderr)
        return 2 if event == "PreToolUse" else 0
    if out:
        print(json.dumps(out))
    return 0


if __name__ == "__main__":
    try:
        code = main(sys.argv[1] if len(sys.argv) > 1 else "")
    except BaseException:
        code = 2 if sys.argv[1:2] == ["PreToolUse"] else 0
    sys.exit(code)
