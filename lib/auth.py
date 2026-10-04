#!/usr/bin/env python3
"""auth.py: a GitHub key for decal, by signing in (a code, with a QR code for phones) or a token you make yourself.

  auth.py get REPO --need read|write [--may-create]   ask on the terminal; prints the key on stdout
  auth.py check REPO --need read|write [--may-create] check the key in GITHUB_TOKEN (exit codes: OK, BAD_KEY, ...)
  auth.py token-url --need read|write --days N|none   the pre-filled "new token" page
  auth.py install-url --need read|write               the Decal (Write) app's install page

A key from signing in is only printed, never saved. DECAL_GITHUB / DECAL_GITHUB_API point elsewhere (tests);
DECAL_GITHUB_APP_READ / DECAL_GITHUB_APP_WRITE ("CLIENT_ID:slug") use other apps (forks, tests)."""
import argparse, os, sys, urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qrcodegen  # noqa: E402  (vendored next to this file)

WEB = os.environ.get("DECAL_GITHUB", "https://github.com").rstrip("/")
API = os.environ.get("DECAL_GITHUB_API", "https://api.github.com").rstrip("/")
# "CLIENT_ID:slug" of the Decal and Decal Write GitHub Apps (public IDs; device flow needs no secret)
APPS = {"read": "", "write": ""}
DAYS = [("30 days", "30"), ("90 days", "90"), ("1 year", "365"), ("never expires", "none")]


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
    ap.add_argument("cmd", choices=["token-url", "install-url"])
    ap.add_argument("--need", choices=["read", "write"], default="read")
    ap.add_argument("--days", type=days_arg, default="90")
    a = ap.parse_args()
    if a.cmd == "token-url":
        print(token_url(a.need, a.days))
    else:
        u = install_url(a.need)
        if not u:
            sys.exit("error: no Decal app configured")
        print(u)


if __name__ == "__main__":
    main()
