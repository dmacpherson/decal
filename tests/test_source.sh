#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
SRC="$REPO/lib/source.py"
r() { python3 "$SRC" resolve "$1" 2>&1; }

# GitHub, every way people write it
assert_eq "$(r github:me/prof)" $'github\tgithub:me/prof\t' "github:owner/repo as is"
assert_eq "$(r github:me/prof@laptop)" $'github\tgithub:me/prof@laptop\t' "...with a ref"
assert_eq "$(r me/prof)" $'github\tgithub:me/prof\t' "owner/repo"
assert_eq "$(r me/prof@v2)" $'github\tgithub:me/prof@v2\t' "owner/repo@ref"
assert_eq "$(r https://github.com/me/prof)" $'github\tgithub:me/prof\t' "a GitHub link"
assert_eq "$(r https://github.com/me/prof.git)" $'github\tgithub:me/prof\t' "...ending .git"
assert_eq "$(r https://github.com/me/prof/)" $'github\tgithub:me/prof\t' "...with a trailing slash"
assert_eq "$(r github.com/me/prof)" $'github\tgithub:me/prof\t' "...without https://"
assert_eq "$(r https://www.github.com/me/prof)" $'github\tgithub:me/prof\t' "...with www."
assert_eq "$(r https://github.com/me/prof/tree/feature/x)" $'github\tgithub:me/prof@feature/x\t' "a branch link (slashes kept)"
assert_eq "$(r https://github.com/me/prof/commit/abc123)" $'github\tgithub:me/prof@abc123\t' "a commit link"
assert_eq "$(r http://github.com/me/prof)" $'github\tgithub:me/prof\t' "an http GitHub link: GitHub's https download anyway"
# other links
assert_eq "$(r https://example.com/p.tar.gz)" $'url\thttps://example.com/p.tar.gz\t' "an archive link"
assert_eq "$(r https://example.com/page)" $'url\thttps://example.com/page\t' "any other https link: fetch decides"
assert_eq "$(r https://gitlab.com/me/prof.git)" $'git\thttps://gitlab.com/me/prof.git\t' "a .git link: git"
assert_eq "$(r git+https://example.com/p)" $'git\tgit+https://example.com/p\t' "git+ link"
assert_eq "$(r git@example.com:me/p.git)" $'git\tgit@example.com:me/p.git\t' "ssh shorthand"
out=$(r http://example.com/p.tar.gz); assert_contains "$out" "use an https:// link" "plain http refused"
assert_eq "$(DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" resolve http://127.0.0.1:8/p.zip)" $'url\thttp://127.0.0.1:8/p.zip\t' "tests may use http to 127.0.0.1"
# local paths win, and say so when it could have been GitHub
mkdir -p "$T_TMP/w/me/prof"; : > "$T_TMP/w/me/prof/profile.toml"; : > "$T_TMP/w/p.tar.gz"; : > "$T_TMP/w/notes.txt"
cd "$T_TMP/w" || exit 1
assert_eq "$(r me/prof)" $'dir\t'"$T_TMP/w/me/prof"$'\tusing the folder me/prof; for GitHub, write github:me/prof' "a folder named like owner/repo: local wins, with a note"
assert_eq "$(r ./p.tar.gz)" $'archive\t'"$T_TMP/w/p.tar.gz"$'\t' "a local archive"
assert_eq "$(HOME=$T_TMP/w r '~/p.tar.gz')" $'archive\t'"$T_TMP/w/p.tar.gz"$'\t' "~ expanded"
out=$(r notes.txt); assert_contains "$out" "not a folder or a .tar.gz/.tgz/.zip" "another kind of file: refused"
out=$(r nothing-here); assert_contains "$out" "not found here, and not a link or owner/name" "nothing matches: says so"
cd "$REPO" || exit 1
t_done
