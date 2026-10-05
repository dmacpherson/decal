"""menu_logic.py: what the menu (ui.py) shows and runs, as pure functions tested without a terminal."""
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import profiles  # noqa: E402

MENU = [  # key, word (the command), the sticker aside, what it does
    ("1", "apply", "stick it on", "put a profile on this machine"),
    ("2", "stamp", "take a print", "save this machine's setup as a profile"),
    ("3", "usb", "a stick", "put decal on a USB stick"),
    ("4", "remove", "peel it off", "undo what decal changed"),
    ("5", "logs", "the fine print", "what the last run did"),
    ("6", "update", "fresh sheet", ""),   # last: only shown when a newer decal is out
]


def label(word):
    """A menu word as shown: USB in capitals, the rest capitalised."""
    return "USB" if word == "usb" else word.capitalize()


def apply_cmds(tags, mods, avail):
    t = ["--tags", ",".join(tags)] if tags else []
    if not mods:
        return []
    return [t + ["add", "all"]] if set(mods) == set(avail) else [t + ["add", *mods]]


def stamp_cmd(mods, everything, dest="", gh=None, public=False):
    c = ["stamp"] + ([] if everything else list(mods))
    if dest:
        c.append(dest)
    if gh is not None:
        c += ["-gh"] + ([gh] if gh else [])
        if public:
            c.append("--public")
    return c


def remove_cmds(tags, mods):
    return [["remove", "all", "--only", t] for t in tags] + ([["remove", *mods]] if mods else [])


def usb_cmd(profile, how, dmode, arm, to):
    return ["usb", "--from", profile, "--how", how, "--decal", dmode, "--to", to] + (["--arm"] if arm else [])


def drive_label(d):
    parts = [d["label"]]
    if d.get("ventoy"):
        parts.append(f"{d.get('isos', 0)} ISOs")
    parts.append(f"{d['size'] / 1e9:.1f} GB")
    if not d.get("mount"):
        parts.append("not mounted")
    return " · ".join(parts)


STICK_ITEMS = [("1", "apply-all", "Apply everything"), ("2", "choose", "Choose what to apply"),
               ("3", "preview", "Preview first"), ("4", "save", "Save this machine"), ("5", "remove-all", "Take it all off"),
               ("6", "status", "What's on this machine"), ("7", "other", "Use a different profile"),
               ("8", "full", "Full menu")]


def save_targets(conf, stick):
    """Where "Save this machine" can go: where the stick's profile came from first, then the rest."""
    p = conf.get("profile", "")
    if p == "copy":
        return [("the copy on this stick", os.path.join(stick, "profile"), "stick"),
                ("both", "the copy on this stick and a GitHub repo", "both"),
                ("somewhere else…", "any of your profiles, a file, or a new one", "elsewhere")]
    return [(p.removeprefix("github:"), "signs in to GitHub to save", "github"),
            ("somewhere else…", "any of your profiles, a file, or a new one", "elsewhere")]


def clean_env(env, key, ghdir):
    """The environment for saving to GitHub: only this session's write key; no GITHUB_TOKEN/GH_TOKEN (the stick's
    read key), and gh pointed at an empty folder (a borrowed PC's gh login never touches your repo)."""
    out = {k: v for k, v in env.items() if k not in ("GITHUB_TOKEN", "GH_TOKEN", "DECAL_WRITE_KEY")}
    out["GH_CONFIG_DIR"] = ghdir
    if key:
        out["DECAL_WRITE_KEY"] = key   # decal started from a stick takes only this key to write with
    return out


def stick_header(conf):
    """The stick menu's first line (start.sh fetched the profile just before the menu opened)."""
    p = conf.get("profile", "")
    what = "the profile copy on it" if p == "copy" else p.removeprefix("github:")
    return f"From your USB stick: {what} · updated just now"


def row_key(row):
    """What identifies a row across refreshes: its profile's source, or its label (headings, actions)."""
    return (row[3] or {}).get("source") or row[1]


def pick_row(rows, key, i):
    """The row index to highlight: the row with KEY, else the active profile, else the usual file, else the first."""
    pickable = [n for n, r in enumerate(rows) if r[0] == "row"]
    same = [n for n in pickable if key is not None and row_key(rows[n]) == key]
    if same:
        return same[0]
    act = [n for n in pickable if (rows[n][3] or {}).get("active")]
    if key is None or i not in pickable:
        usual = [n for n in pickable if rows[n][2] == "the usual place"]
        return (act or usual or pickable)[0]
    return act[0] if act else i


def browser_rows(data, purpose, user):
    """The browser's lines: (style, label, aside, value). Stamp leaves out recently used (others' profiles) and offers
    the usual ~/decal-USER.tar.gz when it isn't there yet."""
    rows, entries, act = [], data.get("entries", []), data.get("active", "")
    if purpose == "apply" and act and not any(e.get("active") for e in entries):
        rows += [("head", "Active", "", None), ("row", profiles.tilde(act), "← active", {"source": act, "kind": "active", "active": True})]
    for kind, title in profiles.GROUPS:
        if purpose == "stamp" and kind == "recent":
            continue
        es = [e for e in entries if e["kind"] == kind]
        extra = []
        if kind == "github":
            if data.get("loading"):
                extra = [("note", "Looking for your profiles…", "", None)]
            elif data.get("signed_in") is False:
                extra = [("row", "Sign in to see your GitHub profiles", "", {"action": "sign-in"})]
        if kind == "file" and purpose == "stamp":
            usual = profiles.usual_stamp(user)
            if not any(e["source"] == usual for e in es):
                extra = [("row", profiles.tilde(usual), "the usual place", {"source": usual, "kind": "file"})]
        if not es and not extra:
            continue
        rows.append(("head", title, "", None))
        rows += extra + [("row", e["name"], profiles.describe(e) + ("    ← active" if e.get("active") else ""), e) for e in es]
    rows += [("note", n, "", None) for n in data.get("notes", [])]
    rows += [("row", "+ Make a new profile", "", {"action": "new"}),
             ("row", "› Enter a profile…", "a link, owner/name, a file or a folder", {"action": "enter"})]
    return rows


def stamp_dest(v, typed=""):
    """Where a stamp goes, from the browser's pick (and what was typed for "Enter a profile…"): (dest, repo)."""
    if v.get("action") == "enter":
        if re.fullmatch(r"[\w.-]+/[\w.-]+", typed) and not os.path.exists(os.path.expanduser(typed)):
            return "", typed
        return os.path.expanduser(typed), ""
    if v.get("kind") == "github":
        return "", v["source"].removeprefix("github:")
    return v["source"], ""


def latest(state, run, value):
    """A background GitHub listing lands only when no newer one has started since (a slow, older one never replaces
    a fresher one)."""
    if run == state.get("run"):
        state["gh"] = value
