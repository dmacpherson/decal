#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# the terminal logo: one shared drawing (lib/logo.sh); install.sh and usb/start.sh carry the same copy
block() { sed -n '/^# --- logo ---$/,/^# --- end logo ---$/p' "$1"; }
assert_eq "$(block "$REPO/install.sh")" "$(block "$REPO/lib/logo.sh")" "install.sh's logo is lib/logo.sh's"
assert_eq "$(block "$REPO/usb/start.sh")" "$(block "$REPO/lib/logo.sh")" "usb/start.sh's logo is lib/logo.sh's"
out=$(bash -c 'source "$1"; logo_print 1 "decal v1" "line two"' _ "$REPO/lib/logo.sh")
assert_eq "$(grep -c $'\e' <<<"$out")" "0" "not a terminal: no colour codes"
assert_contains "$(sed -n 2p <<<"$out")" "██▄███▄██    decal v1" "text beside the second row"
assert_eq "$(wc -l <<<"$out")" "6" "six rows"
tty_out=$(python3 - "$REPO/lib/logo.sh" <<'PY'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.environ.pop("NO_COLOR", None)
    os.execvp("bash", ["bash", "-c", 'source "$1"; logo_print 1 decal', "_", sys.argv[1]])
buf = b""
while True:
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
print(repr(buf.decode()))
PY
)
assert_contains "$tty_out" '\x1b[1;38;5;44m' "a terminal: the first row teal"; assert_contains "$tty_out" '\x1b[1;38;5;135m' "...the last purple"
# decal version read by the menu (not a terminal): just the one line
assert_eq "$("$REPO/decal" version | wc -l)" "1" "decal version, not a terminal: one line"
t_done
