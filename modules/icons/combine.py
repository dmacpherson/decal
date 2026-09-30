#!/usr/bin/env python3
"""combine.py BASE FOLDERS OUT NAME : icon theme = BASE (symlinked) with FOLDERS' places/ icons on top."""
import configparser, os, shutil, sys

base, folders, out, name = sys.argv[1:5]
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
for entry in os.listdir(base):
    if entry in ("places", "index.theme", "icon-theme.cache"):
        continue
    os.symlink(os.path.join(base, entry), os.path.join(out, entry))


def overlay(src_root, dst_root):
    for root, _dirs, files in os.walk(src_root):
        d = os.path.join(dst_root, os.path.relpath(root, src_root))
        os.makedirs(d, exist_ok=True)
        for f in files:
            t = os.path.join(d, f)
            if os.path.lexists(t):
                os.unlink(t)
            os.symlink(os.path.join(root, f), t)


for src in (base, folders):
    p = os.path.join(src, "places")
    if os.path.isdir(p):
        overlay(p, os.path.join(out, "places"))


def read(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(path, encoding="utf-8")
    return cp


cp, fp = read(os.path.join(base, "index.theme")), read(os.path.join(folders, "index.theme"))
cp["Icon Theme"]["Name"] = name
dirs = [d for d in cp["Icon Theme"].get("Directories", "").split(",") if d]
for d in [d for d in fp["Icon Theme"].get("Directories", "").split(",") if d] if fp.has_section("Icon Theme") else []:
    if d not in dirs and fp.has_section(d):
        dirs.append(d)
        cp[d] = dict(fp[d])
cp["Icon Theme"]["Directories"] = ",".join(dirs)
with open(os.path.join(out, "index.theme"), "w", encoding="utf-8") as f:
    cp.write(f, space_around_delimiters=False)
