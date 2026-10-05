#!/usr/bin/env python3
"""drive_ui.py TRANSCRIPT CMD... -- KEY... : run CMD in a pseudo-terminal (80x30) and type KEYs one by one, each once
the screen has settled. KEY: a literal string, or ENTER, ESC, SPACE, UP, DOWN, END, WAIT (a longer pause), UNTIL:TEXT
(until TEXT shows again after the last key: curses redraws only what changed, so pick text the awaited screen draws whole). Writes everything the program printed (escape codes
removed) to TRANSCRIPT; exits with the program's status, or 125 when an UNTIL's TEXT never showed (the program is
stopped: a lost key fails the test instead of passing it by accident)."""
import os, pty, re, select, struct, sys, time, fcntl, termios

i = sys.argv.index("--")
out, cmd, keys = sys.argv[1], sys.argv[2:i], sys.argv[i + 1:]
NAMES = {"ENTER": "\r", "ESC": "\x1b", "SPACE": " ", "UP": "\x1b[A", "DOWN": "\x1b[B", "TAB": "\t", "END": "\x1b[F"}

pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM="xterm-256color", LINES="30", COLUMNS="80")
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 80, 0, 0))
buf = b""
seen = {}   # how many times the awaited text had shown when the last key was sent


def plain(b):
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", b).decode("utf-8", "replace")


def drain(quiet=0.6, limit=60.0):
    """read until nothing new for `quiet` seconds"""
    global buf
    end = time.time() + limit
    last = time.time()
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            buf += data; last = time.time()
        elif time.time() - last > quiet:
            return True
    return True


drain(1.5)
def until(text, limit=20.0):
    """read until TEXT shows more often than it had when the last key was sent; None when it never does"""
    global buf
    end = time.time() + limit
    while time.time() < end:
        if plain(buf).count(text) > seen.get(text, 0):
            return drain(0.3)
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return None   # the program ended before TEXT showed
            if not data:
                return None
            buf += data
    return None


missed = None
for k in keys:
    if k == "WAIT":
        drain(3.0); continue
    if k.startswith("UNTIL:"):
        r = until(k[6:])
        if r is None:
            missed = k[6:]; os.kill(pid, 9); break
        continue
    seen = {t[6:]: plain(buf).count(t[6:]) for t in keys if t.startswith("UNTIL:")}
    os.write(fd, NAMES.get(k, k).encode())
    if not drain():
        break
drain(1.0, 10)
try:   # the terminal closes a moment before the process has finished exiting: give it a few seconds
    for _ in range(50):
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            break
        time.sleep(0.1)
    if done:
        code = os.waitstatus_to_exitcode(status)
    else:
        os.kill(pid, 9); os.waitpid(pid, 0); code = 124
except ChildProcessError:
    code = 0
text = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Z0-9]|\x1b[=>]", b" ", buf).decode("utf-8", "replace")
if missed is not None:
    text += f"\n[drive_ui: never showed: {missed}]\n"; code = 125
open(out, "w").write(text)
sys.exit(code)
