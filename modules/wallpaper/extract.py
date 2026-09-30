#!/usr/bin/env python3
"""extract.py STOCK_GRESOURCE OUTDIR: unpack the theme, append the background rule, write the xml."""
import os, sys
from gi.repository import Gio
PFX = "/org/gnome/shell/theme/"
RULE = """
/* decal: login background */
#lockDialogGroup {
  background: #222226 url("resource:///org/gnome/shell/theme/decal-background.jpg");
  background-size: cover;
  background-repeat: no-repeat;
  background-position: center; }
"""
stock, out = sys.argv[1], sys.argv[2]
r = Gio.Resource.load(stock)
def walk(p):
    for c in r.enumerate_children(p, 0):
        yield from (walk(p + c) if c.endswith("/") else [p + c])
entries = []
if any(f.endswith("/decal-background.jpg") for f in walk(PFX)):
    sys.exit(f"{stock} already contains the decal background (read through an active mount?); refusing to patch it twice")
for f in walk(PFX):
    rel = f[len(PFX):]; dst = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as fh: fh.write(r.lookup_data(f, 0).get_data())
    entries.append(rel)
for css in ("gnome-shell-dark.css", "gnome-shell-light.css"):
    p = os.path.join(out, css)
    if os.path.exists(p):
        with open(p, "a") as fh: fh.write(RULE)
entries.append("decal-background.jpg")
with open(os.path.join(out, "gnome-shell-theme.gresource.xml"), "w") as fh:
    fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<gresources>\n  <gresource prefix="/org/gnome/shell/theme">\n')
    fh.writelines(f"    <file>{e}</file>\n" for e in entries)
    fh.write("  </gresource>\n</gresources>\n")
