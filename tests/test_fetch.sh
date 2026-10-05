#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export DECAL_CACHE="$T_TMP/cache"
F() { python3 "$REPO/lib/fetch.py" "$@"; }
g() { git -C "$T_TMP/repo" -c user.name=t -c user.email=t@t "$@"; }

# git: sparse path (with a space), pinned ref never refetches, unpinned refreshes
mkdir -p "$T_TMP/repo/Icons A/Theme-One" "$T_TMP/repo/other"
echo v1 > "$T_TMP/repo/Icons A/Theme-One/index.theme"; echo nope > "$T_TMP/repo/other/big.bin"
g init -q; g add -A; g commit -qm one; sha1=$(g rev-parse HEAD)
out=$(F "git+file://$T_TMP/repo" --path "Icons A")
assert_eq "$(cat "$out/Theme-One/index.theme")" "v1" "git sparse path"
assert_nofile "$(dirname "$out")/other" "only the requested path is checked out"
echo v2 > "$T_TMP/repo/Icons A/Theme-One/index.theme"; g commit -qam two
out=$(F "git+file://$T_TMP/repo" --path "Icons A" --ref "$sha1")
assert_eq "$(cat "$out/Theme-One/index.theme")" "v1" "pinned ref"
echo v3 > "$T_TMP/repo/Icons A/Theme-One/index.theme"; g commit -qam three
out=$(F "git+file://$T_TMP/repo" --path "Icons A" --ref "$sha1")
assert_eq "$(cat "$out/Theme-One/index.theme")" "v1" "pinned ref is never refetched"
out=$(F "git+file://$T_TMP/repo" --path "Icons A")
assert_eq "$(cat "$out/Theme-One/index.theme")" "v3" "unpinned source refreshes"
err=$(F "git+file://$T_TMP/repo" --path "No Such" 2>&1); assert_eq "$?" "1" "missing path rc"
assert_contains "$err" "'No Such' not found" "missing path message"
mv "$T_TMP/repo" "$T_TMP/repo.away"   # "offline": the remote can't be reached
out=$(F "git+file://$T_TMP/repo" --path "Icons A" 2>"$T_TMP/err"); assert_eq "$?" "0" "unpinned git offline with a cached copy rc"
assert_eq "$(cat "$out/Theme-One/index.theme")" "v3" "unpinned git offline: cached copy used"
assert_contains "$(cat "$T_TMP/err")" "using the cached copy" "unpinned git offline: says so"
mv "$T_TMP/repo.away" "$T_TMP/repo"

# github-release + https via the fake server
mkdir -p "$T_TMP/srv/release/pack/Theme-A/cursors" "$T_TMP/srv/files"
echo i > "$T_TMP/srv/release/pack/Theme-A/index.theme"
tar -czf "$T_TMP/srv/release/pack-dark-v1.tar.gz" -C "$T_TMP/srv/release/pack" Theme-A
tar -czf "$T_TMP/srv/release/pack-light-v1.tar.gz" -C "$T_TMP/srv/release/pack" Theme-A
rm -rf "$T_TMP/srv/release/pack"; echo "fake jpeg" > "$T_TMP/srv/files/w.jpg"
python3 "$REPO/tests/fixtures/fake_github.py" "$T_TMP/srv" > "$T_TMP/port" & SRV=$!
for _ in $(seq 50); do [[ -s $T_TMP/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$T_TMP/port")"
out=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz")
assert_file "$out/Theme-A/index.theme" "release assets extracted"
err=$(F "github-release:o/r" --asset "nomatch-*" 2>&1); assert_contains "$err" "no asset matches 'nomatch-*'" "asset glob miss"
assert_contains "$err" "pack-dark-v1.tar.gz" "lists available assets"
img=$(F "$DECAL_GITHUB/files/w.jpg"); assert_eq "$(cat "$img")" "fake jpeg" "single file download kept as file"
echo two > "$T_TMP/srv/files/w2.jpg"; out=$(DECAL_ALLOW_HTTP_LOCAL= F "$DECAL_GITHUB/files/w2.jpg" 2>&1); assert_contains "$out" "use an https:// link" "plain http refused (tests allow 127.0.0.1 only on purpose)"
mkdir -p "$T_TMP/srv/esc"; ln -s /etc/passwd "$T_TMP/srv/esc/pw"; tar -czf "$T_TMP/srv/files/esc.tar.gz" -C "$T_TMP/srv/esc" pw
out=$(F "$DECAL_GITHUB/files/esc.tar.gz" 2>&1); assert_eq "$?" "1" "an archive with a link out: refused"
assert_contains "$out" "points outside the archive" "...says why"
kill "$SRV"; wait "$SRV" 2>/dev/null
out=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz" --version v1)
assert_file "$out/Theme-A/index.theme" "pinned release served from cache while offline"
out=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz" 2>"$T_TMP/err"); assert_eq "$?" "0" "latest offline with a cached copy rc"
assert_file "$out/Theme-A/index.theme" "latest release offline: last cached release used"
assert_contains "$(cat "$T_TMP/err")" "using the cached copy" "latest release offline: says so"
err=$(F "github-release:o/r" --asset "x-*" 2>&1); assert_contains "$err" "download failed" "offline + latest + nothing cached -> clear failure"

# prune: one version per source (the last used), nothing unused for 30 days, no half-finished downloads
C="$DECAL_CACHE"; ls "$C" > "$T_TMP/before"
old=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz" --version v1 2>/dev/null)
mkdir -p "$C/rel-0000000000000000"; cp "$old/.decal-source" "$C/rel-0000000000000000/" 2>/dev/null; touch -d '2 days ago' "$C/rel-0000000000000000"
mkdir -p "$C/git-1111111111111111"; echo "git+file:///nowhere path" > "$C/git-1111111111111111/.decal-source"; touch -d '40 days ago' "$C/git-1111111111111111"
mkdir -p "$C/rel-2222222222222222.tmp"
python3 "$REPO/lib/fetch.py" --prune
assert_file "$old/Theme-A/index.theme" "last used version kept"
assert_nofile "$C/rel-0000000000000000" "older version of the same source removed"
assert_nofile "$C/git-1111111111111111" "unused for 30+ days removed"
assert_nofile "$C/rel-2222222222222222.tmp" "half-finished download removed"
assert_file "$(F "git+file://$T_TMP/repo" --path "Icons A" 2>/dev/null)/Theme-One/index.theme" "recently used git source kept"

# profile path
mkdir -p "$T_TMP/prof/themes/mine"; out=$(F "themes/mine" --profile "$T_TMP/prof")
assert_eq "$out" "$T_TMP/prof/themes/mine" "profile path"
err=$(F "themes/none" --profile "$T_TMP/prof" 2>&1); assert_contains "$err" "not found" "missing profile path"

# ls_fetch dry-run downloads nothing
source "$REPO/lib/common.sh"; LS_REPO="$REPO"; export PROFILE_DIR="$T_TMP/prof"
out=$(LS_DRY_RUN=1 ls_fetch "git+file://$T_TMP/repo" 2>/dev/null); assert_eq "$(ls -A "$out")" "" "dry-run returns an empty dir"
export LS_RUNTMP="$T_TMP/rt"; mkdir -p "$LS_RUNTMP"
out=$(LS_DRY_RUN=1 ls_fetch "git+file://$T_TMP/repo" 2>/dev/null)
assert_eq "$(dirname "$out")" "$LS_RUNTMP" "dry-run placeholder lives in the run's temp dir (removed with it)"
t_done
