#!/usr/bin/env python3
"""stamp.py : what `decal stamp` reads off a machine, changed from default only.

  dconf --out FILE [--extensions UUID...]   settings you changed (user dconf db) whose value differs from the
                                            distro's (its system dbs) or the schema default -> a decal keyfile
  extensions                                 enabled extensions; the distro's turned off -> "enable"/"disable" lines
  section MODULE --profile DIR --modules DIR --to DIR
                                             the active profile's section for MODULE (tags included) as TOML, with
                                             the profile files it points to copied into the stamp
  brave --prefs FILE [--local-state FILE] --to DIR
                                             Brave settings decal knows (per device) + Web Store extensions -> TOML
"""
import argparse, configparser, io, json, os, re, shutil, subprocess, sys, tempfile

LIB = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, LIB)

# --- dconf ----------------------------------------------------------------------------------------------------
# Settings worth carrying to another machine: (path, also its sub-paths). Everything else in dconf (app state,
# history, window sizes, other apps) is left out, and so are keys other modules own (themes, fonts, extensions).
ALLOW = [
    ("/org/gnome/desktop/interface/", False), ("/org/gnome/desktop/wm/", True),
    ("/org/gnome/desktop/peripherals/", True), ("/org/gnome/desktop/input-sources/", False),
    ("/org/gnome/desktop/app-folders/", True), ("/org/gnome/desktop/privacy/", False),
    ("/org/gnome/desktop/screensaver/", False), ("/org/gnome/desktop/session/", False),
    ("/org/gnome/desktop/sound/", False), ("/org/gnome/desktop/notifications/", False),
    ("/org/gnome/desktop/search-providers/", False), ("/org/gnome/desktop/calendar/", False),
    ("/org/gnome/desktop/a11y/", True), ("/org/gnome/mutter/", True),
    ("/org/gnome/settings-daemon/plugins/color/", False), ("/org/gnome/settings-daemon/plugins/power/", False),
    ("/org/gnome/settings-daemon/plugins/media-keys/", True), ("/org/gnome/shell/", False),
    ("/org/gnome/shell/weather/", False), ("/org/gnome/shell/keybindings/", False),
    ("/org/gnome/nautilus/preferences/", False), ("/org/gnome/nautilus/list-view/", False),
    ("/org/gnome/nautilus/icon-view/", False), ("/org/gnome/Ptyxis/", False),
    ("/org/gnome/system/location/", False), ("/org/gtk/gtk4/settings/file-chooser/", False),
    ("/org/gtk/settings/file-chooser/", False), ("/org/gnome/TextEditor/", False),
]
DENY_KEYS = {
    "enabled-extensions", "disabled-extensions", "command-history", "cursor-theme", "cursor-size", "icon-theme",
    "gtk-theme", "monospace-font-name", "picture-uri", "picture-uri-dark", "picture-options", "primary-color",
    "secondary-color", "color-shading-type", "welcome-dialog-last-shown-version", "last-selected-power-profile",
    "window-size", "window-position", "window-maximized", "sidebar-width", "sort-column", "sort-order-dir",
    "last-folder-uri", "initial-setup-done", "remember-recent-files-dummy", "search-filter-time-type",
    "date-format", "location-mode", "looking-glass-history", "prefs-open-count", "settings-version",
    "rounded-blur-found", "show-hidden", "show-size-column", "show-type-column", "type-format",
}
DENY_FULL = {  # state, ids, or owned by another module (terminal: Ptyxis font, cursor, profiles)
    "/org/gnome/desktop/notifications/application-children", "/org/gnome/nautilus/preferences/migrated-gtk-settings",
    "/org/gnome/Ptyxis/default-profile-uuid", "/org/gnome/Ptyxis/profile-uuids", "/org/gnome/Ptyxis/font-name",
    "/org/gnome/Ptyxis/use-system-font", "/org/gnome/Ptyxis/cursor-shape",
}
DENY_PATHS = ["/org/gnome/desktop/notifications/application/", "/org/gnome/shell/extensions/",
              "/org/gnome/Ptyxis/Profiles/", "/org/gnome/desktop/background/"]


def parse_dump(text, base="/"):
    """dconf dump text -> {full key path: value text}"""
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",))
    cp.optionxform = str
    cp.read_string(text)
    out = {}
    for sec in cp.sections():
        d = base if sec.strip("/") == "" else base + sec.strip("/") + "/"
        for k, v in cp.items(sec):
            out[d + k] = v
    return out


def system_dump():
    """The distro's defaults: the system dbs of the dconf profile, without the user's."""
    name = os.environ.get("DCONF_PROFILE", "user")
    cands = [name] if os.path.isabs(name) else [f"/etc/dconf/profile/{name}", f"/usr/share/dconf/profile/{name}"]
    lines = []
    for c in cands:
        if os.path.isfile(c):
            lines = [l.strip() for l in open(c) if l.strip().startswith(("system-db:", "file-db:"))]
            break
    if not lines:
        return {}
    with tempfile.NamedTemporaryFile("w", suffix=".profile", delete=False) as f:
        f.write("\n".join(lines) + "\n")
    try:
        r = subprocess.run(["dconf", "dump", "/"], capture_output=True, text=True, env=dict(os.environ, DCONF_PROFILE=f.name))
        return parse_dump(r.stdout) if r.returncode == 0 else {}
    finally:
        os.unlink(f.name)


def allowed(full):
    if full in DENY_FULL or any(full.startswith(p) for p in DENY_PATHS):
        return False
    d, k = full.rsplit("/", 1)
    if k in DENY_KEYS:
        return False
    for p, deep in ALLOW:
        if (d + "/") == p or (deep and (d + "/").startswith(p)):
            return True
    return False


def changed(user, system, with_ext, keep):
    """keys of user (a {path: text} dump) whose value isn't the default; keep(path) filters"""
    import dconf_tool
    from gi.repository import GLib
    src = dconf_tool.schema_source(with_ext)
    fixed = dconf_tool.fixed_map(src)
    out = {}
    for full, txt in user.items():
        if not keep(full):
            continue
        d, k = full.rsplit("/", 1)
        d += "/"
        s = dconf_tool.schema_for(src, fixed, d)
        if s is None or not s.has_key(k):
            if system.get(full) != txt:
                out[full] = txt          # no schema to compare with: a value you set
            continue
        vt = s.get_key(k).get_value_type()
        try:
            mine = GLib.Variant.parse(vt, txt, None, None)
        except GLib.Error:
            continue
        if full in system:
            try:
                default = GLib.Variant.parse(vt, system[full], None, None)
            except GLib.Error:
                default = s.get_key(k).get_default_value()
        else:
            default = s.get_key(k).get_default_value()
        if not mine.equal(default):
            out[full] = txt
    return out


def write_ini(keys, base, path, replace=()):
    secs = {}
    for full, txt in sorted(keys.items()):
        d, k = full.rsplit("/", 1)
        rel = d[len(base):].strip("/") if d.startswith(base.rstrip("/")) else d.strip("/")
        secs.setdefault(rel or "/", []).append((k, txt))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write("# decal: captured by `decal stamp` (only what differs from the defaults)\n")
        for sec, items in secs.items():
            f.write(f"\n[{sec}]\n")
            for k, v in items:
                for a, b in replace:   # e.g. your home folder -> @HOME@, so it works for anyone
                    v = v.replace(a, b)
                f.write(f"{k}={v}\n")


def ext_schema_paths(uuids):
    """settings paths of these extensions (from their metadata's settings-schema)"""
    import dconf_tool
    src = dconf_tool.schema_source(True)
    paths = []
    for base in (os.path.expanduser("~/.local/share/gnome-shell/extensions"), "/usr/share/gnome-shell/extensions",
                 "/usr/local/share/gnome-shell/extensions"):
        for u in uuids:
            meta = os.path.join(base, u, "metadata.json")
            if not os.path.isfile(meta):
                continue
            try:
                sid = json.load(open(meta)).get("settings-schema")
            except (OSError, ValueError):
                continue
            s = src.lookup(sid, True) if sid else None
            if s and s.get_path():
                paths.append(s.get_path())
    return paths


def cmd_dconf(a):
    user = parse_dump(subprocess.run(["dconf", "dump", "/"], capture_output=True, text=True, check=True).stdout)
    system = system_dump()
    if a.extensions is not None:
        prefixes = ext_schema_paths(a.extensions)
        noise = ("gsconnect", "window-", "last-")
        keep = lambda full: (any(full.startswith(p) for p in prefixes) and not any(n in full for n in noise)
                             and full.rsplit("/", 1)[1] not in DENY_KEYS)
        keys = changed(user, system, True, keep)
        base = "/org/gnome/shell/extensions/"
    else:
        keys = changed(user, system, False, allowed)
        base = "/"
    if keys:
        write_ini(keys, base, a.out, [r.split("=", 1) for r in a.replace] + [(os.path.expanduser("~"), "@HOME@")])
    print(len(keys))


def gsettings_list(key):
    r = subprocess.run(["gsettings", "get", "org.gnome.shell", key], capture_output=True, text=True)
    return re.findall(r"'([^']+)'", r.stdout) if r.returncode == 0 else []


def cmd_extensions(a):
    from gi.repository import GLib
    enabled = gsettings_list("enabled-extensions")
    from gi.repository import Gio
    sysv = system_dump().get("/org/gnome/shell/enabled-extensions")
    if sysv:
        distro = GLib.Variant.parse(GLib.VariantType.new("as"), sysv, None, None).unpack()
    else:   # the schema's default, with the distro's overrides (e.g. Bazzite's)
        s = Gio.SettingsSchemaSource.get_default().lookup("org.gnome.shell", True)
        distro = s.get_key("enabled-extensions").get_default_value().unpack() if s else []
    installed = set(subprocess.run(["gnome-extensions", "list"], capture_output=True, text=True).stdout.split())
    print("enable " + " ".join(u for u in enabled if u in installed))
    print("disable " + " ".join(u for u in distro if u not in enabled))


# --- TOML (just what profiles use) ----------------------------------------------------------------------------
BARE = re.compile(r"^[A-Za-z0-9_-]+$")


def tkey(k):
    return k if BARE.match(k) else json.dumps(k)


def tval(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ", ".join(tval(x) for x in v) + "]"
    raise ValueError(f"can't write {v!r} as TOML")


def toml_table(name, d, out):
    plain = {k: v for k, v in d.items() if not isinstance(v, dict)}
    subs = {k: v for k, v in d.items() if isinstance(v, dict)}
    if plain or not subs:
        out.append(f"[{name}]")
        out += [f"{tkey(k)} = {tval(v)}" for k, v in plain.items()]
    for k, v in subs.items():
        toml_table(f"{name}.{tkey(k)}", v, out)


def cmd_section(a):
    import profile as prof
    data = prof.load_profile(a.profile).get(a.module)
    if data is None:
        return
    schema = prof.load_schema(a.modules, a.module) or {"keys": {}}
    types = schema["keys"]
    pdir = os.path.realpath(a.profile)

    def spec_for(path):
        if path in types:
            return types[path]
        for k, s in types.items():
            if k.endswith(".*") and path.startswith(k[:-1]):
                return s
        return None

    def copy(v):
        """a profile file -> the same relative path in the stamp (outside the profile: files/NAME)"""
        if not v or re.match(r"^(https?|git\+|github-release:)", v):
            return v
        src = v if os.path.isabs(v) else os.path.join(pdir, v)
        if not os.path.exists(src):
            return v
        real = os.path.realpath(src)
        rel = os.path.relpath(real, pdir) if real.startswith(pdir + os.sep) else os.path.join("files", os.path.basename(real))
        dst = os.path.join(a.to, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.isdir(real):
            shutil.copytree(real, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git"))
        else:
            shutil.copy2(real, dst)
        return rel

    def walk(d, prefix, own):
        for k, v in d.items():
            if isinstance(v, dict):
                # a tag's table holds the section's own keys again; a module table extends the path
                walk(v, prefix if k not in own else f"{prefix}{k}.", own)
                continue
            spec = spec_for(prefix + k)
            if spec and spec["type"] in ("path", "paths", "path-or-url", "source"):
                d[k] = [copy(x) for x in v] if isinstance(v, list) else copy(v)

    own = prof.own_tables(schema)
    walk(data, "", own)
    out = []
    toml_table(a.module, data, out)
    print("\n".join(out))


# --- Brave ----------------------------------------------------------------------------------------------------
# Per-device settings decal carries (Brave Sync doesn't): look, toolbar, new tab page, search engines, privacy
BRAVE_KEYS = [
    "brave.new_tab_page", "brave.location_bar_is_wide", "brave.show_side_panel_button", "brave.sidebar",
    "brave.tabs", "brave.web_view_rounded_corners", "brave.enable_window_closing_confirm",
    "brave.wayback_machine_enabled", "brave.default_private_search_provider_data",
    "brave.default_private_search_provider_guid", "brave.show_bookmarks_button", "brave.autocomplete_enabled",
    "bookmark_bar", "browser.theme", "browser.clear_data", "browser.pin_pwa_install_button",
    "browser.pin_split_tab_button", "default_search_provider", "default_search_provider_data",
    "extensions.theme", "ntp", "NewTabPage", "session.restore_on_startup", "tab_search",
    "profile.default_content_setting_values",
]


def pick(d, dotted):
    cur = d
    for p in dotted.split("."):
        if not isinstance(cur, dict) or p not in cur:
            return None
        cur = cur[p]
    return cur


def put(d, dotted, v):
    parts = dotted.split(".")
    for p in parts[:-1]:
        d = d.setdefault(p, {})
    d[parts[-1]] = v


STATE = re.compile(r"(count|_time$|^date_|^last_|_date$|timestamp)", re.I)   # bookkeeping, not settings


def settings_only(v):
    if isinstance(v, dict):
        return {k: settings_only(x) for k, x in v.items() if not STATE.search(k)}
    return v


def cmd_brave(a):
    prefs = json.load(open(a.prefs))
    keep = {}
    for k in BRAVE_KEYS:
        v = pick(prefs, k)
        if v is not None:
            put(keep, k, settings_only(v))
    exts = sorted(i for i, e in pick(prefs, "extensions.settings").items()
                  if isinstance(e, dict) and e.get("from_webstore") and not e.get("was_installed_by_default")
                  and e.get("location") in (1, 6) and re.fullmatch(r"[a-p]{32}", i)) if pick(prefs, "extensions.settings") else []
    lines = ["[brave]"]
    os.makedirs(os.path.join(a.to, "brave"), exist_ok=True)
    if keep:
        json.dump(keep, open(os.path.join(a.to, "brave/preferences.json"), "w"), indent=2, sort_keys=True)
        lines.append('preferences = "brave/preferences.json"')
    if a.local_state and os.path.isfile(a.local_state):
        ls = json.load(open(a.local_state))
        o = {k: v for k, v in (pick(ls, "brave.origin") or {}).items() if k in ("free_tier_accepted", "purchase_validated") and v}
        if o:
            json.dump({"brave": {"origin": o}}, open(os.path.join(a.to, "brave/local-state.json"), "w"), indent=2)
            lines.append('local-state = "brave/local-state.json"')
    if exts:
        lines.append("extensions = " + tval(exts))
    if len(lines) > 1:
        print("\n".join(lines))
    print(f"# {len(keep)} setting groups, {len(exts)} extensions", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("dconf"); p.add_argument("--out", required=True); p.add_argument("--extensions", nargs="*")
    p.add_argument("--replace", action="append", default=[], metavar="FROM=TO")
    sub.add_parser("extensions")
    p = sub.add_parser("section"); p.add_argument("module"); p.add_argument("--profile", required=True)
    p.add_argument("--modules", required=True); p.add_argument("--to", required=True)
    p = sub.add_parser("brave"); p.add_argument("--prefs", required=True); p.add_argument("--local-state")
    p.add_argument("--to", required=True)
    a = ap.parse_args()
    {"dconf": cmd_dconf, "extensions": cmd_extensions, "section": cmd_section, "brave": cmd_brave}[a.cmd](a)


if __name__ == "__main__":
    main()
