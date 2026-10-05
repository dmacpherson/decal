#!/usr/bin/env python3
"""source.py: what a profile source is, and getting it safely.

  source.py resolve INPUT         KIND<TAB>SOURCE<TAB>NOTE (kind: dir, archive, github, url, git)
  source.py unpack [--links inside] ARCHIVE DIR   an archive, safely: nothing outside DIR, no links (or only
                                  links that stay inside), 200 MB at most
  source.py fetch URL DIR         download; an archive is unpacked into DIR (prints "archive"); else exit 3
  source.py remember SOURCE       put SOURCE first in the recently-used list (10 kept; never a key)
  source.py yours SOURCE [--login L]  exit 0 when SOURCE is yours: local, recently used, or L's on GitHub
  source.py public github:O/R     exit 0 when the repo is public (answers without a key)
  source.py github O/R OUT [--ref REF]   the repo as a .tar.gz (key from GITHUB_TOKEN); exit 4 when not found or
                                  not allowed, 3 when GitHub can't be reached

https only; DECAL_ALLOW_HTTP_LOCAL=1 also allows http://127.0.0.1 (tests)."""
import argparse, datetime, os, re, stat, sys, tarfile, tempfile, urllib.error, urllib.parse, urllib.request, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gh  # noqa: E402

NAME = r"[A-Za-z0-9_.-]+"
OWNER = r"[A-Za-z0-9][A-Za-z0-9-]*"   # GitHub accounts: letters, digits, hyphens
ARCHIVES = (".tar.gz", ".tgz", ".zip")
LIMIT = int(os.environ.get("DECAL_UNPACK_LIMIT", str(200 * 1024 * 1024)))
STATE = os.environ.get("DECAL_USER_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "decal")
RECENT = os.path.join(STATE, "recent")


class Bad(Exception):
    code = None   # a download's HTTP status (0: no answer)


def allowed(url):
    u = urllib.parse.urlparse(url)
    return u.scheme == "https" or (u.scheme == "http" and u.hostname in ("127.0.0.1", "localhost")
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


def unpack(archive, dest, links="none"):
    """A .tar.gz/.tgz/.tar.xz/.tar.bz2/.tar or .zip, safely: nothing outside DEST, no devices, a size cap. Links are
    refused unless links="inside" (themes need them), and then only links that stay inside DEST."""
    os.makedirs(dest, exist_ok=True)
    root = os.path.realpath(dest)

    def target(name):
        if name.startswith("/") or "\\" in name:
            raise Bad(f"{name}: an absolute path in the archive")
        parts = [p for p in name.split("/") if p not in ("", ".")]
        if ".." in parts:
            raise Bad(f"{name}: points outside the archive")
        return os.path.join(root, *parts) if parts else None

    def within(p):
        return p == root or p.startswith(root + os.sep)

    def safe(member, t):
        """T may be written: its folder, with every link unpacked so far followed, is inside DEST, and T itself isn't a
        link (writing would follow it). A chain of links can't walk out: the real path is checked, not the text."""
        if not within(os.path.realpath(os.path.dirname(t))) or os.path.islink(t):
            raise Bad(f"{member}: points outside the archive")
        return t

    def link_ok(member, t, linkname):
        if linkname.startswith("/") or not within(os.path.realpath(os.path.join(os.path.realpath(os.path.dirname(t)), linkname))):
            raise Bad(f"{member}: a link that points outside the archive")

    def write(member, t, src):
        nonlocal used
        os.makedirs(os.path.dirname(safe(member, t)), exist_ok=True)
        safe(member, t)   # again: makedirs may have gone through a link
        fd = os.open(t, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "wb") as out:
            used = _copy(src, out, used)

    with open(archive, "rb") as f:
        magic = f.read(4)
    used = 0
    try:
        if magic == b"PK\x03\x04":
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
                    with zf.open(i) as src:
                        write(i.filename, t, src)
            return
        try:
            tf = tarfile.open(archive, "r:*")   # gzip, xz, bzip2 or plain
        except tarfile.TarError:
            raise Bad("not an archive (.tar.gz, .tar.xz, .tar.bz2, .tar or .zip)")
        with tf:
            for m in tf:
                t = target(m.name)
                if t is None:
                    continue
                if m.isdir():
                    safe(m.name, t)
                    os.makedirs(t, exist_ok=True)
                    safe(m.name, os.path.join(t, "."))
                elif m.isfile():
                    with tf.extractfile(m) as src:
                        write(m.name, t, src)
                    os.chmod(t, 0o755 if m.mode & 0o111 else 0o644)
                elif links == "inside" and m.issym():
                    os.makedirs(os.path.dirname(safe(m.name, t)), exist_ok=True)
                    link_ok(m.name, t, m.linkname)
                    os.symlink(m.linkname, t)
                elif links == "inside" and m.islnk():   # a hard link: a copy of a file already unpacked
                    src = target(m.linkname)
                    if not src or not within(os.path.realpath(src)) or not os.path.isfile(src) or os.path.islink(src):
                        raise Bad(f"{m.name}: a link that points outside the archive")
                    with open(src, "rb") as fh:
                        write(m.name, t, fh)
                else:
                    raise Bad(f"{m.name}: links and special files aren't allowed in a profile")
    except (tarfile.TarError, zipfile.BadZipFile, EOFError, OSError) as e:
        raise Bad(f"a damaged archive ({e})")


class _NoDowngrade(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed(newurl):
            raise Bad(f"the link sends decal to {newurl}: only https:// is used")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _origin(url):
    u = urllib.parse.urlparse(url)
    return u.scheme, u.hostname, u.port or {"https": 443, "http": 80}.get(u.scheme)


class _KeyStaysHome(_NoDowngrade):
    """A redirect to another host (GitHub hands downloads to codeload) doesn't take the key along."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and _origin(newurl) != _origin(req.full_url):   # as curl: another scheme, host or port
            new.remove_header("Authorization")
        return new


def download(url, path, token=None):
    """URL to PATH: https only (no redirect to http), within the size limit; TOKEN as a header, for that host only."""
    if not allowed(url):
        raise Bad("use an https:// link (http:// can be changed on the way)")
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token} if token else {})
    try:
        with urllib.request.build_opener(_KeyStaysHome).open(req, timeout=60) as r, open(path, "wb") as out:
            _copy(r, out, 0)
    except urllib.error.HTTPError as e:
        b = Bad(f"couldn't download {url} (HTTP {e.code})"); b.code = e.code; raise b
    except (urllib.error.URLError, OSError) as e:
        b = Bad(f"couldn't download {url} ({getattr(e, 'reason', e)})"); b.code = 0; raise b


def github(repo, out, ref=""):
    """OWNER/REPO (at REF) as a .tar.gz, with the key in GITHUB_TOKEN when there is one."""
    download(f"{gh.API}/repos/{repo}/tarball" + (f"/{urllib.parse.quote(ref, safe='/')}" if ref else ""), out, os.environ.get("GITHUB_TOKEN") or None)


def fetch(url, dest):
    with tempfile.TemporaryDirectory() as tmp:
        f = os.path.join(tmp, "download")
        download(url, f)
        with open(f, "rb") as fh:
            magic = fh.read(4)
        if magic[:2] != b"\x1f\x8b" and magic != b"PK\x03\x04":   # profiles: .tar.gz/.tgz or .zip
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
    with open(RECENT + ".decal-new", "w") as f:
        f.writelines(f"{s}\t{t}\n" for s, t in [(source, now)] + keep)
    os.replace(RECENT + ".decal-new", RECENT)


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
    try:
        return gh.request("GET", "/repos/" + m.group(1), timeout=15)[0] == 200
    except gh.Offline:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["resolve", "unpack", "fetch", "remember", "yours", "public", "github"])
    ap.add_argument("args", nargs="+")
    ap.add_argument("--login", default="")
    ap.add_argument("--ref", default="")
    ap.add_argument("--links", choices=["none", "inside"], default="none")
    a = ap.parse_args()
    try:
        if a.cmd == "resolve":
            kind, src, note = resolve(a.args[0])
            print(f"{kind}\t{src}\t{note}")
        elif a.cmd == "unpack":
            unpack(a.args[0], a.args[1], a.links)
        elif a.cmd == "fetch":
            if not fetch(a.args[0], a.args[1]):
                sys.exit(3)
            print("archive")
        elif a.cmd == "remember":
            remember(a.args[0])
        elif a.cmd == "github":   # 4: not found or not allowed (private?) · 3: GitHub out of reach
            try:
                github(a.args[0], a.args[1], a.ref)
            except Bad as e:
                if e.code in (401, 403, 404):
                    sys.exit(4)
                if e.code == 0:
                    sys.exit(3)
                raise
        elif a.cmd == "public":
            sys.exit(0 if public(a.args[0]) else 1)
        else:
            sys.exit(0 if yours(a.args[0], a.login) else 1)
    except Bad as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
