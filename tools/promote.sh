#!/usr/bin/env bash
# tools/promote.sh : release what's on dev into main, without what's only for working on decal (DEV_ONLY): main holds
# decal itself, dev holds everything. Run in a clean checkout; it commits on main and pushes nothing (then: review,
# git push origin main, tag). Comes back to the branch it started on.
set -euo pipefail
DEV=refs/heads/dev   # in full: the rolling dev release also makes a tag called dev
DEV_ONLY=(CLAUDE.md docs tests)
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if ! git diff --quiet || ! git diff --cached --quiet; then die "uncommitted changes: commit or stash them first"; fi
start=$(git rev-parse --abbrev-ref HEAD)
git checkout -q main   # the branch (checkout prefers a branch name)
# a clash can only be in DEV_ONLY (main deleted them, dev changed them): removing them settles it
git merge --no-ff --no-commit "$DEV" >/dev/null 2>&1 || true
git rm -rqf --ignore-unmatch -- "${DEV_ONLY[@]}" >/dev/null   # tracked files only: anything of yours in them stays
if [[ -n $(git diff --name-only --diff-filter=U) ]]; then
  git merge --abort; git checkout -q "$start"
  die "dev and main clash outside ${DEV_ONLY[*]}: merge them by hand"
fi
git commit -q -m "release: dev $(git rev-parse --short "$DEV") into main (without ${DEV_ONLY[*]})"
git checkout -q "$start"
echo "main is now dev $(git rev-parse --short "$DEV") without ${DEV_ONLY[*]}: check it, then git push origin main"
