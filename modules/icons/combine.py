#!/usr/bin/env python3
"""combine.py BASE OUT NAME [--folders FOLDERS] [--no-symbolic]
Icon theme NAME in OUT = BASE (symlinked, never copied), with FOLDERS' places/ icons on top.
--no-symbolic leaves BASE's *-symbolic icons out and inherits Adwaita first, so GNOME's own UI symbols
(window buttons, back, sidebar...) are used: GTK looks for symbolic names across every inherited theme
before it falls back to full-colour ones."""
import argparse, configparser, os, re, shutil

ap = argparse.ArgumentParser()
ap.add_argument("base")
ap.add_argument("out")
ap.add_argument("name")
ap.add_argument("--folders", default="")
ap.add_argument("--no-symbolic", action="store_true")
a = ap.parse_args()
SKIP = ("index.theme", "icon-theme.cache")


def symbolic(f):  # foo-symbolic.svg, foo-symbolic-rtl.svg (not emblem-symbolic-link.svg)
    return re.search(r"-symbolic(-rtl|-ltr)?(\.[a-z]+)?$", f) is not None


def overlay(src_root, dst_root, skip_symbolic):
    """Mirror src_root's folders under dst_root and symlink each file (replacing what's there)."""
    for root, _dirs, files in os.walk(src_root):
        d = os.path.join(dst_root, os.path.relpath(root, src_root))
        os.makedirs(d, exist_ok=True)
        for f in files:
            if (skip_symbolic and symbolic(f)) or (root == src_root and f in SKIP):
                continue
            t = os.path.join(d, f)
            if os.path.lexists(t):
                os.unlink(t)
            os.symlink(os.path.join(root, f), t)


shutil.rmtree(a.out, ignore_errors=True)
os.makedirs(a.out)
for entry in os.listdir(a.base):
    if entry in SKIP:
        continue
    src = os.path.join(a.base, entry)
    if a.no_symbolic and os.path.isdir(src):
        overlay(src, os.path.join(a.out, entry), True)   # file by file, to leave the symbolic ones out
    elif entry != "places":
        os.symlink(src, os.path.join(a.out, entry))       # whole folder: nothing to leave out
if a.folders and os.path.isdir(os.path.join(a.folders, "places")):
    if not a.no_symbolic:
        overlay(os.path.join(a.base, "places"), os.path.join(a.out, "places"), False)
    overlay(os.path.join(a.folders, "places"), os.path.join(a.out, "places"), a.no_symbolic)
elif not a.no_symbolic and os.path.isdir(os.path.join(a.base, "places")):
    os.symlink(os.path.join(a.base, "places"), os.path.join(a.out, "places"))


def read(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(path, encoding="utf-8")
    return cp


cp = read(os.path.join(a.base, "index.theme"))
it = cp["Icon Theme"]
it["Name"] = a.name
dirs = [d for d in it.get("Directories", "").split(",") if d]
if a.folders:
    fp = read(os.path.join(a.folders, "index.theme"))
    for d in [d for d in fp["Icon Theme"].get("Directories", "").split(",") if d] if fp.has_section("Icon Theme") else []:
        if d not in dirs and fp.has_section(d):
            dirs.append(d)
            cp[d] = dict(fp[d])
it["Directories"] = ",".join(dirs)
if a.no_symbolic:
    inherits = [x for x in it.get("Inherits", "").split(",") if x and x != "Adwaita"]
    it["Inherits"] = ",".join(["Adwaita"] + inherits + ([] if "hicolor" in inherits else ["hicolor"]))
with open(os.path.join(a.out, "index.theme"), "w", encoding="utf-8") as f:
    cp.write(f, space_around_delimiters=False)
