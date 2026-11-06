#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
K="$T_TMP/keys"; mkdir -p "$K"
A=AAAA000000000000000000000000000000000001; B=BBBB000000000000000000000000000000000002
fake_key "$K/a.asc" "$A"; fake_key "$K/b.asc" "$B"; fake_key -b "$K/a.bin" "$A"
fake_key "$K/two.asc" "$A" CCCC000000000000000000000000000000000003; printf 'PUB=%s\n' "$A" > "$K/a-binary-for-dnf"
stub_gpg; stub apt-get; stub dpkg-query 'exit 1'
# downloads are faked: each URL names its key file
fake_fetch() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"; [[ -e $K/${1##*/} ]] || return 1; echo "$K/${1##*/}"; }; }
# rr CMD... : run backend functions the way a module does (platform loaded, downloads faked)
rr() { ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load; fake_fetch; "$@" ); }
R="$DECAL_ROOT"

# dnf: keys pinned to local files named by fingerprint, the repo uses only those (never a key from a URL)
export DECAL_PLATFORM=fedora
rr repo_add demo --key https://x.example/a.asc "$A" --key https://x.example/b.asc "$B" --dnf 'https://x.example/f-$releasever' --repo-gpgcheck 2>/dev/null
assert_eq "$?" "0" "dnf: rc"
assert_eq "$(cat "$R/etc/yum.repos.d/demo.repo")" "[demo]
name=demo (added by decal)
baseurl=https://x.example/f-\$releasever
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/decal-demo-$A.asc file:///etc/pki/rpm-gpg/decal-demo-$B.asc" "dnf: repo file"
assert_eq "$(cat "$R/etc/pki/rpm-gpg/decal-demo-$A.asc")" "$(cat "$K/a.asc")" "dnf: first key written"
assert_file "$R/etc/pki/rpm-gpg/decal-demo-$B.asc" "dnf: second key written"
assert_eq "$(cat "$DECAL_STATE/repos/demo")" "/etc/pki/rpm-gpg/decal-demo-$A.asc
/etc/pki/rpm-gpg/decal-demo-$B.asc
/etc/yum.repos.d/demo.repo" "dnf: recorded"
# again, unchanged: nothing downloaded
: > "$STUBS/calls"; rr repo_add demo --key https://x.example/a.asc "$A" --key https://x.example/b.asc "$B" --dnf 'https://x.example/f-$releasever' --repo-gpgcheck 2>/dev/null
assert_not_contains "$(calls)" "ls_fetch" "dnf: unchanged repo left as is"
# decal learnt another key list (a key dropped): rewritten, the old key file gone
rr repo_add demo --key https://x.example/b.asc "$B" --dnf 'https://x.example/f-$releasever' --repo-gpgcheck 2>/dev/null
assert_nofile "$R/etc/pki/rpm-gpg/decal-demo-$A.asc" "new key list: the old key file removed"
assert_contains "$(cat "$R/etc/yum.repos.d/demo.repo")" "gpgkey=file:///etc/pki/rpm-gpg/decal-demo-$B.asc" "new key list: repo rewritten"
rr repo_remove demo 2>/dev/null
assert_nofile "$R/etc/yum.repos.d/demo.repo" "remove: repo file gone"
assert_nofile "$R/etc/pki/rpm-gpg/decal-demo-$B.asc" "remove: key gone"
assert_nofile "$DECAL_STATE/repos/demo" "remove: record gone"

# fail closed: a key without its fingerprint, a file with two keys, a binary key for dnf: nothing written
for bad in "https://x.example/b.asc $A" "https://x.example/two.asc $A" "https://x.example/a-binary-for-dnf $A"; do
  read -r u f <<<"$bad"
  out=$(rr repo_add demo --key "$u" "$f" --dnf https://x.example/f 2>&1); rc=$?
  assert_eq "$rc" "1" "refused key ($u): rc"
  assert_contains "$out" "nothing added" "refused key ($u): says so"
  assert_nofile "$R/etc/yum.repos.d/demo.repo" "refused key ($u): no repo"
  assert_nofile "$DECAL_STATE/repos/demo" "refused key ($u): no record"
done
out=$(rr repo_add demo --key https://x.example/missing.asc "$A" --dnf https://x.example/f 2>&1)
assert_contains "$out" "could not download" "a failed download: says so"

# apt: the key keeps its format's extension (apt needs it); KEYRING in the line is that key's path
export DECAL_PLATFORM=debian
rr repo_add demo --key https://x.example/a.bin "$A" --apt "deb [signed-by=KEYRING] https://x.example/apt stable main" 2>/dev/null
assert_eq "$(cat "$R/etc/apt/sources.list.d/demo.list")" "deb [signed-by=/usr/share/keyrings/demo-archive-keyring.gpg] https://x.example/apt stable main" "apt: source line"
assert_file "$R/usr/share/keyrings/demo-archive-keyring.gpg" "apt: binary key as .gpg"
rr repo_remove demo 2>/dev/null; assert_nofile "$R/etc/apt/sources.list.d/demo.list" "apt: removed"
rr repo_add demo --key https://x.example/a.asc "$A" --apt "deb [signed-by=KEYRING] https://x.example/apt stable main" 2>/dev/null
assert_file "$R/usr/share/keyrings/demo-archive-keyring.asc" "apt: armored key as .asc"
rr repo_remove demo 2>/dev/null

# set up before decal (by hand, or the vendor's own package as a .sources file): used as is, never removed
mkdir -p "$R/etc/apt/sources.list.d"; echo mine > "$R/etc/apt/sources.list.d/demo.sources"; : > "$STUBS/calls"
out=$(rr repo_add demo --key https://x.example/a.asc "$A" --apt "deb [signed-by=KEYRING] https://x.example/apt stable main" 2>&1)
assert_contains "$out" "already set up" "existing repo: says it's used as is"
assert_nofile "$R/etc/apt/sources.list.d/demo.list" "existing repo: no second source"
assert_not_contains "$(calls)" "ls_fetch" "existing repo: nothing downloaded"
rr repo_remove demo 2>/dev/null; assert_eq "$(cat "$R/etc/apt/sources.list.d/demo.sources")" "mine" "existing repo: never removed"

# Arch: no vendor repos
export DECAL_PLATFORM=arch; : > "$STUBS/calls"
rr repo_add demo --key https://x.example/a.asc "$A" --dnf https://x.example/f --apt "deb x" 2>/dev/null; assert_eq "$?" "0" "arch: rc"
assert_eq "$(calls)" "" "arch: nothing done"
# dry run: nothing written
export DECAL_PLATFORM=fedora
( export LS_DRY_RUN=1; rr repo_add demo --key https://x.example/a.asc "$A" --dnf https://x.example/f ) >/dev/null 2>&1
assert_nofile "$R/etc/yum.repos.d/demo.repo" "dry run: nothing written"
t_done
