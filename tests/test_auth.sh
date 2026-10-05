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
# asking: a terminal stand-in (a file of keystrokes in, a file out), the fake server's two apps
export DECAL_GITHUB_APP_READ=Iv-read:decal DECAL_GITHUB_APP_WRITE=Iv-write:decal-write DECAL_AUTH_RECHECK=0 COLUMNS=100
ask() {  # ask KEYS ARGS... : run auth.py get with KEYS as the typing; key on stdout, screen in $T_TMP/screen
  printf "$1" > "$T_TMP/keys"; : > "$G/device_log"
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" python3 "$A" get "${@:2}"
}
touch "$T_TMP/before"
printf 'pending\nslow\nok\n' > "$G/device_script"
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "sign in: the key, after pending and slow_down"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "1) Sign in with GitHub" "the choice offers signing in"
assert_contains "$S" "2. Enter WDJB-MJHT" "the code"
assert_contains "$S" "On your phone" "the phone column"
assert_contains "$S" "Signed in." "says it worked"
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-read" "reading uses the Decal Profile app"
assert_eq "$(grep -c '^poll' "$G/device_log")" "3" "polled until approved"
assert_eq "$(find "$HOME" -type f -newer "$T_TMP/before" | wc -l)" "0" "nothing saved under HOME"
printf 'ok\n' > "$G/device_script"
ask '1\n' me/prof --need write >/dev/null
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-write" "writing uses the Decal Profile Write app"

# the app isn't installed on the repo yet: the install link, then it carries on by itself (no new code)
printf 'ok\n' > "$G/device_script"; echo "me/prof 3" > "$G/hidden"; fake_up
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "not installed yet: the key once it is"
assert_contains "$(cat "$T_TMP/screen")" "Decal Profile can't see me/prof yet: install it on that repo" "says what to do"
assert_contains "$(cat "$T_TMP/screen")" "$DECAL_GITHUB/apps/decal/installations/new" "with the install link"
assert_eq "$(grep -c '^code' "$G/device_log")" "1" "one code only"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "Scan to install from your phone" "a QR code for installing from the phone"
assert_contains "$S" '2. Choose "Only select' "the steps: which repos"
assert_contains "$S" 'repositories": prof' "...and which repo"
assert_contains "$S" "   (the link below)" "no browser: points at the link"
assert_eq "$(grep -c 'On your phone' "$T_TMP/screen")" "2" "two-column screens: signing in, then installing"
# with a desktop: the install page opens in the browser too
echo "me/prof 2" > "$G/hidden"; fake_up; printf 'ok\n' > "$G/device_script"; stub xdg-open; stub xclip 'exit 1'; : > "$STUBS/calls"
assert_eq "$(DISPLAY=:99 ask '1\n' me/prof --need read)" "s3cret" "with a desktop: signed in"
assert_contains "$(calls)" "xdg-open $DECAL_GITHUB/apps/decal/installations/new" "the install page opened in the browser"
assert_eq "$(grep -c '(opened in your browser)' "$T_TMP/screen")" "2" "both pages say they opened"
rm -f "$STUBS/xdg-open" "$STUBS/xclip" "$G/hidden"; fake_up
# never visible (misspelled?): gives up on its own
echo "me/prof forever" > "$G/hidden"; fake_up
printf 'ok\nok\n' > "$G/device_script"
out=$(DECAL_AUTH_WAIT=0 ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "never visible: no key"
assert_contains "$(cat "$T_TMP/screen")" "still can't see me/prof: check the name" "says the name may be wrong"
rm "$G/hidden"; fake_up

# the code expires: a new one; denied: back to the choice; Esc: back to the choice
printf 'expired\nok\n' > "$G/device_script"
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "expired: signed in with a new code"
assert_contains "$(cat "$T_TMP/screen")" "The code expired" "says so"; assert_eq "$(grep -c '^code' "$G/device_log")" "2" "two codes"
printf 'denied\n' > "$G/device_script"
out=$(ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "denied, then cancel: no key"
assert_contains "$(cat "$T_TMP/screen")" "Sign-in was denied on GitHub." "says it was denied"
assert_eq "$(grep -c 'Sign in with GitHub' "$T_TMP/screen")" "2" "back to the choice after denying"
printf 'pending\n' > "$G/device_script"
out=$(ask '1\n\x1b3\n' me/prof --need read); assert_eq "$?" "1" "Esc while waiting, then cancel"
: > "$G/device_fail"
out=$(ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "the code request fails: no key"
assert_contains "$(cat "$T_TMP/screen")" "GitHub didn't start a sign-in" "plain words, no traceback"
assert_not_contains "$(cat "$T_TMP/screen")" "Traceback" "no traceback on screen"
rm "$G/device_fail"

# make a token myself: expiry, the page, a wrong paste, then a good one (spaces trimmed); t while waiting gets here too
assert_eq "$(ask '2\n\nwrong\n  s3cret  \n' me/prof --need read)" "s3cret" "a pasted token, after a wrong one"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "90 days   (default)" "expiry choice"
assert_contains "$S" "expires_in=90&contents=read" "the pre-filled page, 90 days"
assert_contains "$S" 'choose "Only select repositories" and pick prof' "which repo to pick"
assert_contains "$S" "GitHub didn't accept that key" "the wrong paste explained"
assert_contains "$(ask '2\n4\ns3cret\n' me/prof --need write --may-create; cat "$T_TMP/screen")" "expires_in=none&contents=write&administration=write" "never expires; writing"
assert_contains "$(cat "$T_TMP/screen")" 'choose "All repositories"' "a repo decal may create: all repositories"
printf 'pending\n' > "$G/device_script"
assert_eq "$(ask '1\nt\ns3cret\n' me/prof --need read)" "s3cret" "t while waiting: paste a token instead"
assert_eq "$(DECAL_GITHUB_APP_READ= ask '1\n\ns3cret\n' me/prof --need read)" "s3cret" "no app configured: 1 is make a token"
assert_not_contains "$(cat "$T_TMP/screen")" "Sign in with GitHub" "...and signing in isn't offered"

# no terminal: fails with how to fix it; Ctrl+C: exits 130, no traceback
out=$(DECAL_TTY_IN=/nonexistent python3 "$A" get me/prof --need read 2>&1); assert_eq "$?" "1" "no terminal: fails"
assert_contains "$out" "set GITHUB_TOKEN or log in with gh auth login" "...and says how to fix it"
mkfifo "$T_TMP/fifo"; ( sleep 30 > "$T_TMP/fifo" ) & HOLD=$!
# (bash starts background jobs with Ctrl+C ignored; put Python's handler back, as a foreground run has it)
DECAL_TTY_IN="$T_TMP/fifo" DECAL_TTY_OUT="$T_TMP/screen" python3 -c 'import runpy, signal, sys
signal.signal(signal.SIGINT, signal.default_int_handler); sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name="__main__")' \
  "$A" get me/prof --need read > /dev/null 2> "$T_TMP/err" & P=$!
sleep 1; kill -INT "$P"; wait "$P"; assert_eq "$?" "130" "Ctrl+C: exit 130"
assert_not_contains "$(cat "$T_TMP/err")" "Traceback" "Ctrl+C: no traceback"; kill "$HOLD" 2>/dev/null
# a real terminal (a pty): key-at-a-time mode while waiting, Esc back to the choice, echo restored afterwards
echo hold > "$G/device_script"
out=$(DECAL_AUTH_RECHECK=0 python3 - "$A" <<'PY'
import os, pty, select, sys, termios, time
pid, fd = pty.fork()
if pid == 0:
    os.environ.pop("DECAL_TTY_IN", None); os.environ.pop("DECAL_TTY_OUT", None)
    os.execvp("python3", ["python3", sys.argv[1], "get", "me/prof", "--need", "read"])
def until(text, secs=10):
    buf, end = b"", time.time() + secs
    while time.time() < end and text.encode() not in buf:
        if select.select([fd], [], [], max(0, end - time.time()))[0]:
            try: buf += os.read(fd, 4096)
            except OSError: break
    return text.encode() in buf
ok = until("Choose [1]: "); os.write(fd, b"1\n")
ok = ok and until("Waiting for GitHub"); time.sleep(0.5); waiting_echo = bool(termios.tcgetattr(fd)[3] & termios.ECHO)
os.write(fd, b"\x1b"); ok = ok and until("Choose [1]: "); os.write(fd, b"3\n")
if not ok:
    os.kill(pid, 9)   # stuck: fail instead of hanging
_, st = os.waitpid(pid, 0)
print("ok" if ok else "stuck", "echo-while-waiting" if waiting_echo else "no-echo-while-waiting",
      "echo-after" if termios.tcgetattr(fd)[3] & termios.ECHO else "no-echo-after", os.waitstatus_to_exitcode(st))
PY
)
assert_eq "$out" "ok no-echo-while-waiting echo-after 1" "real terminal: Esc works, echo off while waiting and back on after"
# saving to a repo the Write app can't see (installed on picked repos only): wait for the install, as reading does
fake_up; echo "selected" > "$G/installations"
assert_eq "$(chk s3cret me/new --need write --may-create)" "11" "check: a new repo, app on picked repos: can't create it"
assert_eq "$(chk s3cret decal-tester --need write --may-create)" "11" "check: no owner yet: the owner is looked up, same answer"
echo "all" > "$G/installations"
assert_eq "$(chk s3cret me/new --need write --may-create)" "0" "check: a new repo, app on all repos: fine"
echo "selected 2" > "$G/installations"; fake_up; echo ok > "$G/device_script"
assert_eq "$(ask '1\n' decal-tester --need write --may-create)" "s3cret" "stamp sign-in: waits until the app can create the repo"
assert_contains "$(cat "$T_TMP/screen")" "Decal Profile Write can't see tester/decal-tester yet" "says so, with the owner"
assert_contains "$(cat "$T_TMP/screen")" '2. Choose "All repositories"' "a repo decal may create: all repositories"
rm -f "$G/installations"; fake_up

# a captive portal (HTML instead of GitHub's answer): plain words, no traceback
: > "$G/html"; fake_up
out=$(GITHUB_TOKEN=s3cret python3 "$A" check me/prof --need read 2>&1); assert_eq "$?" "13" "check: an HTML answer counts as not reaching GitHub"
assert_not_contains "$out" "Traceback" "check: no traceback"
out=$(ask '1\n3\n' me/prof --need read 2>&1); assert_eq "$?" "1" "sign in: an HTML answer: no key"
assert_contains "$(cat "$T_TMP/screen")" "couldn't reach GitHub" "sign in: says it couldn't reach GitHub"
assert_not_contains "$out$(cat "$T_TMP/screen")" "Traceback" "sign in: no traceback"
rm "$G/html"; fake_up

# a network blip while waiting for the install: keep waiting, keep the approved key
echo "drop 1" > "$G/drop"; fake_up; echo ok > "$G/device_script"
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "a blip during the install wait: still signed in"
rm "$G/drop"; fake_up
echo ok > "$G/device_script"
assert_eq "$(ask '1\n' - --need read)" "s3cret" "sign in without a repo (to list your profiles)"
assert_contains "$(cat "$T_TMP/screen")" "so decal can read your profiles" "...says what for"
kill "$GHPID" 2>/dev/null
t_done
