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
kill "$SRV"; wait "$SRV" 2>/dev/null
out=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz" --version v1)
assert_file "$out/Theme-A/index.theme" "pinned release served from cache while offline"
out=$(F "github-release:o/r" --asset "pack-dark-*.tar.gz" --asset "pack-light-*.tar.gz" 2>"$T_TMP/err"); assert_eq "$?" "0" "latest offline with a cached copy rc"
assert_file "$out/Theme-A/index.theme" "latest release offline: last cached release used"
assert_contains "$(cat "$T_TMP/err")" "using the cached copy" "latest release offline: says so"
err=$(F "github-release:o/r" --asset "x-*" 2>&1); assert_contains "$err" "download failed" "offline + latest + nothing cached -> clear failure"

# profile path
mkdir -p "$T_TMP/prof/themes/mine"; out=$(F "themes/mine" --profile "$T_TMP/prof")
assert_eq "$out" "$T_TMP/prof/themes/mine" "profile path"
err=$(F "themes/none" --profile "$T_TMP/prof" 2>&1); assert_contains "$err" "not found" "missing profile path"

# ls_fetch dry-run downloads nothing
source "$REPO/lib/common.sh"; LS_REPO="$REPO"; export PROFILE_DIR="$T_TMP/prof"
out=$(LS_DRY_RUN=1 ls_fetch "git+file://$T_TMP/repo" 2>/dev/null); assert_eq "$(ls -A "$out")" "" "dry-run returns an empty dir"
t_done
