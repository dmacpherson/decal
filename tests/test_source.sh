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
assert_eq "$(r file:///srv/p.git)" $'git\tfile:///srv/p.git\t' "a file:// git URL"
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
# unpacking: the two real shapes (GitHub's archive with a pax header and one top folder; a stamp with ./profile.toml)
U="$T_TMP/u"; mkdir -p "$U/gh/me-prof-abc123" "$U/st"
printf '[p]\n' > "$U/gh/me-prof-abc123/profile.toml"; printf '[p]\n' > "$U/st/profile.toml"; echo hi > "$U/st/wall.txt"
tar --format=pax -czf "$U/gh.tar.gz" -C "$U/gh" me-prof-abc123; tar -czf "$U/st.tgz" -C "$U/st" .
(cd "$U/st" && python3 -c 'import zipfile; z=zipfile.ZipFile("../st.zip","w"); z.write("profile.toml"); z.write("wall.txt"); z.close()')
python3 "$SRC" unpack "$U/gh.tar.gz" "$U/o1"; assert_file "$U/o1/me-prof-abc123/profile.toml" "GitHub-style tarball unpacked"
python3 "$SRC" unpack "$U/st.tgz" "$U/o2"; assert_eq "$(cat "$U/o2/wall.txt")" "hi" "stamp tarball (./ names) unpacked"
python3 "$SRC" unpack "$U/st.zip" "$U/o3"; assert_file "$U/o3/profile.toml" "zip unpacked"
# unsafe archives: refused, nothing written outside the target
mk_tar='import io,tarfile,sys
t=tarfile.open(sys.argv[1],"w:gz")
def f(n,data=b"x"):
  i=tarfile.TarInfo(n); i.size=len(data); t.addfile(i,io.BytesIO(data))'
python3 -c "$mk_tar"'
f("../escaped.txt"); t.close()' "$U/dotdot.tgz"; out=$(python3 "$SRC" unpack "$U/dotdot.tgz" "$U/t1" 2>&1); rc=$?
assert_eq "$rc" "1" "../ member: refused"; assert_contains "$out" "points outside the archive" "...says why"; assert_nofile "$U/escaped.txt" "...nothing written outside"
python3 -c "$mk_tar"'
f("/tmp/abs-decal-test.txt"); t.close()' "$U/abs.tgz"; out=$(python3 "$SRC" unpack "$U/abs.tgz" "$U/t2" 2>&1)
assert_contains "$out" "an absolute path" "absolute path: refused"; assert_nofile /tmp/abs-decal-test.txt "...not written"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("link"); i.type=tarfile.SYMTYPE; i.linkname="/etc/passwd"; t.addfile(i); t.close()' "$U/sym.tgz"
out=$(python3 "$SRC" unpack "$U/sym.tgz" "$U/t3" 2>&1); assert_contains "$out" "links and special files aren't allowed" "symlink: refused"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("hard"); i.type=tarfile.LNKTYPE; i.linkname="x"; t.addfile(i); t.close()' "$U/hard.tgz"
out=$(python3 "$SRC" unpack "$U/hard.tgz" "$U/t4" 2>&1); assert_contains "$out" "links and special files aren't allowed" "hardlink: refused"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("dev"); i.type=tarfile.CHRTYPE; t.addfile(i); t.close()' "$U/dev.tgz"
out=$(python3 "$SRC" unpack "$U/dev.tgz" "$U/t5" 2>&1); assert_contains "$out" "links and special files aren't allowed" "device: refused"
python3 -c 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("../../zip-escaped.txt","x"); z.close()' "$U/slip.zip"
out=$(python3 "$SRC" unpack "$U/slip.zip" "$U/t6" 2>&1); assert_contains "$out" "points outside the archive" "zip slip: refused"
head -c 3000 /dev/zero > "$U/big"; tar -czf "$U/big.tgz" -C "$U" big
out=$(DECAL_UNPACK_LIMIT=1000 python3 "$SRC" unpack "$U/big.tgz" "$U/t7" 2>&1); assert_contains "$out" "more than" "over the size limit: refused"
echo "not an archive" > "$U/plain.tgz"; out=$(python3 "$SRC" unpack "$U/plain.tgz" "$U/t8" 2>&1)
assert_contains "$out" "not an archive" "not an archive: says so"
# themes: .tar.xz/.tar.bz2/.tar too, and (only when asked) links that stay inside
mkdir -p "$U/th/T/cursors"; echo c > "$U/th/T/cursors/left_ptr"; ln -s left_ptr "$U/th/T/cursors/default"; ln -s ../index.theme "$U/th/T/cursors/up"
echo i > "$U/th/T/index.theme"
for c in J j ""; do tar -c${c}f "$U/th$c.tar" -C "$U/th" T; done
for c in J j ""; do python3 "$SRC" unpack --links inside "$U/th$c.tar" "$U/o-th$c" 2>/dev/null; assert_eq "$(cat "$U/o-th$c/T/cursors/default")" "c" "theme archive ($c) with inside links unpacked"; done
out=$(python3 "$SRC" unpack "$U/thJ.tar" "$U/o-nolinks" 2>&1); assert_contains "$out" "links and special files aren't allowed" "links refused unless asked for"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("evil"); i.type=tarfile.SYMTYPE; i.linkname="../../../../etc/passwd"; t.addfile(i); t.close()' "$U/esc.tgz"
out=$(python3 "$SRC" unpack --links inside "$U/esc.tgz" "$U/t9" 2>&1); assert_contains "$out" "points outside the archive" "a link out: refused even when links are allowed"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("abs"); i.type=tarfile.SYMTYPE; i.linkname="/etc/passwd"; t.addfile(i); t.close()' "$U/abs2.tgz"
out=$(python3 "$SRC" unpack --links inside "$U/abs2.tgz" "$U/t10" 2>&1); assert_contains "$out" "points outside the archive" "an absolute link: refused"
# a chain of links can't walk out: x -> ., then x/y -> .. (looks inside on paper), then a file written through y
mkdir -p "$U/up/t11"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("x"); i.type=tarfile.SYMTYPE; i.linkname="."; t.addfile(i)
i=tarfile.TarInfo("x/y"); i.type=tarfile.SYMTYPE; i.linkname=".."; t.addfile(i)
f("y/evil.txt")
i=tarfile.TarInfo("h"); i.type=tarfile.LNKTYPE; i.linkname="y/secret.txt"; t.addfile(i); t.close()' "$U/chain.tgz"
echo SECRET > "$U/up/secret.txt"
out=$(python3 "$SRC" unpack --links inside "$U/chain.tgz" "$U/up/t11" 2>&1); assert_eq "$?" "1" "a link chain out: refused"
assert_nofile "$U/up/evil.txt" "...nothing written outside"; assert_nofile "$U/up/t11/h" "...nothing copied in from outside"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("l"); i.type=tarfile.SYMTYPE; i.linkname="."; t.addfile(i)
i=tarfile.TarInfo("l/l/l/m"); i.type=tarfile.SYMTYPE; i.linkname="../../.."; t.addfile(i)
f("m/.bashrc"); t.close()' "$U/chain2.tgz"
mkdir -p "$U/deep/a/b/c"; out=$(python3 "$SRC" unpack --links inside "$U/chain2.tgz" "$U/deep/a/b/c" 2>&1)
assert_nofile "$U/deep/.bashrc" "the reviewer's chain: nothing written above"

# fetch over a local web server (tests only: http to 127.0.0.1)
mkdir -p "$U/www"; cp "$U/st.zip" "$U/www/p.zip"; echo "<html>hi</html>" > "$U/www/page"
(cd "$U/www" && exec python3 -u -m http.server 0 --bind 127.0.0.1 > "$U/http.log" 2>&1) & WPID=$!
for _ in $(seq 50); do PORT=$(grep -o 'port [0-9]*' "$U/http.log" | grep -o '[0-9]*'); [[ -n $PORT ]] && break; sleep 0.1; done
W="http://127.0.0.1:$PORT"
assert_eq "$(DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" fetch "$W/p.zip" "$U/f1")" "archive" "fetch: an archive link is unpacked"
assert_file "$U/f1/profile.toml" "...into the folder"
DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" fetch "$W/page" "$U/f2" >/dev/null 2>&1; assert_eq "$?" "3" "fetch: not an archive: exit 3 (try git)"
out=$(DECAL_ALLOW_HTTP_LOCAL= python3 "$SRC" fetch "$W/p.zip" "$U/f3" 2>&1); assert_contains "$out" "use an https:// link" "fetch: plain http refused"
kill "$WPID" 2>/dev/null

# recently used, and whose it is
python3 "$SRC" remember github:friend/setup; python3 "$SRC" remember "$T_TMP/w/p.tar.gz"; python3 "$SRC" remember github:friend/setup
assert_eq "$(cut -f1 "$DECAL_USER_STATE/recent" | tr '\n' ' ')" "github:friend/setup $T_TMP/w/p.tar.gz " "recent: newest first, no duplicates"
for i in $(seq 12); do python3 "$SRC" remember "github:x/r$i"; done
assert_eq "$(wc -l < "$DECAL_USER_STATE/recent")" "10" "recent: 10 kept"
y() { python3 "$SRC" yours "$@"; echo $?; }
assert_eq "$(y "$T_TMP/w/p.tar.gz")" "0" "yours: a local path"
assert_eq "$(y file:///srv/p.git)" "0" "yours: a git repo on this machine"
assert_eq "$(y github:x/r12)" "0" "yours: recently used"
assert_eq "$(y github:me/prof --login me)" "0" "yours: your GitHub account's"
assert_eq "$(y github:me/prof --login Me)" "0" "...any letter case"
assert_eq "$(y github:stranger/prof --login me)" "1" "not yours: someone else's repo"
assert_eq "$(y https://example.com/p.zip)" "1" "not yours: a link"
t_done
