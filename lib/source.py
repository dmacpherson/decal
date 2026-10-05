#!/usr/bin/env python3
"""source.py: what a profile source is, and getting it safely.

  source.py resolve INPUT         KIND<TAB>SOURCE<TAB>NOTE (kind: dir, archive, github, url, git)

https only; DECAL_ALLOW_HTTP_LOCAL=1 also allows http://127.0.0.1 (tests)."""
import argparse, os, re, sys, urllib.parse

NAME = r"[A-Za-z0-9_.-]+"
OWNER = r"[A-Za-z0-9][A-Za-z0-9-]*"   # GitHub accounts: letters, digits, hyphens
ARCHIVES = (".tar.gz", ".tgz", ".zip")


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
    if t.startswith(("git+", "ssh://", "git@")) or (t.startswith("https://") and t.split("?")[0].endswith(".git")):
        return "git", t, ""
    if t.startswith(("https://", "http://")):
        if not allowed(t):
            raise Bad("use an https:// link (http:// can be changed on the way)")
        return "url", t, ""
    raise Bad(f"{t}: not found here, and not a link or owner/name")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["resolve"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()
    try:
        kind, src, note = resolve(a.args[0])
        print(f"{kind}\t{src}\t{note}")
    except Bad as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
