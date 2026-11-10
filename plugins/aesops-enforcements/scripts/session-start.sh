#!/usr/bin/env bash
# Rule 7, SessionStart: what changed, whether housekeeping is due, staged skill updates.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
run_parts context-diff housekeeping-check staged-updates
