#!/usr/bin/env python3
"""auth.py: a GitHub key for decal, by signing in (a code, with a QR code for phones) or a token you make yourself.

  auth.py get REPO --need read|write [--may-create]   ask on the terminal; prints the key on stdout
  auth.py check REPO --need read|write [--may-create] check the key in GITHUB_TOKEN (exit codes: OK, BAD_KEY, ...)
  auth.py token-url --need read|write --days N|none   the pre-filled "new token" page
  auth.py install-url --need read|write               the Decal (Write) app's install page

A key from signing in is only printed, never saved. DECAL_GITHUB / DECAL_GITHUB_API point elsewhere (tests);
DECAL_GITHUB_APP_READ / DECAL_GITHUB_APP_WRITE ("CLIENT_ID:slug") use other apps (forks, tests)."""
import argparse, json, os, sys, urllib.error, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qrcodegen  # noqa: E402  (vendored next to this file)

WEB = os.environ.get("DECAL_GITHUB", "https://github.com").rstrip("/")
API = os.environ.get("DECAL_GITHUB_API", "https://api.github.com").rstrip("/")
# "CLIENT_ID:slug" of the Decal and Decal Write GitHub Apps (public IDs; device flow needs no secret)
APPS = {"read": "", "write": ""}
DAYS = [("30 days", "30"), ("90 days", "90"), ("1 year", "365"), ("never expires", "none")]
OK, BAD_KEY, CANT_SEE, READ_ONLY, OFFLINE = 0, 10, 11, 12, 13
WHY = {BAD_KEY: "GitHub didn't accept that key (mistyped, revoked or expired)",
       CANT_SEE: "that key can't see {repo}: it doesn't exist, or the key wasn't given access to it",
       READ_ONLY: "that key can only read {repo}; saving needs one that can write",
       OFFLINE: "couldn't reach GitHub: check the internet connection"}


class Offline(Exception):
    pass


def api_get(path, token):
    req = urllib.request.Request(API + path, headers={"Accept": "application/vnd.github+json",
                                                      "Authorization": "Bearer " + token,
                                                      "X-GitHub-Api-Version": "2022-11-28"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {}
    except (urllib.error.URLError, OSError) as e:
        raise Offline(str(e))


def check(repo, need, token, may_create=False):
    """OK when TOKEN can read (or write) REPO; with MAY_CREATE a missing repo is fine (stamp creates it)."""
    try:
        code, _ = api_get("/user", token)
        if code == 401:
            return BAD_KEY
        if "/" not in repo:   # stamp before it knows the owner: the key works, the repo comes later
            return OK if code == 200 else BAD_KEY
        code, info = api_get(f"/repos/{repo}", token)
        if code == 401:
            return BAD_KEY
        if code == 404 and may_create:
            return OK
        if code != 200:
            return CANT_SEE
        if need == "write" and not info.get("permissions", {}).get("push", False):
            return READ_ONLY
        return OK
    except Offline:
        return OFFLINE


def app(need):
    v = os.environ.get("DECAL_GITHUB_APP_" + need.upper(), APPS[need])
    cid, _, slug = v.partition(":")
    return (cid, slug) if cid and slug else None


def token_url(need, days):
    q = {"name": "Decal", "description": "decal: " + ("read" if need == "read" else "save") + " your profile",
         "expires_in": days, "contents": need}
    if need == "write":
        q["administration"] = "write"   # creating the repo on a first stamp
    return WEB + "/settings/personal-access-tokens/new?" + urllib.parse.urlencode(q)


def install_url(need):
    a = app(need)
    return f"{WEB}/apps/{a[1]}/installations/new" if a else None


def qr_lines(text, border=2):
    q = qrcodegen.QrCode.encode_text(text, qrcodegen.QrCode.Ecc.LOW)
    n = q.get_size()
    rows = []
    for y in range(-border, n + border, 2):
        s = ""
        for x in range(-border, n + border):
            top, bot = q.get_module(x, y), q.get_module(x, y + 1)   # False outside the code: the quiet zone
            s += "█" if top and bot else "▀" if top else "▄" if bot else " "
        rows.append("\033[30;47m" + s + "\033[0m")   # black on white, whatever the terminal's colours
    return rows


def layout(repo, need, code, url, qr, width, opened=False, copied=False):
    host = url.split("://", 1)[-1]
    left = ["On this computer", "─" * 16, f"1. Open  {host}"]
    if opened:
        left.append("   (opened in your browser)")
    left.append(f"2. Enter {code}")
    if copied:
        left.append("   (copied to your clipboard)")
    right = ["On your phone", "─" * 13] + qr + [f"Scan, then enter {code}"]
    if width >= 76:
        rows = [(left[i] if i < len(left) else "").ljust(41) + (right[i] if i < len(right) else "")
                for i in range(max(len(left), len(right)))]
    else:
        rows = left + [""] + right
    what = "read" if need == "read" else "save to"
    return [f"Sign in to GitHub so decal can {what} {repo}", ""] + rows + \
           ["", "Waiting for GitHub...   Esc cancel · t paste a token instead"]


def days_arg(v):
    if v == "none" or (v.isdigit() and 1 <= int(v) <= 366):
        return v
    raise argparse.ArgumentTypeError("a number of days from 1 to 366, or none")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["check", "token-url", "install-url"])
    ap.add_argument("repo", nargs="?")
    ap.add_argument("--need", choices=["read", "write"], default="read")
    ap.add_argument("--may-create", action="store_true")
    ap.add_argument("--days", type=days_arg, default="90")
    a = ap.parse_args()
    if a.cmd == "token-url":
        print(token_url(a.need, a.days))
    elif a.cmd == "install-url":
        u = install_url(a.need)
        if not u:
            sys.exit("error: no Decal app configured")
        print(u)
    else:
        if not a.repo:
            ap.error("check needs a repo")
        sys.exit(check(a.repo, a.need, os.environ.get("GITHUB_TOKEN", ""), a.may_create))

if __name__ == "__main__":
    main()
