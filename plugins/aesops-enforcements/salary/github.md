CONTRACT GITHUB   type: salary
# The GitHub protocol: same for every job, so it is pre-signed. Forks sync to upstream main first.
SCOPE Bash: git status
SCOPE Bash: git diff
SCOPE Bash: git log
SCOPE Bash: git show
SCOPE Bash: git branch
SCOPE Bash: git fetch
SCOPE Bash: gh repo sync
SCOPE Bash: gh repo view
SCOPE Bash: git pull   after: Bash: gh repo sync   when: fork
SCOPE Bash: git switch   after: Bash: gh repo sync   when: fork
SCOPE Bash: git add
SCOPE Bash: git commit
SCOPE Bash: git push   after: #push
SCOPE Bash: gh pr create   after: #push
SCOPE Bash: gh pr merge   after: #push
SCOPE Bash: gh pr view
SCOPE Bash: gh pr checks
SCOPE Bash: gh run view
