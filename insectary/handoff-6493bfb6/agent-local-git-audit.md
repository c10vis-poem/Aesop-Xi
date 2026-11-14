## Plan
- [x] list worktrees per repo
- [x] per repo: branch -vv, unpushed log, status, stash
- [x] standalone copies (fresh, merge, .review, silo)
- [x] final report (delivered via handback)

## Last action
2026-11-13: all probes done, report handed back.

## Findings
See handback report. Key: Aesop-Xi rules-v3 (d93661c) unpushed + dirty wt/rules-v3; NovAExopia detached 59dfff3 UU marketplace.json (stash apply residue); vault dirty; Recaps main dir dirty + device-setup wt 738 staged files; fresh/NovAExopia & fresh/NovAExorpus uncommitted killswitch removals; fresh/Aesop-Xi 2 unpushed commits; merge-2026-11-11 5 unpushed restructure commits.

## Blocked
None refused. One command of mine failed: git -C ~/repos/.worktrees (dir does not exist; my mistake). .review/fable is not a git repo itself (subfolders are).
