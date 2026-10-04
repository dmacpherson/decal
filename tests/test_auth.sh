#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN
A="$REPO/lib/auth.py"
py() { python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import auth; $1"; }

# the QR code: half-blocks that decode back to qrcodegen's own matrix for the link (2-module quiet zone)
out=$(py '
import qrcodegen, re
url = "https://github.com/login/device"
q = qrcodegen.QrCode.encode_text(url, qrcodegen.QrCode.Ecc.LOW)
rows = [re.sub(r"\x1b\[[0-9;]*m", "", r) for r in auth.qr_lines(url)]
n, b = q.get_size(), 2
ok = len(rows) == (n + 2 * b + 1) // 2 and all(len(r) == n + 2 * b for r in rows)
for y in range(-b, n + b):
    for x in range(-b, n + b):
        ch = rows[(y + b) // 2][x + b]
        top = (y + b) % 2 == 0
        dark = ch == "█" or (ch == "▀" and top) or (ch == "▄" and not top)
        ok = ok and dark == (0 <= x < n and 0 <= y < n and q.get_module(x, y))
print("ok" if ok else "mismatch", n)')
assert_eq "$out" "ok 25" "QR rows decode to the link's matrix (version 2, 25 modules)"
assert_contains "$(py 'print(repr(auth.qr_lines("x")[0]))')" '\x1b[30;47m' "QR drawn black on white, readable on dark terminals"

# the screen: two columns when wide, stacked when narrow; notes only when they happened
L=$(py 'print("\n".join(auth.layout("me/prof", "read", "WDJB-MJHT", "https://github.com/login/device", ["QQQ"], 100)))')
assert_contains "$L" "Sign in to GitHub so decal can read me/prof" "heading names the repo"
assert_contains "$L" "On this computer                         On your phone" "two columns at 100 wide"
assert_contains "$L" "1. Open  github.com/login/device" "the link, without https://"
assert_contains "$L" "2. Enter WDJB-MJHT" "the code"
assert_contains "$L" "Scan, then enter WDJB-MJHT" "the code under the QR too"
assert_contains "$L" "Esc cancel · t paste a token instead" "the keys"
assert_not_contains "$L" "opened in your browser" "no browser note when it wasn't opened"
assert_not_contains "$L" "copied to your clipboard" "no clipboard note when it wasn't copied"
L=$(py 'print("\n".join(auth.layout("me/prof", "write", "C", "https://github.com/login/device", ["QQQ"], 60, True, True)))')
assert_contains "$L" "so decal can save to me/prof" "write wording"
assert_not_contains "$L" "On this computer                         On your phone" "stacked at 60 wide"
assert_contains "$L" "(opened in your browser)" "browser note"
assert_contains "$L" "(copied to your clipboard)" "clipboard note"

# the pre-filled token page
assert_eq "$(python3 "$A" token-url --need read --days 90)" \
  "https://github.com/settings/personal-access-tokens/new?name=Decal&description=decal%3A+read+your+profile&expires_in=90&contents=read" "read token page"
assert_eq "$(python3 "$A" token-url --need write --days none)" \
  "https://github.com/settings/personal-access-tokens/new?name=Decal&description=decal%3A+save+your+profile&expires_in=none&contents=write&administration=write" "write token page, never expires"
python3 "$A" token-url --need read --days 400 >/dev/null 2>&1; assert_eq "$?" "2" "expiry over 366 days refused"

# the apps: from the environment ("CLIENT_ID:slug"), else built in (none yet: no sign-in offered)
assert_eq "$(DECAL_GITHUB_APP_READ=Iv1.abc:decal python3 "$A" install-url --need read)" "https://github.com/apps/decal/installations/new" "install page"
assert_eq "$(DECAL_GITHUB_APP_WRITE=Iv1.w:decal-write py 'print(auth.app("write"))')" "('Iv1.w', 'decal-write')" "write app from the environment"
assert_eq "$(DECAL_GITHUB_APP_READ=junk py 'print(auth.app("read"))')" "None" "a malformed setting: no app"
# a fake GitHub (localhost): checking a key
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"; echo me/prof > "$G/seed"
fake_up() {  # (re)start the fake GitHub: it reads seed/hidden when it starts
  if [[ -n ${GHPID:-} ]]; then kill "$GHPID" 2>/dev/null; wait "$GHPID" 2>/dev/null; fi
  rm -f "$G/port"; python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
  for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
  export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
}
fake_up
chk() { GITHUB_TOKEN=$1 python3 "$A" check "${@:2}" >/dev/null 2>&1; echo $?; }
assert_eq "$(chk s3cret me/prof --need read)" "0" "check: a good key reads"
assert_eq "$(chk s3cret me/prof --need write)" "0" "check: ...and writes"
assert_eq "$(chk wrong me/prof --need read)" "10" "check: a rejected key"
assert_eq "$(chk s3cret me/nope --need read)" "11" "check: a repo the key can't see"
assert_eq "$(chk s3cret me/nope --need write --may-create)" "0" "check: a repo to be created is fine"
assert_eq "$(chk s3cret decal-tester --need write --may-create)" "0" "check: no owner yet (stamp): the key is checked"
: > "$G/readonly"; assert_eq "$(chk s3cret me/prof --need write)" "12" "check: a read-only key when writing"; rm "$G/readonly"
assert_eq "$(GITHUB_TOKEN=s3cret DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$A" check me/prof --need read >/dev/null 2>&1; echo $?)" "13" "check: GitHub unreachable"
kill "$GHPID" 2>/dev/null
t_done
