CONTRACT OPENING   type: salary
# The owner lists what the opening needs. A project can replace this file with <root>/.contract/opening.md
# (only the owner writes .contract/). Documents these files point to may be read too: reads are always open.
REQUIRE? Read FULL: {root}/AGENTS.md
REQUIRE? Read FULL: {root}/MEMORY.md
REQUIRE? Read FULL: {root}/RESUME.md
REQUIRE? Read FULL: {root}/PENDING.md
REQUIRE? Read FULL: {root}/HANDOFF.md
REQUIRE? Read FULL: newest ~/repos/NvAEx-Recaps/handoff/*/*.md
SKILLS task-observer
# Project Recon: read-only listing during negotiation (find with -delete or -exec is refused).
# A project opening may add SCOPE lines for reads outside its scope (e.g. SCOPE Bash: git -C <repo> log).
SCOPE Bash: ls
SCOPE Bash: find
SCOPE Bash: wc
