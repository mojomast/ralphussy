Fixes applied: devplan parsing hardening and default branch normalization

Files changed:
- ralph-refactor/lib/devplan.sh — preprocess devplan files: strip YAML frontmatter, remove HTML comments, normalize unicode checkboxes, accept plain list items and normalize them to '- [ ]'. Added helper `preprocess_devplan` and updated parsing functions to use it.
- ralph-refactor/lib/swarm_git.sh — added `swarm_git_normalize_default_branch` which safely renames local `master` to `main` when `main` missing and `master` exists; honors `SWARM_BASE_BRANCH` env override.
- ralph-refactor/tests/test_devplan.sh — unit tests for plain lists, checklists, frontmatter, and HTML comments/whitespace.
- ralph-refactor/tests/test_swarm.sh — small addition to test branch normalization locally.

How to run tests:
1) Run devplan unit tests:
   cd /home/mojo/projects/ralphussy && bash ralph-refactor/tests/test_devplan.sh

2) Run swarm tests (includes branch normalization check):
   bash ralph-refactor/tests/test_swarm.sh

Quick verification (devplan detection):
 - printf '%s\n' '- task A' > /tmp/dp.md
 - bash -c 'source ralph-refactor/lib/devplan.sh; has_pending_tasks /tmp/dp.md && echo detected || echo missing'

Branch normalization check (local-only, safe):
 - Create a repo and ensure it has 'master' only; run:
   git init /tmp/merge-test && cd /tmp/merge-test
   git config user.name "Swarm"
   git config user.email "swarm@example.com"
   echo initial > file.txt; git add file.txt; git commit -m init
   git branch -m master 2>/dev/null || true
   source ralph-refactor/lib/swarm_git.sh
   swarm_git_normalize_default_branch
   git rev-parse --abbrev-ref HEAD

Notes & safety:
- `swarm_git_normalize_default_branch` only performs local branch rename and will not push or change remotes. Set `SWARM_BASE_BRANCH` to override desired base branch.
- Devplan preprocessing writes a temporary preprocessed file next to the devplan (named devplan.md.preproc). This keeps original file untouched.

Next steps (optional):
1) Wire `swarm_git_normalize_default_branch` into branch creation path (called at run start) when initializing worker branches.
