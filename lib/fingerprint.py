#!/usr/bin/env python3
"""fingerprint.py MODULE --profile DIR --modules DIR : a hash of everything an `add` of MODULE depends on:
its settings from the profile, the files (and folders) of the profile those settings point to, and decal's own
code for it (the module and lib/). Same hash + the module reporting "installed" = nothing to do."""
import argparse, hashlib, os, re, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("module")
ap.add_argument("--profile", required=True)
ap.add_argument("--modules", required=True)
a = ap.parse_args()
a.profile = os.path.realpath(a.profile)   # the same profile however it is reached (e.g. ~/.config/decal/profile)
lib = os.path.dirname(os.path.abspath(__file__))
h = hashlib.sha256()


def add_tree(path):
    """A folder: names, sizes and modification times (cheap even for big theme folders); a file: its bytes."""
    if os.path.isfile(path):
        with open(path, "rb") as f:
            h.update(f.read())
        return
    for root, dirs, files in os.walk(path):
        dirs[:] = sorted(d for d in dirs if d not in (".git", "__pycache__"))
        for n in sorted(files):
            p = os.path.join(root, n)
            st = os.lstat(p)
            h.update(f"{os.path.relpath(p, path)}\0{st.st_size}\0{st.st_mtime_ns}\n".encode())


env = subprocess.run([sys.executable, os.path.join(lib, "profile.py"), "shell", a.module,
                      "--profile", a.profile, "--modules", a.modules], capture_output=True, text=True)
if env.returncode:
    sys.exit(env.stderr.strip() or "profile.py failed")
h.update(env.stdout.encode())
prof = os.path.realpath(a.profile)
for v in sorted(set(re.findall(r"'([^']+)'|(/[^\s'\"()]+)", env.stdout))):
    p = v[0] or v[1]
    if os.path.isabs(p) and os.path.exists(p) and os.path.realpath(p).startswith(prof + os.sep):
        h.update(p.encode())
        add_tree(p)
# decal's code for it: the module's own folder (contents) and the shared library (contents)
for code in (os.path.join(a.modules, a.module), lib):
    for root, dirs, files in os.walk(code):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for n in sorted(files):
            with open(os.path.join(root, n), "rb") as f:
                h.update(os.path.relpath(os.path.join(root, n), code).encode() + b"\0" + f.read())
print(h.hexdigest())
