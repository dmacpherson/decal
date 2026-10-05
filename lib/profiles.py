#!/usr/bin/env python3
"""profiles.py: the profiles decal can see, and pieces for making new ones.

  profiles.py list [--json] [--only local|github]   GitHub (repos you own holding a profile.toml), this machine
                                                     (~/decal-* stamps), USB sticks (.Decal/profile), recently used
  profiles.py sticks                                 mounted drives (one per line)
  profiles.py empty DIR                              a starter profile: examples/profile, every section commented out
  profiles.py readme DIR NAME FROM                   DIR/README.md for a profile called NAME, made from FROM
  profiles.py active                                 the active profile's source (decal and the menu ask this)

GitHub uses the key in GITHUB_TOKEN (decal passes the one it found); none: a sign-in row instead. Never asks."""
import argparse, base64, concurrent.futures, datetime, glob, json, os, subprocess, sys, tarfile, tomllib, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auth, gh, source  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = os.environ.get("DECAL_MODULES_DIR") or os.path.join(REPO, "modules")
HOME = os.path.expanduser("~")
MEDIA = os.environ.get("DECAL_MEDIA") or f"/run/media/{os.environ.get('USER', '')}"
PROFILE_HOME = os.environ.get("DECAL_PROFILE_HOME") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "decal", "profile")
GROUPS = [("github", "On GitHub"), ("file", "On this machine"), ("stick", "On USB sticks"), ("recent", "Recently used")]


def count(text):
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return None
    mods = {d for d in os.listdir(MODULES) if os.path.isfile(os.path.join(MODULES, d, "module.sh"))}
    return sum(1 for k in data if k in mods)


def iso(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).isoformat(timespec="seconds")


def tilde(p):
    """P with your home folder shown as ~ (also when P names it through a link, e.g. /var/home on Atomic)."""
    for home in (HOME, os.path.realpath(HOME)):
        if p == home or p.startswith(home + "/"):
            return "~" + p[len(home):]
    return p


def usual_stamp(user):
    """Where decal stamp saves by default: ~/decal-USER.tar.gz."""
    return os.path.join(HOME, f"decal-{user}.tar.gz")


def toml_in_archive(path):
    """The profile.toml text at the top of an archive (or in its single top folder), or None."""
    def depth(name):
        return name.removeprefix("./").count("/")
    try:
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as z:
                names = sorted((n for n in z.namelist() if n.split("/")[-1] == "profile.toml"), key=depth)
                return z.read(names[0]).decode() if names and depth(names[0]) <= 1 else None
        with tarfile.open(path, "r:gz") as t:
            ms = sorted((m for m in t if m.isfile() and m.name.split("/")[-1] == "profile.toml"), key=lambda m: depth(m.name))
            return t.extractfile(ms[0]).read().decode() if ms and depth(ms[0].name) <= 1 else None
    except (OSError, EOFError, tarfile.TarError, zipfile.BadZipFile, UnicodeDecodeError):
        return None


def find_local():
    out = []
    for p in sorted(glob.glob(os.path.join(HOME, "decal-*"))):
        if os.path.isdir(p):
            if not os.path.exists(os.path.join(p, ".decal-stamp")):
                continue
            try:
                text = open(os.path.join(p, "profile.toml")).read()
            except (OSError, UnicodeDecodeError):   # unreadable, or not text: not a profile to list
                continue
        elif p.endswith(source.ARCHIVES):
            text = toml_in_archive(p)
        else:
            continue
        n = count(text) if text is not None else None
        if n is not None:
            out.append({"kind": "file", "source": p, "name": tilde(p), "updated": iso(os.path.getmtime(p)), "modules": n})
    return out


def sticks():
    return sorted(d for d in glob.glob(os.path.join(MEDIA, "*")) if os.path.isdir(d))


def find_sticks():
    out = []
    for d in sticks():
        p = os.path.join(d, ".Decal", "profile")
        try:
            text = open(os.path.join(p, "profile.toml")).read()
        except (OSError, UnicodeDecodeError):   # a stick is anyone's: unreadable or not text is skipped
            continue
        n = count(text)
        if n is not None:
            label = os.path.basename(d)
            out.append({"kind": "stick", "source": p, "name": f"{label}: .Decal", "label": label,
                        "updated": iso(os.path.getmtime(os.path.join(p, "profile.toml"))), "modules": n})
    return out


def find_recent():
    return [{"kind": "recent", "source": s, "name": s.removeprefix("github:") if s.startswith("github:") else tilde(s),
             "updated": t} for s, t in source.recent()]


def find_github(token):
    """(entries, notes) for the repos the key's account owns that hold a profile.toml. Raises gh.Offline."""
    code, me = gh.get("/user", token)
    if code != 200:
        return [], ["GitHub didn't accept the key"]
    login = me.get("login", "")
    repos, page = [], 1
    while True:
        code, batch = gh.get(f"/user/repos?affiliation=owner&per_page=100&page={page}", token)
        if code != 200 or not isinstance(batch, list):
            break
        repos += batch
        if len(batch) < 100:
            break
        page += 1
    by = {r["full_name"]: r for r in repos}
    cand = {n for n, r in by.items() if r.get("name", "").startswith("decal-")}
    if len(repos) <= 100:
        cand |= set(by)
    code, found = gh.get(f"/search/repositories?q=topic:decal-profile+user:{login}&per_page=100", token)
    if code == 200:
        for r in found.get("items", []):
            by.setdefault(r["full_name"], r)
            cand.add(r["full_name"])
    cand = {n for n in cand if n.split("/")[0].lower() == login.lower()}

    def check(full):
        try:
            code, f = gh.get(f"/repos/{full}/contents/profile.toml", token)
            n = count(base64.b64decode(f["content"]).decode()) if code == 200 and "content" in f else None
        except (gh.Offline, ValueError, KeyError):
            return None
        if n is None:
            return None
        r = by[full]
        return {"kind": "github", "source": f"github:{full}", "name": full, "private": bool(r.get("private")),
                "updated": r.get("pushed_at") or "", "modules": n}

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        entries = [e for e in ex.map(check, sorted(cand)) if e]
    notes = []
    if not entries:
        code, _ = gh.get("/user/installations", token)
        if code == 200:   # an app key: the app may not be on any profile repo yet
            notes.append(f"no profiles found: install Decal Profile on your profile repos: {auth.install_url('read')}")
        else:
            notes.append(f"no profiles found on GitHub for {login}")
    return entries, notes


def active():
    """The active profile's source: where a link points, the recorded source, a checkout's origin, else the folder."""
    d = os.environ.get("DECAL_PROFILE") or PROFILE_HOME
    if os.path.islink(d) or os.environ.get("DECAL_PROFILE"):
        return os.path.realpath(d)
    try:
        return open(os.path.join(d, ".decal-source")).read().strip()
    except OSError:
        pass
    if os.path.isdir(os.path.join(d, ".git")):
        try:
            r = subprocess.run(["git", "-C", d, "remote", "get-url", "origin"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except OSError:   # no git here: the folder itself
            pass
    return os.path.realpath(d) if os.path.isdir(d) else ""


def listing(only=""):
    out, notes, signed = [], [], None
    if only in ("", "github"):
        token = os.environ.get("GITHUB_TOKEN", "")
        signed = bool(token)
        if token:
            try:
                e, n = find_github(token)
                out += e
                notes += n
            except gh.Offline:
                notes.append("couldn't reach GitHub")
    if only in ("", "local"):
        out += find_local() + find_sticks()
        seen = {e["source"] for e in out}
        out += [e for e in find_recent() if e["source"] not in seen]
    act = active()
    for e in out:
        e["active"] = e["source"] == act or os.path.realpath(e["source"]) == act
    return {"entries": out, "notes": notes, "signed_in": signed, "active": act}


def ago(when):
    try:
        t = datetime.datetime.fromisoformat(when.replace("Z", "+00:00"))
    except ValueError:
        return ""
    days = (datetime.datetime.now(datetime.timezone.utc) - t).days
    if days < 1:
        return "today"
    if days < 2:
        return "yesterday"
    for size, unit in ((365, "year"), (30, "month"), (7, "week"), (1, "day")):
        if days >= size:
            n = days // size
            return f"{n} {unit}{'s' if n > 1 else ''} ago"
    return ""


def describe(e):
    mods = f" · {e['modules']} modules" if "modules" in e else ""
    if e["kind"] == "github":
        return f"{'private' if e.get('private') else 'public'} · updated {ago(e['updated'])}{mods}"
    if e["kind"] == "file":
        return f"file · {ago(e['updated'])}{mods}"
    if e["kind"] == "stick":
        return f"copy · {ago(e['updated'])}{mods}"
    return f"used {ago(e['updated'])}"


def text(d):
    lines = []
    for kind, title in GROUPS:
        es = [e for e in d["entries"] if e["kind"] == kind]
        if kind == "github" and d["signed_in"] is False:
            lines += [title, "  Sign in to see your GitHub profiles (decal profiles --sign-in)"]
        elif es:
            lines.append(title)
            lines += [f"  {e['name']:<32} {describe(e)}" + ("    ← active" if e["active"] else "") for e in es]
    return "\n".join(lines + d["notes"])


def empty(dest):
    """examples/profile/profile.toml with every section commented out: applying it changes nothing."""
    src = open(os.path.join(REPO, "examples", "profile", "profile.toml")).read().splitlines()
    out = []
    for line in src:
        out.append(line if not line.strip() or line.lstrip().startswith("#") else "# " + line)
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, "profile.toml"), "w") as f:
        f.write("# A new decal profile: uncomment the sections you want, then decal apply this.\n" + "\n".join(out) + "\n")


def readme(dest, name, made_from):
    how = {"this-machine": "stamped from a machine with `decal new`", "empty": "started empty with `decal new`"}.get(
        made_from, f"copied from {made_from} with `decal new`")
    fence = "`" * 3
    with open(os.path.join(dest, "README.md"), "w") as f:
        f.write(f"# {name}\n\nA [decal](https://github.com/dmacpherson/decal) profile, {how}.\n\n"
                f"## Put it on a machine\n\n{fence}bash\ncurl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- "
                f"{name}\n{fence}\n\n(Use `owner/{name}` for a GitHub repo, or the path of a file.)\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "sticks", "empty", "readme", "active"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--only", choices=["local", "github"], default="")
    a = ap.parse_args()
    if a.cmd == "list":
        d = listing(a.only)
        print(json.dumps(d) if a.json else text(d))
    elif a.cmd == "active":
        print(active())
    elif a.cmd == "sticks":
        print("\n".join(sticks()))
    elif a.cmd == "empty":
        empty(a.args[0])
    else:
        readme(*a.args[:3])


if __name__ == "__main__":
    main()
