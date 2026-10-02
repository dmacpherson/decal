#!/usr/bin/env python3
"""decal's menu (`decal` in a terminal, or `decal ui`): apply, stamp, remove, update, logs.

Every action runs the same `decal` commands you could type (shown before they run), so the menu and the command
line always agree. A shared picker chooses what each one covers: the profile's tags and its modules."""
import curses, glob, os, re, subprocess, sys

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

    def key(self):
        k = self.scr.get_wch()
        return {"\n": "enter", "\r": "enter", "\x1b": "esc", " ": "space", "\x7f": "backspace", "\b": "backspace",
                curses.KEY_ENTER: "enter", curses.KEY_UP: "up", curses.KEY_DOWN: "down", curses.KEY_BACKSPACE: "backspace",
                curses.KEY_NPAGE: "pgdn", curses.KEY_PPAGE: "pgup", curses.KEY_HOME: "home", curses.KEY_END: "end",
                curses.KEY_RESIZE: "resize", "\t": "tab", "k": "up", "j": "down"}.get(k, k)

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
                k = self.key()
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
                ok = mode != "apply" or self.available(name, on_t)
                box = "[x]" if name in on_m and ok else ("[ ]" if ok else " · ")
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
                elif mode != "apply" or self.available(name, on_t):
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

    # --- the actions -------------------------------------------------------------------------------------------
    def do_apply(self):
        opts = [("the active profile", self.d.where, "active")] if self.d.profile else []
        opts += [("a folder or .tar.gz…", "", "path"), ("a GitHub repo…", "owner/name", "github"),
                 ("a git URL…", "", "git")]
        how = self.choose("Apply · stick it on · which profile?", opts)
        if how is None:
            return
        if how != "active":
            prompts = {"path": "the folder or .tar.gz (e.g. ~/decal-me.tar.gz)", "github": "owner/name (private: it asks for a token)",
                       "git": "the git URL"}
            src = self.ask("Apply · which profile?", prompts[how])
            if not src:
                return
            src = os.path.expanduser(src)
            if how == "github" and not src.startswith("github:"):
                src = "github:" + src
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
        me = os.environ.get("USER") or "me"
        where = self.choose("Stamp · save it to", [
            (f"~/decal-{me}.tar.gz", "the usual place (the last one kept as .old)", "file"),
            ("somewhere else…", "a .tar.gz or a folder", "path"),
            ("GitHub", f"a private repo, decal-{me} (and the file too)", "github")])
        if where is None:
            return
        dest, gh, public = "", None, False
        if where == "path":
            dest = self.ask("Stamp · save it to", "a .tar.gz or a folder")
            if not dest:
                return
            dest = os.path.expanduser(dest)
        elif where == "github":
            gh = self.ask("Stamp · GitHub", "the repo: name or owner/name", f"decal-{me}")
            if gh is None:
                return
            vis = self.choose("Stamp · who can see it?", [("private", "only you (recommended)", False),
                                                          ("public", "anyone: pictures, apps, settings", True)])
            if vis is None:
                return
            public = vis
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
