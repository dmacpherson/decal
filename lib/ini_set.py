#!/usr/bin/env python3
"""ini_set.py FILE SECTION KEY VALUE [KEY VALUE ...] : print FILE with the keys set in [SECTION] (other lines kept).
ini_set.py --unset FILE SECTION KEY... : print FILE without those keys in [SECTION].
ini_set.py --get FILE SECTION KEY      : print the key's value (exit 1 if it isn't set)."""
import sys

mode = sys.argv[1] if sys.argv[1] in ("--unset", "--get") else "--set"
args = sys.argv[2:] if mode != "--set" else sys.argv[1:]
path, section, kv = args[0], args[1], args[2:]
pairs = list(zip(kv[0::2], kv[1::2])) if mode == "--set" else []
keys = {k for k, _ in pairs} if mode == "--set" else set(kv)
out, in_sec, done = [], False, False


def key_of(s):
    return s.split("=", 1)[0].strip() if "=" in s and not s.startswith("#") else None


def add():
    out.extend(f"{k}={v}" for k, v in pairs)


for line in open(path).read().splitlines():
    s = line.strip()
    if s.startswith("["):
        if in_sec and not done:
            add(); done = True
        in_sec = (s == f"[{section}]")
    if in_sec and key_of(s) in keys:
        if mode == "--get":
            print(s.split("=", 1)[1].strip()); sys.exit(0)
        continue
    out.append(line)
if mode == "--get":
    sys.exit(1)
if mode == "--set":
    if in_sec and not done:
        add(); done = True
    if not done:
        out += ["", f"[{section}]"]; add()
print("\n".join(out))
