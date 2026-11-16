#!/usr/bin/env python3
"""Firefox profile, prefs.js, mozLz4, and policies.json helper for decal."""
import argparse
import configparser
import json
import os
import re
import shutil
import struct
import sys
import urllib.parse

PREF_LINE_RE = re.compile(r'^\s*user_pref\(\s*("(?:[^"\\]|\\.)*")\s*,\s*(.*?)\s*\);\s*$')
AMO_ID_RE = re.compile(
    r"^(?:[A-Za-z0-9._-]+@[A-Za-z0-9._-]+|\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\})$"
)


def atomic_write_text(path, text):
    """Write text to the real target of path via temp rename, keeping symlinks and permissions."""
    real = os.path.realpath(path)
    os.makedirs(os.path.dirname(real) or ".", exist_ok=True)
    tmp = os.path.join(os.path.dirname(real), f".{os.path.basename(real)}.decal-new")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    if os.path.exists(real):
        shutil.copymode(real, tmp)
    os.replace(tmp, real)


def valid_amo_id(ext_id):
    return (
        isinstance(ext_id, str)
        and bool(AMO_ID_RE.fullmatch(ext_id))
        and ".." not in ext_id
        and "/" not in ext_id
    )


def resolve_profile(base_dir, wanted_name):
    """Resolve the Firefox profile directory from profiles.ini."""
    ini_path = os.path.join(base_dir, "profiles.ini")
    if not os.path.isfile(ini_path):
        cand = os.path.join(base_dir, wanted_name)
        if "/" not in wanted_name and wanted_name not in (".", "..") and os.path.isdir(cand):
            return cand
        raise ValueError(f"profiles.ini not found in {base_dir}")

    cp = configparser.RawConfigParser(strict=False)
    cp.optionxform = str
    cp.read(ini_path, encoding="utf-8")
    base_real = os.path.realpath(base_dir)

    def resolve_path(rel_or_abs, is_rel):
        p = os.path.join(base_dir, rel_or_abs) if is_rel else rel_or_abs
        real = os.path.realpath(p)
        if is_rel and real != base_real and not real.startswith(base_real + os.sep):
            raise ValueError(f"unsafe profile path in profiles.ini: {rel_or_abs!r}")
        return p if os.path.isdir(p) else None

    if wanted_name == "default-release":
        for sec in cp.sections():
            if sec.startswith("Install") and cp.has_option(sec, "Default"):
                p = resolve_path(cp.get(sec, "Default"), True)
                if p:
                    return p

    for sec in cp.sections():
        if sec.startswith("Profile") and cp.get(sec, "Name", fallback="") == wanted_name:
            if cp.has_option(sec, "Path"):
                p = resolve_path(cp.get(sec, "Path"), cp.get(sec, "IsRelative", fallback="1") == "1")
                if p:
                    return p

    if wanted_name in ("default", "default-release"):
        for sec in cp.sections():
            if sec.startswith("Profile") and cp.get(sec, "Default", fallback="0") == "1":
                if cp.has_option(sec, "Path"):
                    p = resolve_path(cp.get(sec, "Path"), cp.get(sec, "IsRelative", fallback="1") == "1")
                    if p:
                        return p

    raise ValueError(f"Firefox profile {wanted_name!r} not found in {ini_path}")


def parse_prefs_js(path):
    """Return (lines, {key: (line_idx, value)}) parsed from a prefs.js file."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    parsed = {}
    for idx, line in enumerate(lines):
        m = PREF_LINE_RE.match(line)
        if not m:
            continue
        try:
            k = json.loads(m.group(1))
            v = json.loads(m.group(2))
        except json.JSONDecodeError:
            continue
        if isinstance(k, str):
            parsed[k] = (idx, v)
    return lines, parsed


def load_prefs_settings(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("Firefox prefs file must be a JSON object")
    for k, v in data.items():
        if not isinstance(k, str) or not k or any(ord(c) < 32 for c in k) or "\n" in k:
            raise ValueError(f"invalid Firefox pref name: {k!r}")
        if not isinstance(v, (bool, int, float, str)):
            raise ValueError(f"pref {k!r} must be a bool, number, or string")
    return data


def format_pref_line(key, val):
    return f"user_pref({json.dumps(key)}, {json.dumps(val)});\n"


def apply_prefs_list(lines, updates):
    """Return new lines after setting key->val (or removing if val is _REMOVE)."""
    by_key = {}
    for idx, line in enumerate(lines):
        m = PREF_LINE_RE.match(line)
        if m:
            try:
                k = json.loads(m.group(1))
                by_key.setdefault(k, []).append(idx)
            except json.JSONDecodeError:
                pass

    drop_indices = set()
    new_lines = list(lines)
    appended = []
    for k, action in updates.items():
        idxs = by_key.get(k, [])
        if action is None:
            drop_indices.update(idxs)
        else:
            rendered = format_pref_line(k, action)
            if idxs:
                new_lines[idxs[0]] = rendered
                drop_indices.update(idxs[1:])
            else:
                appended.append(rendered)

    out = [line for idx, line in enumerate(new_lines) if idx not in drop_indices]
    if out and appended and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out.extend(appended)
    return "".join(out)


def cmd_resolve_profile(a):
    print(resolve_profile(a.base_dir, a.name))


def cmd_prefs_status(a):
    _, cur = parse_prefs_js(a.prefs_js)
    want = load_prefs_settings(a.settings)
    for k, v in want.items():
        if k not in cur:
            sys.exit(1)
        got = cur[k][1]
        if type(got) is not type(v) or got != v:
            sys.exit(1)
    sys.exit(0)


def cmd_prefs_apply(a):
    lines, cur = parse_prefs_js(a.prefs_js)
    want = load_prefs_settings(a.settings)
    prev = {}
    if os.path.isfile(a.prev):
        with open(a.prev, "r", encoding="utf-8") as f:
            prev = json.load(f)
    for k in want:
        if k not in prev:
            if k in cur:
                prev[k] = {"value": cur[k][1]}
            else:
                prev[k] = {"absent": True}
    atomic_write_text(a.prev, json.dumps(prev, indent=2, sort_keys=True) + "\n")
    atomic_write_text(a.prefs_js, apply_prefs_list(lines, want))


def cmd_prefs_restore(a):
    if not os.path.isfile(a.prev):
        return
    lines, _ = parse_prefs_js(a.prefs_js)
    with open(a.prev, "r", encoding="utf-8") as f:
        prev = json.load(f)
    updates = {k: (None if rec.get("absent") else rec["value"]) for k, rec in prev.items()}
    atomic_write_text(a.prefs_js, apply_prefs_list(lines, updates))


def decompress_mozlz4(data):
    """Decompress Mozilla search.json.mozlz4 ('mozLz40\\0' + uint32le size + raw LZ4 block)."""
    if len(data) < 12 or data[:8] != b"mozLz40\0":
        raise ValueError("not a mozLz40 file")
    out_len = struct.unpack("<I", data[8:12])[0]
    src = data[12:]
    out = bytearray()
    i = 0
    while i < len(src):
        tok = src[i]
        i += 1
        lit_len = tok >> 4
        if lit_len == 15:
            while i < len(src):
                b = src[i]
                i += 1
                lit_len += b
                if b != 255:
                    break
        if i + lit_len > len(src):
            raise ValueError("corrupt mozLz4 literal length")
        out.extend(src[i : i + lit_len])
        i += lit_len
        if i >= len(src):
            break
        if i + 2 > len(src):
            raise ValueError("corrupt mozLz4 match offset")
        offset = struct.unpack("<H", src[i : i + 2])[0]
        i += 2
        if offset == 0 or offset > len(out):
            raise ValueError("invalid mozLz4 match offset")
        match_len = (tok & 0x0F) + 4
        if (tok & 0x0F) == 15:
            while i < len(src):
                b = src[i]
                i += 1
                match_len += b
                if b != 255:
                    break
        pos = len(out) - offset
        for _ in range(match_len):
            out.append(out[pos])
            pos += 1
    if len(out) != out_len:
        raise ValueError(f"mozLz4 size mismatch: expected {out_len}, got {len(out)}")
    return bytes(out)


def cmd_read_mozlz4(a):
    with open(a.path, "rb") as f:
        sys.stdout.buffer.write(decompress_mozlz4(f.read()))


def build_policy_dict(policies_path="", search_path="", extensions=()):
    pol = {}
    if policies_path:
        with open(policies_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        if not isinstance(raw, dict):
            raise ValueError("Firefox policies file must be a JSON object")
        inner = raw.get("policies", raw)
        if not isinstance(inner, dict):
            raise ValueError("Firefox policies['policies'] must be a JSON object")
        pol.update(inner)

    if extensions:
        ext_cfg = pol.setdefault("ExtensionSettings", {})
        if not isinstance(ext_cfg, dict):
            raise ValueError("ExtensionSettings must be a JSON object")
        for eid in extensions:
            if not valid_amo_id(eid):
                raise ValueError(f"invalid Firefox add-on ID: {eid!r}")
            q = urllib.parse.quote(eid, safe="@")
            ext_cfg.setdefault(
                eid,
                {
                    "installation_mode": "normal_installed",
                    "install_url": f"https://addons.mozilla.org/firefox/downloads/latest/{q}/latest.xpi",
                },
            )

    if search_path:
        with open(search_path, "r", encoding="utf-8") as f:
            sdata = json.load(f)
        if not isinstance(sdata, dict):
            raise ValueError("Firefox search file must be a JSON object")
        se = pol.setdefault("SearchEngines", {})
        if sdata.get("default"):
            se["Default"] = sdata["default"]
        if sdata.get("default-private"):
            se["DefaultPrivate"] = sdata["default-private"]
        if sdata.get("remove"):
            se["Remove"] = list(sdata["remove"])
        if sdata.get("add"):
            se["Add"] = list(sdata["add"])
        if "prevent-installs" in sdata:
            se["PreventInstalls"] = bool(sdata["prevent-installs"])

    return {"policies": pol} if pol else {}


def cmd_build_policy(a):
    res = build_policy_dict(a.policies or "", a.search or "", a.ext or [])
    if res:
        sys.stdout.write(json.dumps(res, indent=2, sort_keys=True) + "\n")


def cmd_policy_matches(a):
    if not os.path.isfile(a.current):
        sys.exit(1)
    try:
        with open(a.current, "r", encoding="utf-8") as f:
            cur = json.load(f)
        want = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(1)
    sys.exit(0 if cur == want else 1)


def cmd_drop_extensions(a):
    if not os.path.isfile(a.current):
        return
    with open(a.current, "r", encoding="utf-8") as f:
        doc = json.load(f)
    pol = doc.get("policies", {})
    ext_cfg = pol.get("ExtensionSettings", {})
    for eid in a.ext:
        ext_cfg.pop(eid, None)
    if not ext_cfg and "ExtensionSettings" in pol:
        del pol["ExtensionSettings"]
    if pol:
        sys.stdout.write(json.dumps({"policies": pol}, indent=2, sort_keys=True) + "\n")


def cmd_user_install_file(a):
    dest_real = os.path.realpath(a.dest)
    os.makedirs(a.backup_dir, exist_ok=True)
    bk = os.path.join(a.backup_dir, a.key)
    absent = bk + ".absent"
    if not os.path.exists(bk) and not os.path.exists(absent):
        if os.path.exists(dest_real):
            shutil.copy2(dest_real, bk)
        else:
            open(absent, "w", encoding="utf-8").close()
    with open(a.src, "r", encoding="utf-8") as f:
        atomic_write_text(a.dest, f.read())


def cmd_user_restore_file(a):
    bk = os.path.join(a.backup_dir, a.key)
    absent = bk + ".absent"
    if os.path.exists(bk):
        with open(bk, "r", encoding="utf-8") as f:
            atomic_write_text(a.dest, f.read())
        os.unlink(bk)
    elif os.path.exists(absent):
        if os.path.lexists(a.dest) and not os.path.islink(a.dest):
            os.unlink(a.dest)
        os.unlink(absent)


def cmd_user_file_matches(a):
    if not os.path.isfile(a.src) or not os.path.isfile(a.dest):
        sys.exit(1)
    with open(a.src, "rb") as fs, open(os.path.realpath(a.dest), "rb") as fd:
        sys.exit(0 if fs.read() == fd.read() else 1)


def cmd_user_install_dir(a):
    os.makedirs(a.backup_dir, exist_ok=True)
    rec = os.path.join(a.backup_dir, a.key + ".files")
    if not os.path.isdir(a.src):
        raise ValueError(f"directory not found: {a.src}")
    installed = []
    src_root = os.path.realpath(a.src)
    for root, dirs, files in os.walk(src_root):
        dirs.sort()
        for fn in sorted(files):
            sfile = os.path.join(root, fn)
            rel = os.path.relpath(sfile, src_root)
            dfile = os.path.join(a.dest, rel)
            bk = os.path.join(a.backup_dir, a.key + ".tree", rel)
            absent = bk + ".absent"
            if not os.path.exists(bk) and not os.path.exists(absent):
                os.makedirs(os.path.dirname(bk), exist_ok=True)
                if os.path.exists(dfile):
                    shutil.copy2(dfile, bk)
                else:
                    open(absent, "w", encoding="utf-8").close()
            os.makedirs(os.path.dirname(dfile), exist_ok=True)
            tmp = dfile + ".decal-new"
            shutil.copy2(sfile, tmp)
            os.replace(tmp, dfile)
            installed.append(rel)
    atomic_write_text(rec, "\n".join(installed) + ("\n" if installed else ""))


def cmd_user_restore_dir(a):
    rec = os.path.join(a.backup_dir, a.key + ".files")
    if not os.path.isfile(rec):
        return
    with open(rec, "r", encoding="utf-8") as f:
        rels = [line.rstrip("\n") for line in f if line.rstrip("\n")]
    for rel in rels:
        dfile = os.path.join(a.dest, rel)
        bk = os.path.join(a.backup_dir, a.key + ".tree", rel)
        absent = bk + ".absent"
        if os.path.exists(bk):
            os.makedirs(os.path.dirname(dfile), exist_ok=True)
            shutil.copy2(bk, dfile + ".decal-new")
            os.replace(dfile + ".decal-new", dfile)
        elif os.path.exists(absent):
            if os.path.lexists(dfile):
                os.unlink(dfile)
    shutil.rmtree(os.path.join(a.backup_dir, a.key + ".tree"), ignore_errors=True)
    os.unlink(rec)
    if os.path.isdir(a.dest) and not os.listdir(a.dest):
        os.rmdir(a.dest)


def cmd_user_dir_matches(a):
    if not os.path.isdir(a.src) or not os.path.isdir(a.dest):
        sys.exit(1)
    src_root = os.path.realpath(a.src)
    for root, dirs, files in os.walk(src_root):
        dirs.sort()
        for fn in sorted(files):
            sfile = os.path.join(root, fn)
            rel = os.path.relpath(sfile, src_root)
            dfile = os.path.join(a.dest, rel)
            if not os.path.isfile(dfile):
                sys.exit(1)
            with open(sfile, "rb") as fs, open(dfile, "rb") as fd:
                if fs.read() != fd.read():
                    sys.exit(1)
    sys.exit(0)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("resolve-profile")
    p.add_argument("base_dir"); p.add_argument("name")

    p = sub.add_parser("prefs-status")
    p.add_argument("prefs_js"); p.add_argument("settings")

    p = sub.add_parser("prefs-apply")
    p.add_argument("prefs_js"); p.add_argument("settings"); p.add_argument("prev")

    p = sub.add_parser("prefs-restore")
    p.add_argument("prefs_js"); p.add_argument("prev")

    p = sub.add_parser("read-mozlz4")
    p.add_argument("path")

    p = sub.add_parser("build-policy")
    p.add_argument("--policies"); p.add_argument("--search"); p.add_argument("--ext", action="append", default=[])

    p = sub.add_parser("policy-matches")
    p.add_argument("current")

    p = sub.add_parser("drop-extensions")
    p.add_argument("current"); p.add_argument("ext", nargs="+")

    p = sub.add_parser("user-install-file")
    p.add_argument("src"); p.add_argument("dest"); p.add_argument("backup_dir"); p.add_argument("key")

    p = sub.add_parser("user-restore-file")
    p.add_argument("dest"); p.add_argument("backup_dir"); p.add_argument("key")

    p = sub.add_parser("user-file-matches")
    p.add_argument("src"); p.add_argument("dest")

    p = sub.add_parser("user-install-dir")
    p.add_argument("src"); p.add_argument("dest"); p.add_argument("backup_dir"); p.add_argument("key")

    p = sub.add_parser("user-restore-dir")
    p.add_argument("dest"); p.add_argument("backup_dir"); p.add_argument("key")

    p = sub.add_parser("user-dir-matches")
    p.add_argument("src"); p.add_argument("dest")

    a = ap.parse_args()
    handlers = {
        "resolve-profile": cmd_resolve_profile,
        "prefs-status": cmd_prefs_status,
        "prefs-apply": cmd_prefs_apply,
        "prefs-restore": cmd_prefs_restore,
        "read-mozlz4": cmd_read_mozlz4,
        "build-policy": cmd_build_policy,
        "policy-matches": cmd_policy_matches,
        "drop-extensions": cmd_drop_extensions,
        "user-install-file": cmd_user_install_file,
        "user-restore-file": cmd_user_restore_file,
        "user-file-matches": cmd_user_file_matches,
        "user-install-dir": cmd_user_install_dir,
        "user-restore-dir": cmd_user_restore_dir,
        "user-dir-matches": cmd_user_dir_matches,
    }
    try:
        handlers[a.cmd](a)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
