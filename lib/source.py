#!/usr/bin/env python3
"""source.py: what a profile source is, and getting it safely.

  source.py resolve INPUT         KIND<TAB>SOURCE<TAB>NOTE (kind: dir, archive, github, url, git)
  source.py unpack ARCHIVE DIR    a .tar.gz/.tgz/.zip, safely: nothing outside DIR, no links, 200 MB at most
  source.py fetch URL DIR         download; an archive is unpacked into DIR (prints "archive"); else exit 3
  source.py remember SOURCE       put SOURCE first in the recently-used list (10 kept; never a key)
  source.py yours SOURCE [--login L]  exit 0 when SOURCE is yours: local, recently used, or L's on GitHub
  source.py public github:O/R     exit 0 when the repo is public (answers without a key)

https only; DECAL_ALLOW_HTTP_LOCAL=1 also allows http://127.0.0.1 (tests)."""
import argparse, datetime, os, re, shutil, stat, sys, tarfile, tempfile, urllib.error, urllib.parse, urllib.request, zipfile

NAME = r"[A-Za-z0-9_.-]+"
OWNER = r"[A-Za-z0-9][A-Za-z0-9-]*"   # GitHub accounts: letters, digits, hyphens
ARCHIVES = (".tar.gz", ".tgz", ".zip")
LIMIT = int(os.environ.get("DECAL_UNPACK_LIMIT", str(200 * 1024 * 1024)))
STATE = os.environ.get("DECAL_USER_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "decal")
RECENT = os.path.join(STATE, "recent")


class Bad(Exception):
    pass


def allowed(url):
    u = urllib.parse.urlparse(url)
    return u.scheme == "https" or (u.scheme == "http" and u.hostname == "127.0.0.1"
                                   and os.environ.get("DECAL_ALLOW_HTTP_LOCAL") == "1")


def resolve(text):
    t = text.strip()
    p = os.path.expanduser(t)
    if os.path.exists(p):   # local wins
        p = os.path.abspath(p)
        kind = "dir" if os.path.isdir(p) else "archive"
        if kind == "archive" and not p.endswith(ARCHIVES):
            raise Bad(f"{t}: not a folder or a .tar.gz/.tgz/.zip")
        note = ""
        if re.fullmatch(rf"{OWNER}/{NAME}(@\S+)?", t):
            note = f"using the {'folder' if kind == 'dir' else 'file'} {t}; for GitHub, write github:{t}"
        return kind, p, note
    if re.fullmatch(rf"github:{OWNER}/{NAME}(@\S+)?", t):
        return "github", t, ""
    if re.fullmatch(rf"{OWNER}/{NAME}(@\S+)?", t):
        return "github", "github:" + t, ""
    m = re.fullmatch(rf"(?:https?://)?(?:www\.)?github\.com/({OWNER})/({NAME})(?:/(?:tree|commit)/(.+?))?/?", t)
    if m:
        repo = m.group(2)[:-4] if m.group(2).endswith(".git") else m.group(2)
        return "github", f"github:{m.group(1)}/{repo}" + (f"@{m.group(3)}" if m.group(3) else ""), ""
    if t.startswith(("git+", "ssh://", "git@", "file://")) or (t.startswith("https://") and t.split("?")[0].endswith(".git")):
        return "git", t, ""
    if t.startswith(("https://", "http://")):
        if not allowed(t):
            raise Bad("use an https:// link (http:// can be changed on the way)")
        return "url", t, ""
    raise Bad(f"{t}: not found here, and not a link or owner/name")


def _copy(src, out, used):
    """Copy, counting toward LIMIT; returns the new total."""
    while True:
        b = src.read(1 << 16)
        if not b:
            return used
        used += len(b)
        if used > LIMIT:
            raise Bad(f"the archive unpacks to more than {LIMIT // (1024 * 1024) or LIMIT} {'MB' if LIMIT >= 1 << 20 else 'bytes'}")
        out.write(b)


def unpack(archive, dest):
    os.makedirs(dest, exist_ok=True)
    root = os.path.realpath(dest)

    def target(name):
        if name.startswith("/") or "\\" in name:
            raise Bad(f"{name}: an absolute path in the archive")
        parts = [p for p in name.split("/") if p not in ("", ".")]
        if ".." in parts:
            raise Bad(f"{name}: points outside the archive")
        return os.path.join(root, *parts) if parts else None

    with open(archive, "rb") as f:
        magic = f.read(4)
    used = 0
    try:
        if magic[:2] == b"\x1f\x8b":
            with tarfile.open(archive, "r:gz") as tf:
                for m in tf:
                    t = target(m.name)
                    if t is None:
                        continue
                    if m.isdir():
                        os.makedirs(t, exist_ok=True)
                        continue
                    if not m.isfile():
                        raise Bad(f"{m.name}: links and special files aren't allowed in a profile")
                    os.makedirs(os.path.dirname(t), exist_ok=True)
                    with tf.extractfile(m) as src, open(t, "wb") as out:
                        used = _copy(src, out, used)
                    os.chmod(t, 0o755 if m.mode & 0o111 else 0o644)
        elif magic == b"PK\x03\x04":
            with zipfile.ZipFile(archive) as zf:
                for i in zf.infolist():
                    t = target(i.filename)
                    if t is None:
                        continue
                    if i.is_dir():
                        os.makedirs(t, exist_ok=True)
                        continue
                    kind = (i.external_attr >> 16) & 0o170000
                    if kind and kind != stat.S_IFREG:
                        raise Bad(f"{i.filename}: links and special files aren't allowed in a profile")
                    os.makedirs(os.path.dirname(t), exist_ok=True)
                    with zf.open(i) as src, open(t, "wb") as out:
                        used = _copy(src, out, used)
        else:
            raise Bad("not a .tar.gz or .zip archive")
    except (tarfile.TarError, zipfile.BadZipFile, EOFError) as e:
        raise Bad(f"a damaged archive ({e})")


class _NoDowngrade(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed(newurl):
            raise Bad(f"the link sends decal to {newurl}: only https:// is used")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, path):
    if not allowed(url):
        raise Bad("use an https:// link (http:// can be changed on the way)")
    try:
        with urllib.request.build_opener(_NoDowngrade).open(url, timeout=60) as r, open(path, "wb") as out:
            _copy(r, out, 0)
    except urllib.error.HTTPError as e:
        raise Bad(f"couldn't download {url} (HTTP {e.code})")
    except (urllib.error.URLError, OSError) as e:
        raise Bad(f"couldn't download {url} ({getattr(e, 'reason', e)})")


def fetch(url, dest):
    with tempfile.TemporaryDirectory() as tmp:
        f = os.path.join(tmp, "download")
        download(url, f)
        with open(f, "rb") as fh:
            magic = fh.read(4)
        if magic[:2] != b"\x1f\x8b" and magic != b"PK\x03\x04":
            return False
        unpack(f, dest)
        return True


def recent():
    try:
        lines = open(RECENT).read().splitlines()
    except OSError:
        return []
    return [tuple(l.split("\t", 1)) for l in lines if "\t" in l]


def remember(source):
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    keep = [(s, t) for s, t in recent() if s != source][:9]
    os.makedirs(STATE, exist_ok=True)
    with open(RECENT, "w") as f:
        f.writelines(f"{s}\t{t}\n" for s, t in [(source, now)] + keep)


def yours(source, login=""):
    if source.startswith(("/", "file://", "git+file://")) or any(s == source for s, _ in recent()):
        return True
    m = re.fullmatch(rf"github:({NAME})/{NAME}(@\S+)?", source)
    return bool(m and login and m.group(1).lower() == login.lower())


def public(source):
    """True when a github: repo answers without a key (a public repo); False when private, missing or offline."""
    m = re.fullmatch(rf"github:({OWNER}/{NAME})(@\S+)?", source)
    if not m:
        return False
    api = os.environ.get("DECAL_GITHUB_API", "https://api.github.com").rstrip("/")
    try:
        with urllib.request.urlopen(urllib.request.Request(api + "/repos/" + m.group(1),
                                    headers={"Accept": "application/vnd.github+json"}), timeout=15) as r:
            return r.status == 200
    except (urllib.error.URLError, OSError, ValueError):
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["resolve", "unpack", "fetch", "remember", "yours", "public"])
    ap.add_argument("args", nargs="+")
    ap.add_argument("--login", default="")
    a = ap.parse_args()
    try:
        if a.cmd == "resolve":
            kind, src, note = resolve(a.args[0])
            print(f"{kind}\t{src}\t{note}")
        elif a.cmd == "unpack":
            unpack(a.args[0], a.args[1])
        elif a.cmd == "fetch":
            if not fetch(a.args[0], a.args[1]):
                sys.exit(3)
            print("archive")
        elif a.cmd == "remember":
            remember(a.args[0])
        elif a.cmd == "public":
            sys.exit(0 if public(a.args[0]) else 1)
        else:
            sys.exit(0 if yours(a.args[0], a.login) else 1)
    except Bad as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
