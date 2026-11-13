CONTRACT OPENING   type: salary
# Rule 1, the opening (owner, 2026-11-13). In order: the rules first, then the project's files, then the handoff,
# then every document they point to (on the phone or off it: web pages, GitHub, Drive are read freely). It ends
# only when the agent confirms to the owner, in a line starting "Opening done:", what it read, what it loaded and
# what it could not find; then its findings and proposal; then negotiation. A project can replace this file with
# <root>/.contract/opening.md (only the owner writes .contract/).
REQUIRE Read FULL: {plugin}/RULES.md
REQUIRE? Read FULL: {root}/AGENTS.md
REQUIRE? Read FULL: {root}/RESUME.md
REQUIRE? Read FULL: {root}/MEMORY.md
REQUIRE? Read FULL: {root}/PENDING.md
# HANDOFF.md points at the handoff meant for this repo; what it points to is required as a pointed document
REQUIRE? Read FULL: {root}/HANDOFF.md
REQUIRE? Read FULL: ~/repos/NvAEx-Recaps/HANDOFFS.md
REQUIRE? Read FULL: newest ~/repos/NvAEx-Recaps/handoff/*/*.md
SKILLS task-observer
# Project Recon: read-only listing during negotiation (find with -delete or -exec is refused).
# A project opening may add SCOPE lines for reads outside its scope (e.g. SCOPE Bash: git -C <repo> log).
SCOPE Bash: ls
SCOPE Bash: find
SCOPE Bash: wc
