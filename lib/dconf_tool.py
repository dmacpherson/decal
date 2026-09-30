#!/usr/bin/env python3
"""Additive dconf keyfile engine for decal (see spec: Settings rules)."""
import argparse, configparser, fnmatch, json, os, subprocess, sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

RELOCATABLE = [
    ("/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/*/",
     "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"),
    ("/org/gnome/desktop/app-folders/folders/*/", "org.gnome.desktop.app-folders.folder"),
]
REFUSED = ["/org/gnome/desktop/background/"]
NOISE = ["window-size", "window-maximized", "last-shown", "housekeeping", "gsconnect",
         "certificate", "last-connection", "welcome-dialog"]

def warn(msg): print(msg, file=sys.stderr)

def ext_schema_dirs():
    out = []
    for base in (os.path.expanduser("~/.local/share/gnome-shell/extensions"),
                 "/usr/share/gnome-shell/extensions", "/usr/local/share/gnome-shell/extensions"):
        if os.path.isdir(base):
            for e in sorted(os.listdir(base)):
                d = os.path.join(base, e, "schemas")
                if os.path.isfile(os.path.join(d, "gschemas.compiled")):
                    out.append(d)
    return out

def schema_source(with_ext):
    src = Gio.SettingsSchemaSource.get_default()
    for d in (ext_schema_dirs() if with_ext else []):
        try:
            src = Gio.SettingsSchemaSource.new_from_directory(d, src, False)
        except GLib.Error:
            pass
    return src

def schema_for(src, fixed, dirpath):
    if dirpath in fixed:
        return fixed[dirpath]
    for glob, sid in RELOCATABLE:
        if fnmatch.fnmatch(dirpath, glob):
            return src.lookup(sid, True)
    return None

def fixed_map(src):
    m = {}
    for sid in src.list_schemas(True)[0]:
        s = src.lookup(sid, True)
        if s and s.get_path():
            m[s.get_path()] = s
    return m

def read_ini(path, base, subst):
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",),
                                      comment_prefixes=("#",), inline_comment_prefixes=None)
    cp.optionxform = str
    cp.read(path, encoding="utf-8")
    base = base.rstrip("/") + "/"
    for sec in cp.sections():
        d = base if sec.strip("/") == "" else base + sec.strip("/") + "/"
        for k, v in cp.items(sec):
            for a, b in subst.items():
                v = v.replace(a, b)
            yield d, k, v

def resolve(args):
    src = schema_source(args.extensions)
    fixed = fixed_map(src)
    items = []
    for d, k, v in read_ini(args.ini, args.base, args.subst):
        full = d + k
        if any(full.startswith(p) for p in REFUSED):
            items.append(dict(full=full, state="refused")); continue
        s = schema_for(src, fixed, d)
        if s is None or not s.has_key(k):
            items.append(dict(full=full, state="n/a")); continue
        vt = s.get_key(k).get_value_type()
        try:
            val = GLib.Variant.parse(vt, v, None, None)
        except GLib.Error as e:
            items.append(dict(full=full, state="n/a", why=e.message)); continue
        items.append(dict(full=full, state="ok", dir=d, key=k, schema=s, value=val, vtype=vt))
    return items

def effective(it):
    path = None if it["schema"].get_path() else it["dir"]
    return Gio.Settings.new_full(it["schema"], None, path).get_value(it["key"])

def dconf(*a, capture=False):
    r = subprocess.run(["dconf", *a], capture_output=True, text=True, check=not capture)
    return r.stdout.strip() if capture else None

def dread(full): return dconf("read", full, capture=True) or None

def load_prev(p):
    if p and os.path.exists(p):
        with open(p) as f: return json.load(f)
    return {"keys": {}, "merged": {}}

def save_prev(p, prev):
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "w") as f: json.dump(prev, f, indent=1)

def cmd_apply(args):
    prev = load_prev(args.prev)
    for it in resolve(args):
        if it["state"] != "ok":
            warn(f"skip ({it['state']}): {it['full']}"); continue
        full = it["full"]
        if full in args.merge:
            if it["vtype"].dup_string() != "as":
                warn(f"skip (merge needs 'as'): {full}"); continue
            cur = list(effective(it).unpack()); mine = list(it["value"].unpack())
            add = [x for x in mine if x not in cur]
            rec = prev["merged"].setdefault(full, {"added": [], "was_unset": dread(full) is None, "base": cur})
            if add:
                dconf("write", full, GLib.Variant("as", cur + add).print_(False))
                rec["added"] += [x for x in add if x not in rec["added"]]
        else:
            if full not in prev["keys"]:
                prev["keys"][full] = dread(full)
            dconf("write", full, it["value"].print_(True))
        save_prev(args.prev, prev)

def cmd_remove(args):
    if not os.path.exists(args.prev): return
    prev = load_prev(args.prev)
    for full, old in prev["keys"].items():
        if old is None: dconf("reset", full)
        else: dconf("write", full, old)
    for full, rec in prev["merged"].items():
        if not rec["added"]: continue          # we changed nothing: never touch the user's list
        cur_txt = dread(full)
        if cur_txt is None: continue
        cur = GLib.Variant.parse(GLib.VariantType.new("as"), cur_txt, None, None).unpack()
        left = [x for x in cur if x not in rec["added"]]
        # untouched since add and it was unset before: back to the default; otherwise keep user edits
        if rec.get("was_unset") and "base" in rec and cur == rec["base"] + rec["added"]: dconf("reset", full)
        else: dconf("write", full, GLib.Variant("as", left).print_(False))
    os.remove(args.prev)

def cmd_status(args):
    if not os.path.exists(args.prev or ""):
        print("not-installed"); return
    differ = 0; ok = 0
    for it in resolve(args):
        if it["state"] != "ok":
            print(f"{it['state']} {it['full']}"); continue
        cur = effective(it)
        if it["full"] in args.merge:
            good = all(x in cur.unpack() for x in it["value"].unpack())
        else:
            good = cur.equal(it["value"])
        if good: ok += 1
        else: differ += 1; print(f"differ {it['full']}")
    print("installed" if differ == 0 else f"partial: {differ} differ")

def cmd_capture(args):
    dump = dconf("dump", args.base, capture=True)
    section = ""; skip_section = False
    for line in dump.splitlines():
        if line.startswith("["):
            section = line; skip_section = any(n in line for n in NOISE)
            if not skip_section: print(line)
        elif not skip_section and not any(n in line for n in NOISE):
            print(line)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["apply", "remove", "status", "capture"])
    ap.add_argument("--base", required=True)
    ap.add_argument("--ini"); ap.add_argument("--prev")
    ap.add_argument("--merge", action="append", default=[])
    ap.add_argument("--subst", action="append", default=[])
    ap.add_argument("--extensions", action="store_true")
    a = ap.parse_args()
    a.subst = dict(s.split("=", 1) for s in a.subst)
    {"apply": cmd_apply, "remove": cmd_remove, "status": cmd_status, "capture": cmd_capture}[a.cmd](a)

if __name__ == "__main__":
    main()
