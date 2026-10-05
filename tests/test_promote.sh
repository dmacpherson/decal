#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# tools/promote.sh: dev goes to main without what's only for working on decal (CLAUDE.md, docs, tests)
R="$T_TMP/repo"; mkdir -p "$R"; cd "$R" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
echo v1 > decal; echo notes > CLAUDE.md; mkdir -p docs tests; echo d > docs/a.md; echo t > tests/t.sh
git add -A; git commit -qm one
git checkout -qb dev; echo v2 > decal; echo more >> CLAUDE.md; echo t2 > tests/u.sh; git add -A; git commit -qm two
out=$(bash "$REPO/tools/promote.sh" 2>&1); assert_eq "$?" "0" "promote: rc"
assert_eq "$(git show main:decal)" "v2" "main gets dev's code"
for p in CLAUDE.md docs/a.md tests/t.sh tests/u.sh; do
  git ls-tree -r --name-only main | grep -qx "$p"; assert_eq "$?" "1" "main has no $p"
done
assert_eq "$(git show dev:CLAUDE.md | head -1)" "notes" "dev keeps everything"
assert_eq "$(git rev-parse --abbrev-ref HEAD)" "dev" "back on the branch it started from"
git merge-base --is-ancestor dev main; assert_eq "$?" "0" "main records the merge (the next one starts from here)"
# the next release: CLAUDE.md changed on dev again (main deleted it): no conflict, still left out
echo again >> CLAUDE.md; echo v3 > decal; git commit -qam three
out=$(bash "$REPO/tools/promote.sh" 2>&1); assert_eq "$?" "0" "promote again: rc"
assert_eq "$(git show main:decal)" "v3" "...the new code"; git ls-tree -r --name-only main | grep -qx CLAUDE.md; assert_eq "$?" "1" "...CLAUDE.md still left out"
# a file of yours that git doesn't track, inside a dev-only folder, is never deleted
echo mine > docs/scratch.txt; echo v4 > decal; git commit -qam four
bash "$REPO/tools/promote.sh" >/dev/null 2>&1; assert_eq "$(cat docs/scratch.txt 2>/dev/null)" "mine" "an untracked file in docs/ stays"
assert_eq "$(git show main:decal)" "v4" "...and the release still went through"
rm -f docs/scratch.txt
# the rolling dev release adds a tag called dev: the branch is what's released, never that tag (review)
git tag -f dev >/dev/null; echo v5 > decal; git commit -qam five
bash "$REPO/tools/promote.sh" >/dev/null 2>&1; assert_eq "$(git show main:decal)" "v5" "a tag named dev: the branch's newest commit is released"
git tag -d dev >/dev/null
# uncommitted work: refuses, changes nothing
echo dirty >> decal; before=$(git rev-parse main)
out=$(bash "$REPO/tools/promote.sh" 2>&1); assert_eq "$?" "1" "uncommitted changes: refused"
assert_contains "$out" "commit or stash" "...says what to do"; assert_eq "$(git rev-parse main)" "$before" "...main untouched"
t_done
