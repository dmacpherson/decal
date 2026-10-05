#!/usr/bin/env python3
"""decal's menu (`decal` in a terminal, or `decal ui`): apply, stamp, remove, update, logs.

Every action runs the same `decal` commands you could type (shown before they run), so the menu and the command
line always agree. A shared picker chooses what each one covers: the profile's tags and its modules."""
import curses, glob, json, os, re, subprocess, sys, threading

import profiles  # noqa: E402  (lib/, next to this file: describe() and ago())

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECAL = os.path.join(REPO, "decal")
MODULES = os.environ.get("DECAL_MODULES_DIR") or os.path.join(REPO, "modules")
STATE = os.environ.get("DECAL_USER_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "decal")
PROFILE = os.environ.get("DECAL_PROFILE") or os.environ.get("DECAL_PROFILE_HOME") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "decal", "profile")
ENV = dict(os.environ, DECAL_NO_UPDATE="1")   # decal already updated itself when the menu opened
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

MENU = [  # key, word (the command), the sticker aside, what it does
    ("1", "apply", "stick it on", "put a profile on this machine"),
    ("2", "stamp", "take a print", "save this machine's setup as a profile"),
    ("3", "remove", "peel it off", "undo what decal changed"),
    ("4", "update", "fresh sheet", ""),
    ("5", "logs", "the fine print", "what the last run did"),
]


# --- talking to decal ------------------------------------------------------------------------------------------
def decal(*args):
    r = subprocess.run([DECAL, *args], capture_output=True, text=True, env=ENV, stdin=subprocess.DEVNULL)
    return r.returncode, ANSI.sub("", r.stdout + r.stderr)


def sections(tags):
    r = subprocess.run([sys.executable, os.path.join(REPO, "lib", "profile.py"), "sections", "--profile", PROFILE,
                        "--modules", MODULES], capture_output=True, text=True, env=dict(ENV, DECAL_TAGS=tags))
    return r.stdout.split() if r.returncode == 0 else []


def has_profile():
    return os.path.isfile(os.path.join(PROFILE, "profile.toml"))


class Data:
    """What the screens show: version, profile, tags, modules and their status (read once per refresh)."""

    def load(self):
        self.version = decal("version")[1].strip() or "decal"
        if "git checkout" in self.version:
            self.version = "(git checkout)"
        self.profile = has_profile()
        self.where = tilde(os.path.realpath(PROFILE)) if self.profile else ""
        self.tags, self.mod_tags = [], {}
        if self.profile:
            for line in decal("tags")[1].splitlines():
                parts = line.split()
                if len(parts) >= 2 and not line.startswith("==>"):
                    self.tags.append(parts[0])
                    for m in parts[1:]:
                        self.mod_tags.setdefault(m, []).append(parts[0])
        self.base = set(sections("")) if self.profile else set()
        self.all = set(sections("all")) if self.profile else set()
        self.status = {}
        for line in decal("--tags", "all", "status")[1].splitlines() if self.profile else decal("status")[1].splitlines():
            m = re.match(r"^(\S+)\s{2,}(.*)$", line)
            if m and os.path.isdir(os.path.join(MODULES, m.group(1))):
                self.status[m.group(1)] = m.group(2)
        try:
            self.last_tags = [t for t in open(os.path.join(STATE, "tags")).read().strip().split(",") if t in self.tags]
        except OSError:   # never applied with the menu's memory: the tags whose modules are already here
            self.last_tags = [t for t in self.tags if any(t in self.mod_tags.get(m, []) and m not in self.base
                              and self.status.get(m, "").startswith(("installed", "partial")) for m in self.all)]
        self.update = ""
        if os.path.exists(os.path.join(REPO, ".installed")):
            r = subprocess.run(["bash", os.path.join(REPO, "install.sh"), "--check"], capture_output=True, text=True,
                               env=dict(ENV, DECAL_HOME=REPO), timeout=40)
            self.update = r.stdout.strip() if r.returncode == 0 else ""
        return self

    def counts(self):
        on = sum(1 for s in self.status.values() if s.startswith("installed"))
        part = sum(1 for s in self.status.values() if s.startswith("partial"))
        return f"{on} on" + (f", {part} partial" if part else "")


def tilde(p):
    for home in {os.path.realpath(os.path.expanduser("~")), os.path.expanduser("~")}:
        if p == home or p.startswith(home + "/"):
            return "~" + p[len(home):]
    return p


def stamp_modules():
    out = []
    for m in sorted(os.listdir(MODULES)):
        f = os.path.join(MODULES, m, "module.sh")
        if os.path.isfile(f) and not re.search(r"^STAMP_SKIP=1", open(f).read(), re.M):
            out.append(m)
    return out


# --- what each action runs (pure: tested on its own) ----------------------------------------------------------
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



GROUPS = [("github", "On GitHub"), ("file", "On this machine"), ("stick", "On USB sticks"), ("recent", "Recently used")]


def row_key(row):
    """What identifies a row across refreshes: its profile's source, or its label (headings, actions)."""
    return (row[3] or {}).get("source") or row[1]


def pick_row(rows, key, i):
    """The row index to highlight: the row with KEY, else the active profile, else the usual file, else the first."""
    pickable = [n for n, r in enumerate(rows) if r[0] == "row"]
    same = [n for n in pickable if key is not None and row_key(rows[n]) == key]
    if same:
        return same[0]
    if key is None or i not in pickable:
        act = [n for n in pickable if (rows[n][3] or {}).get("active")]
        usual = [n for n in pickable if rows[n][2] == "the usual place"]
        return (act or usual or pickable)[0]
    act = [n for n in pickable if (rows[n][3] or {}).get("active")]
    return act[0] if act else i


def browser_rows(data, purpose, user):
    """The browser's lines: (style, label, aside, value). Stamp leaves out recently used (others' profiles) and offers
    the usual ~/decal-USER.tar.gz when it isn't there yet."""
    rows, entries, act = [], data.get("entries", []), data.get("active", "")
    if purpose == "apply" and act and not any(e.get("active") for e in entries):
        rows += [("head", "Active", "", None), ("row", tilde(act), "← active", {"source": act, "kind": "active", "active": True})]
    for kind, title in GROUPS:
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
            usual = os.path.join(os.path.expanduser("~"), f"decal-{user}.tar.gz")
            if not any(e["source"] == usual for e in es):
                extra = [("row", tilde(usual), "the usual place", {"source": usual, "kind": "file"})]
        if not es and not extra:
            continue
        rows.append(("head", title, "", None))
        rows += extra + [("row", e["name"], profiles.describe(e) + ("    ← active" if e.get("active") else ""), e) for e in es]
    rows += [("note", n, "", None) for n in data.get("notes", [])]
    rows += [("row", "+ Make a new profile", "", {"action": "new"}),
             ("row", "› Enter a profile…", "a link, owner/name, a file or a folder", {"action": "enter"})]
    return rows

# --- screens ---------------------------------------------------------------------------------------------------
class UI:
    def __init__(self, scr):
        self.scr = scr
        curses.curs_set(0)
        try:
            curses.start_color(); curses.use_default_colors()
            for i, c in enumerate([curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_RED, curses.COLOR_CYAN,
                                   curses.COLOR_MAGENTA], 1):
                curses.init_pair(i, c, -1)
        except curses.error:
            pass
        self.wait = -1   # the key timeout (ms) screens set; -1: wait for a key
        self.d = Data()
        self.reload()

    def c(self, n, extra=0):
        return curses.color_pair(n) | extra if curses.has_colors() else extra

    def reload(self):
        self.msg_screen("reading this machine…")
        self.d.load()

    # drawing helpers
    def put(self, y, x, text, attr=0):
        h, w = self.scr.getmaxyx()
        if 0 <= y < h and x < w:
            try:
                self.scr.addnstr(y, x, text, max(0, w - x - 1), attr)
            except curses.error:
                pass

    def header(self, title=""):
        self.scr.erase()
        d = self.d
        self.put(0, 1, "▗▄▖", self.c(5, curses.A_BOLD)); self.put(0, 5, "decal", curses.A_BOLD)
        self.put(0, 11, d.version.replace("decal ", ""), curses.A_DIM)
        prof = f"profile: {d.where}" if d.profile else "no profile yet"
        tags = f" · tags: {', '.join(d.last_tags)}" if d.last_tags else ""
        self.put(1, 1, "▐▛ ▜▌", self.c(5, curses.A_BOLD))
        self.put(1, 7, f"{prof}{tags} · {d.counts()}", curses.A_DIM)
        w = self.scr.getmaxyx()[1]
        self.put(2, 1, "─" * (w - 3), curses.A_DIM)
        if title:
            self.put(3, 2, title, curses.A_BOLD)
        return 5 if title else 4

    def footer(self, text):
        h = self.scr.getmaxyx()[0]
        self.put(h - 1, 2, text, curses.A_DIM)

    def msg_screen(self, text):
        self.scr.erase(); self.put(2, 2, text, curses.A_DIM); self.scr.refresh()

    def key(self, raw=False):
        """The key pressed, by name (up, enter, esc...); raw: letters stay letters (j/k aren't moves in a text box)."""
        try:
            k = self.scr.get_wch()
        except curses.error:   # nothing pressed within the timeout
            return None
        if k == "\x1b":   # with a timeout set, curses can hand an arrow key over as its raw bytes: read the rest
            seq = ""
            self.scr.timeout(30)
            try:
                while len(seq) < 2:
                    try:
                        seq += self.scr.get_wch()
                    except (curses.error, TypeError):
                        break
            finally:
                self.scr.timeout(self.wait)
            named = {"[A": "up", "OA": "up", "[B": "down", "OB": "down", "[H": "home", "OH": "home",
                     "[F": "end", "OF": "end"}.get(seq)
            if named:
                return named
            for ch in reversed(seq):   # not a key we know: Esc, and the rest stays for next time
                curses.unget_wch(ch)
            return "esc"
        return {"\n": "enter", "\r": "enter", "\x1b": "esc", " ": "space", "\x7f": "backspace", "\b": "backspace",
                curses.KEY_ENTER: "enter", curses.KEY_UP: "up", curses.KEY_DOWN: "down", curses.KEY_BACKSPACE: "backspace",
                curses.KEY_NPAGE: "pgdn", curses.KEY_PPAGE: "pgup", curses.KEY_HOME: "home", curses.KEY_END: "end",
                curses.KEY_RESIZE: "resize", "\t": "tab", **({} if raw else {"k": "up", "j": "down"})}.get(k, k)

    # a list to choose one from: [(label, aside, value)] -> value or None
    def choose(self, title, items, help_="↑↓ move · enter choose · esc back"):
        i = 0
        while True:
            top = self.header(title)
            for n, (label, aside, _) in enumerate(items):
                attr = curses.A_REVERSE if n == i else 0
                self.put(top + n, 2, f" {label} ", attr | curses.A_BOLD)
                if aside:
                    self.put(top + n, 6 + len(label), aside, curses.A_DIM)
            self.footer(help_)
            k = self.key()
            if k == "up": i = (i - 1) % len(items)
            elif k == "down": i = (i + 1) % len(items)
            elif k == "enter": return items[i][2]
            elif k in ("esc", "q"): return None

    # a line of text: -> str or None (Tab completes paths)
    def ask(self, title, prompt, default=""):
        text = default
        curses.curs_set(1)
        try:
            while True:
                top = self.header(title)
                self.put(top, 2, prompt, curses.A_DIM)
                self.put(top + 2, 2, "> " + text)
                self.footer("enter ok · tab completes a path · esc back")
                self.scr.move(top + 2, 4 + len(text))
                k = self.key(raw=True)
                if k == "enter": return text.strip()
                if k == "esc": return None
                if k == "backspace": text = text[:-1]
                elif k == "tab":
                    hits = glob.glob(os.path.expanduser(text) + "*")
                    if hits:
                        pre = os.path.commonprefix(hits)
                        if len(hits) == 1 and os.path.isdir(pre): pre += "/"
                        text = pre.replace(os.path.expanduser("~"), "~", 1) if text.startswith("~") else pre
                elif isinstance(k, str) and len(k) == 1 and k.isprintable(): text += k
        finally:
            curses.curs_set(0)

    # scrollable text: -> True (enter) / False (esc)
    def view(self, title, text, help_="↑↓ scroll · esc back"):
        lines = text.rstrip("\n").splitlines() or ["(nothing)"]
        pos = 0
        while True:
            top = self.header(title)
            h = self.scr.getmaxyx()[0] - top - 2
            for n, line in enumerate(lines[pos:pos + h]):
                attr = self.c(1) if line.lstrip().startswith(("✓", "==>")) else (self.c(3) if "error" in line or "✗" in line else 0)
                self.put(top + n, 2, line, attr)
            self.footer(help_ + (f" · {pos + 1}-{min(pos + h, len(lines))}/{len(lines)}" if len(lines) > h else ""))
            k = self.key()
            if k == "down": pos = min(pos + 1, max(0, len(lines) - h))
            elif k == "up": pos = max(0, pos - 1)
            elif k == "pgdn": pos = min(pos + h, max(0, len(lines) - h))
            elif k == "pgup": pos = max(0, pos - h)
            elif k == "home": pos = 0
            elif k == "end": pos = max(0, len(lines) - h)
            elif k == "enter": return True
            elif k in ("esc", "q"): return False

    # the shared picker: tags on top, modules below. -> (tags, modules) or None
    def picker(self, title, mode):
        d = self.d
        if mode == "apply":
            tags, rows = list(d.tags), sorted(d.all)
            on_t = set(d.last_tags)
            on_m = {m for m in rows if self.available(m, on_t)}
        elif mode == "stamp":
            tags, rows, on_t = [], stamp_modules(), set()
            on_m = set(rows)
        else:   # remove: what's there, nothing ticked
            tags = list(d.tags)
            rows = sorted(m for m, s in d.status.items() if not s.startswith(("not-installed", "not in profile")))
            on_t, on_m = set(), set()
        items = [("tag", t) for t in tags] + [("mod", m) for m in rows]
        if not items:
            self.view(title, "nothing to choose from here", "esc back"); return None
        i = 0
        while True:
            top = self.header(title)
            h = self.scr.getmaxyx()[0] - top - 2
            first = max(0, i - h + 1)
            for n, (kind, name) in enumerate(items[first:first + h]):
                y, cur = top + n, first + n == i
                if kind == "tag":
                    box = "[x]" if name in on_t else "[ ]"
                    self.put(y, 2, f"{box} tag: {name}", (curses.A_REVERSE if cur else 0) | self.c(5, curses.A_BOLD))
                    aside = "take off what it added" if mode == "remove" else "its settings and modules too"
                    self.put(y, 26, aside, curses.A_DIM)
                    continue
                ok = mode != "apply" or self.available(name, on_t) or name in on_m   # tickable on its own too
                box = "[x]" if name in on_m else ("[ ]" if ok else "[ ]")
                attr = (curses.A_REVERSE if cur else 0) | (0 if ok else curses.A_DIM)
                self.put(y, 2, f"{box} {name:<18}", attr)
                tg = ",".join(d.mod_tags.get(name, []))
                self.put(y, 26, tg, self.c(5, curses.A_DIM))
                st = d.status.get(name, "")
                dot, col = ("●", 1) if st.startswith("installed") else ("◐", 2) if st.startswith("partial") else \
                           ("✗", 3) if st.startswith("error") else ("○", 0)
                self.put(y, 37, f"{dot} {st}", self.c(col) if col else curses.A_DIM)
            self.footer("space tick · a all · n none · enter next · esc back")
            k = self.key()
            kind, name = items[i]
            if k == "up": i = (i - 1) % len(items)
            elif k == "down": i = (i + 1) % len(items)
            elif k == "space":
                if kind == "tag":
                    on_t ^= {name}
                    if mode == "apply":   # a tag brings its modules in, and takes away ones only it had
                        on_m |= {m for m in rows if name in d.mod_tags.get(m, []) and self.available(m, on_t)}
                        on_m = {m for m in on_m if self.available(m, on_t)}
                else:   # a module only a tag has can be ticked on its own (decal add MODULE uses its tag's settings)
                    on_m ^= {name}
            elif k == "a":
                on_m = {m for m in rows if mode != "apply" or self.available(m, on_t)}
            elif k == "n":
                on_m = set()
            elif k == "enter":
                if not on_m and not (mode == "remove" and on_t):
                    continue
                return [t for t in tags if t in on_t], [m for m in rows if m in on_m]
            elif k in ("esc", "q"):
                return None

    def available(self, m, on_t):
        return m in self.d.base or any(t in on_t for t in self.d.mod_tags.get(m, []))

    # run commands in the terminal itself (progress lines, sudo prompts), then come back
    def run(self, cmds, done, failed):
        curses.endwin()
        rc = 0
        for c in cmds:
            print(f"\n\033[2m$ decal {' '.join(c)}\033[0m", flush=True)
            rc = subprocess.call([DECAL, *c], env=ENV)
            if rc != 0:
                break
        print(f"\n\033[1;32m✓ {done}\033[0m" if rc == 0 else f"\n\033[1;31m✗ {failed}\033[0m")
        try:
            input("\npress enter to go back to the menu ")
        except EOFError:
            pass
        self.scr.refresh()
        self.reload()
        return rc

    def preview(self, title, cmds):
        self.msg_screen("working out what would change…")
        out = []
        for c in cmds:
            rc, text = decal("--dry-run", *c)
            out += [f"$ decal {' '.join(c)}", text.rstrip(), ""]
        return "\n".join(out)

    def profiles_json(self, only):
        rc, out = decal("profiles", "--json", f"--only={only}")
        try:
            return json.loads(out[out.index("{"):]) if rc == 0 else {}
        except ValueError:
            return {}

    def browse(self, title, purpose):
        """The profile browser: local entries at once, GitHub filled in by a background thread."""
        state = {"data": self.profiles_json("local"), "gh": None}
        state["data"].setdefault("entries", [])

        def github():
            state["gh"] = self.profiles_json("github")

        def start():
            state["gh"] = None
            threading.Thread(target=github, daemon=True).start()

        start()
        user = os.environ.get("USER") or "me"
        i, picked = None, None   # picked: the chosen row's label, so the cursor stays on it as GitHub fills in
        self.wait = 200
        self.scr.timeout(self.wait)
        try:
            while True:
                d = dict(state["data"])
                gh = state["gh"]
                if gh is None:
                    d["loading"], d["signed_in"] = True, True
                else:
                    seen = {e["source"] for e in gh.get("entries", [])}
                    d["entries"] = gh.get("entries", []) + [e for e in d["entries"] if e["source"] not in seen]
                    d["signed_in"], d["notes"] = gh.get("signed_in"), gh.get("notes", [])
                    d["loading"] = False
                rows = browser_rows(d, purpose, user)
                pickable = [n for n, r in enumerate(rows) if r[0] == "row"]
                i = pick_row(rows, picked, i)
                top = self.header(title)
                h = self.scr.getmaxyx()[0] - top - 2
                first = max(0, i - h + 1)
                for n, (style, label, aside, _) in enumerate(rows[first:first + h]):
                    y = top + n
                    if style == "head":
                        self.put(y, 2, label, self.c(4, curses.A_BOLD))
                    elif style == "note":
                        self.put(y, 4, label, curses.A_DIM)
                    else:
                        self.put(y, 4, f" {label:<30} ", (curses.A_REVERSE if first + n == i else 0) | curses.A_BOLD)
                        self.put(y, 37, aside, curses.A_DIM)
                self.footer("↑↓ move · enter choose · r refresh · esc back")
                picked = row_key(rows[i])
                k = self.key()
                if k is None:
                    continue
                pos = pickable.index(i)
                moved = {"up": pickable[(pos - 1) % len(pickable)], "down": pickable[(pos + 1) % len(pickable)],
                         "home": pickable[0], "end": pickable[-1]}.get(k)
                if moved is not None:
                    i, picked = moved, row_key(rows[moved])
                    continue
                if k == "r":
                    state["data"] = self.profiles_json("local"); start()
                elif k in ("esc", "q"):
                    return None
                elif k == "enter":
                    v = rows[i][3]
                    if v.get("action") == "sign-in":
                        self.sign_in(); start()
                        continue
                    return v
        finally:
            self.wait = -1
            self.scr.timeout(-1)

    def sign_in(self):
        """Sign in for this menu session: the key lives in ENV (passed to every decal command), never on disk."""
        curses.endwin()
        r = subprocess.run([sys.executable, os.path.join(REPO, "lib", "auth.py"), "get", "-", "--need", "read"],
                           stdout=subprocess.PIPE, text=True, env=ENV)
        if r.returncode == 0 and r.stdout.strip():
            ENV["GITHUB_TOKEN"] = r.stdout.strip()
        self.scr.refresh()

    def trusted(self, src):
        """Someone else's profile: say so before using it (the preview comes later, before anything changes)."""
        lib = os.path.join(REPO, "lib")
        r = subprocess.run([sys.executable, os.path.join(lib, "source.py"), "resolve", src], capture_output=True, text=True, env=ENV)
        if r.returncode != 0:
            self.view("Apply · that profile", r.stderr.strip() or "decal couldn't read that", "esc back")
            return False
        canon = r.stdout.split("\t")[1]
        login = ""
        if canon.startswith("github:"):   # whatever key decal would use: this session's, GITHUB_TOKEN, GH_TOKEN, gh
            rc, out = decal("whoami")
            login = out.strip().splitlines()[-1] if rc == 0 and out.strip() else ""
        y = subprocess.run([sys.executable, os.path.join(lib, "source.py"), "yours", canon, "--login", login], env=ENV)
        if y.returncode == 0:
            return True
        who = canon.removeprefix("github:")
        return self.view("Apply · someone else's profile",
                         f"This profile is from {who}, not you.\n\nIt can install software and change system settings.\n"
                         "You'll see a preview of every change before anything happens.",
                         "enter go on · esc back")

    def do_new(self, start_from=""):
        how = start_from or self.choose("New profile · start from", [
            ("this machine", "a stamp of how it's set up now", "this-machine"),
            ("a copy of a profile…", "then change it", "copy"),
            ("empty", "every section commented out", "empty")])
        if how is None:
            return None
        frm = how
        if how == "copy":
            v = self.browse("New profile · copy which one?", "apply")
            if not v or v.get("action"):
                return None
            frm = v["source"]
        where = self.choose("New profile · where", [("GitHub", "a private repo on your account", "github"),
                                                   ("this machine", "~/NAME.tar.gz", "file"),
                                                   ("the USB stick", ".Decal/profile", "stick")])
        if where is None:
            return None
        me = os.environ.get("USER") or "me"
        name = self.ask("New profile · name", "letters, digits, - _ .", f"decal-{me}")
        if not name:
            return None
        use = self.choose("New profile · use it now?", [("yes", "make it the active profile", True), ("no", "", False)])
        if use is None:
            return None
        cmd = ["new", name, "--from", frm, "--to", where] + (["--use"] if use else [])
        self.run([cmd], f"New profile: {name}", "Couldn't make it (see above)")
        return name

    # --- the actions -------------------------------------------------------------------------------------------
    def do_apply(self):
        v = self.browse("Apply · stick it on · which profile?", "apply")
        if v is None:
            return
        if v.get("action") == "new":
            self.do_new()
            return
        if v.get("action") == "enter":
            src = self.ask("Apply · which profile?", "a link, owner/name, a file or a folder")
            if not src:
                return
            src = os.path.expanduser(src)
        else:
            src = v["source"]
        if not self.trusted(src):   # the active profile too: it may be someone else's, used but never applied
            return
        if not v.get("active"):
            if self.run([["use", src]], "that's the active profile now", "couldn't use it (see above)") != 0:
                return
        pick = self.picker("Apply · stick it on · choose", "apply")
        if not pick:
            return
        tags, mods = pick
        cmds = apply_cmds(tags, mods, [m for m in sorted(self.d.all) if self.available(m, set(tags))])
        if self.view("Apply · preview (nothing changed yet)", self.preview("apply", cmds),
                     "enter apply · ↑↓ scroll · esc back"):
            self.run(cmds, f"Stuck on: {len(mods)} modules", "Apply stopped: see Logs (the fine print)")

    def do_stamp(self):
        pick = self.picker("Stamp · take a print · choose", "stamp")
        if not pick:
            return
        mods = pick[1]
        every = set(mods) == set(stamp_modules())
        if not self.view("Stamp · preview", self.preview("stamp", [stamp_cmd(mods, every)]), "enter save it · ↑↓ scroll · esc back"):
            return
        v = self.browse("Stamp · save it to", "stamp")
        if v is None:
            return
        dest, gh, public = "", None, False
        if v.get("action") == "new":
            self.do_new("this-machine")
            return
        if v.get("action") == "enter":
            to = self.ask("Stamp · save it to", "a .tar.gz, a folder, or owner/name on GitHub")
            if not to:
                return
            if re.fullmatch(r"[\w.-]+/[\w.-]+", to) and not os.path.exists(os.path.expanduser(to)):
                gh = to
            else:
                dest = os.path.expanduser(to)
        elif v["kind"] == "github":
            gh = v["source"].removeprefix("github:")
        else:
            dest = v["source"]
        self.run([stamp_cmd(mods, every, dest, gh, public)], "Stamped", "Stamp failed (see above)")

    def do_remove(self):
        pick = self.picker("Remove · peel it off · choose", "remove")
        if not pick:
            return
        tags, mods = pick
        cmds = remove_cmds(tags, mods)
        if not self.view("Remove · preview (nothing changed yet)", self.preview("remove", cmds), "enter go on · ↑↓ scroll · esc back"):
            return
        sure = self.ask("Remove · peel it off", 'type "remove" to peel these off')
        if sure != "remove":
            return
        what = ", ".join([f"tag {t}" for t in tags] + mods)
        self.run(cmds, f"Peeled off: {what} (cleanly)", "Remove stopped: see Logs (the fine print)")

    def do_update(self):
        curses.endwin()
        rc = subprocess.call([DECAL, "update"], env=dict(os.environ))
        if rc == 0:
            print("\n\033[1;32m✓ Fresh sheet: decal is up to date\033[0m")
            input("\npress enter to go back to the menu ")
            os.execv(DECAL, [DECAL, "ui"])   # the new version's menu
        input("\npress enter to go back to the menu ")
        self.scr.refresh(); self.reload()

    def do_logs(self):
        f = os.path.join(STATE, "logs", "last.log")
        try:
            text = open(f, errors="replace").read()
        except OSError:
            text = "no runs logged yet"
        self.view("Logs · the fine print", text)

    def main(self):
        i = 0
        while True:
            d = self.d
            items = [it for it in MENU if (it[1] != "update" or d.update) and (d.profile or it[1] in ("apply", "stamp", "logs"))]
            top = self.header()
            if not d.profile:
                self.put(top, 2, "No profile yet. Apply one to stick it on, or Stamp this machine to make one.", curses.A_DIM)
                top += 2
            for n, (key, word, fun, what) in enumerate(items):
                if word == "update":
                    what = f"{d.update} is out"
                y = top + n
                self.put(y, 2, key, self.c(4, curses.A_BOLD))
                self.put(y, 5, f" {word.capitalize():<8}", (curses.A_REVERSE if n == i else 0) | curses.A_BOLD)
                self.put(y, 16, f"{fun:<16}", self.c(5, curses.A_DIM))
                self.put(y, 33, what)
            self.put(top + len(items) + 1, 2, "q", self.c(4, curses.A_BOLD)); self.put(top + len(items) + 1, 6, "Quit")
            self.footer("↑↓ move · enter or a number to choose · q quit")
            k = self.key()
            if k == "up": i = (i - 1) % len(items)
            elif k == "down": i = (i + 1) % len(items)
            elif k == "q": return
            elif k in ("resize", "esc"): continue   # esc goes back from a screen; here there's nowhere to go
            else:
                pick = None
                if k == "enter": pick = items[i][1]
                for key, word, *_ in items:
                    if k == key: pick = word
                if pick:
                    getattr(self, f"do_{pick}")()


def main():
    os.environ.setdefault("ESCDELAY", "25")
    try:
        curses.wrapper(lambda scr: UI(scr).main())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
