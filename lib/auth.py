#!/usr/bin/env python3
"""auth.py: a GitHub key for decal, by signing in (a code, with a QR code for phones) or a token you make yourself.

  auth.py get REPO --need read|write [--may-create]   ask on the terminal; prints the key on stdout
  auth.py check REPO --need read|write [--may-create] check the key in GITHUB_TOKEN (exit codes: OK, BAD_KEY, ...)
  auth.py token-url --need read|write --days N|none   the pre-filled "new token" page
  auth.py install-url --need read|write               the Decal (Write) app's install page

A key from signing in is only printed, never saved. DECAL_GITHUB / DECAL_GITHUB_API point elsewhere (tests);
DECAL_GITHUB_APP_READ / DECAL_GITHUB_APP_WRITE ("CLIENT_ID:slug") use other apps (forks, tests)."""
import argparse, contextlib, json, os, select, shutil, subprocess, sys, termios, time, tty as ttymod, urllib.error, urllib.parse, urllib.request

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



class Tty:
    """The terminal (or DECAL_TTY_IN / DECAL_TTY_OUT in tests): prompts never mix with decal's log on stdout/stderr."""

    def __init__(self):
        self.i = open(os.environ.get("DECAL_TTY_IN", "/dev/tty"), "rb", buffering=0)
        self.o = open(os.environ.get("DECAL_TTY_OUT", "/dev/tty"), "w")
        self.real = self.i.isatty()

    def say(self, *lines):
        for s in lines:
            print(s, file=self.o)
        self.o.flush()

    def width(self):
        try:
            return os.get_terminal_size(self.o.fileno()).columns
        except OSError:
            return shutil.get_terminal_size((80, 24)).columns

    def line(self, prompt, hidden=False):
        self.o.write(prompt)
        self.o.flush()
        old = termios.tcgetattr(self.i) if self.real and hidden else None
        try:
            if old:
                new = termios.tcgetattr(self.i)
                new[3] &= ~termios.ECHO
                termios.tcsetattr(self.i, termios.TCSADRAIN, new)
            buf = b""
            while True:
                c = self.i.read(1)
                if not c:
                    if not buf:
                        return None
                    break
                if c == b"\n":
                    break
                buf += c
        finally:
            if old:
                termios.tcsetattr(self.i, termios.TCSADRAIN, old)
                self.say("")
        return buf.decode(errors="replace").strip()

    def key(self, timeout):
        if not self.real:   # a file of keystrokes: Esc or t if that's next; anything else is for the next prompt
            pos = self.i.tell()
            c = self.i.read(1)
            if c in (b"\x1b", b"t", b"T"):
                return c.decode()
            self.i.seek(pos)
            time.sleep(timeout)
            return ""
        r, _, _ = select.select([self.i], [], [], timeout)
        return self.i.read(1).decode(errors="replace") if r else ""

    @contextlib.contextmanager
    def keys(self):
        """Key-at-a-time, no echo, for a whole wait (also while talking to GitHub); the terminal back as it was after."""
        old = termios.tcgetattr(self.i) if self.real else None
        try:
            if old:
                ttymod.setcbreak(self.i)
            yield
        finally:
            if old:
                termios.tcsetattr(self.i, termios.TCSADRAIN, old)


def open_browser(url):
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")) or not shutil.which("xdg-open"):
        return False
    try:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def copy(text):
    cmds = []
    if os.environ.get("WAYLAND_DISPLAY"):
        cmds.append(["wl-copy"])
    if os.environ.get("DISPLAY"):
        cmds += [["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]]
    for c in cmds:
        if shutil.which(c[0]):
            try:
                subprocess.run(c, input=text.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=5, check=True)
                return True
            except (OSError, subprocess.SubprocessError):
                pass
    return False


def post_form(url, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read() or b"{}") | {"error": f"HTTP {e.code}"}
        except ValueError:
            return {"error": f"HTTP {e.code}"}
    except (urllib.error.URLError, OSError) as e:
        raise Offline(str(e))


def wait_for_token(tty, cid, d):
    """The key once the person approves; or "expired", "denied", "cancel" (Esc), "paste" (t)."""
    interval = float(d.get("interval", 5))
    deadline = time.monotonic() + float(d.get("expires_in", 900))
    while time.monotonic() < deadline:
        k = tty.key(interval)
        if k == "\x1b":
            return "cancel"
        if k in ("t", "T"):
            return "paste"
        try:
            r = post_form(WEB + "/login/oauth/access_token", {"client_id": cid, "device_code": d["device_code"],
                          "grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
        except Offline:
            continue   # a blip: try again next round
        if r.get("access_token"):
            return r["access_token"]
        e = r.get("error")
        if e == "authorization_pending":
            continue
        if e == "slow_down":
            interval = float(r.get("interval", interval + 5))
            continue
        if e == "expired_token":
            return "expired"
        if e == "access_denied":
            tty.say("Sign-in was denied on GitHub.")
            return "denied"
        tty.say("GitHub stopped the sign-in: " + (r.get("error_description") or e or "no reason given"))
        return "denied"
    return "expired"


def wait_for_access(tty, repo, need, token, may_create):
    """TOKEN once it can see REPO (the app may need installing on it first); None if it never does."""
    every = float(os.environ.get("DECAL_AUTH_RECHECK", "5"))
    give_up = time.monotonic() + float(os.environ.get("DECAL_AUTH_WAIT", "600"))
    told = False
    while True:
        c = check(repo, need, token, may_create)
        if c == OK:
            tty.say("Signed in.")
            return token
        if c != CANT_SEE:
            tty.say(WHY[c].format(repo=repo))
            return None
        if time.monotonic() >= give_up:
            tty.say(f"decal still can't see {repo}: check the name (it may be misspelled), or that the app is installed on it")
            return None
        if not told:
            name = "Decal" if need == "read" else "Decal Write"
            tty.say("", f"{name} can't see {repo} yet: install it on that repo (or check the name)",
                    f"  {install_url(need)}", "", "Waiting for it...   Esc cancel")
            told = True
        if tty.key(every) == "\x1b":
            return None


def sign_in(tty, repo, need, may_create):
    """The key; or "paste" (the person pressed t), or None (cancelled, denied, failed: back to the choice)."""
    cid, _ = app(need)
    while True:
        try:
            d = post_form(WEB + "/login/device/code", {"client_id": cid})
        except Offline:
            tty.say(WHY[OFFLINE])
            return None
        if "device_code" not in d:
            tty.say("GitHub didn't start a sign-in: " + (d.get("error_description") or d.get("error") or "no reason given"))
            return None
        url, code = d["verification_uri"], d["user_code"]
        opened, copied = open_browser(url), copy(code)
        tty.say("", *layout(repo, need, code, url, qr_lines(url), tty.width(), opened, copied))
        with tty.keys():
            r = wait_for_token(tty, cid, d)
        if r == "expired":
            tty.say("", "The code expired: here's a new one.")
            continue
        if r == "paste":
            return "paste"
        if r in ("cancel", "denied"):
            return None
        with tty.keys():
            return wait_for_access(tty, repo, need, r, may_create)


def make_token(tty, repo, need, may_create):
    """A token the person makes on GitHub's pre-filled page and pastes; None if they give up."""
    tty.say("", "How long should the token last?")
    for i, (label, _) in enumerate(DAYS, 1):
        tty.say(f"  {i}) {label}" + ("   (default)" if i == 2 else ""))
    a = tty.line("Choose [2]: ")
    if a is None:
        return None
    days = DAYS[int(a) - 1][1] if a in ("1", "2", "3", "4") else DAYS[1][1]
    url = token_url(need, days)
    where = ('choose "All repositories" (decal creates ' + repo.split("/")[-1] + " if it isn't there yet)") if may_create \
        else f'choose "Only select repositories" and pick {repo.split("/")[-1]}'
    tty.say("", "Opened in your browser:" if open_browser(url) else "Open this page:", "  " + url,
            f'Under "Repository access" {where}, then press "Generate token".')
    while True:
        t = tty.line("Paste the token (typing is hidden; Enter alone to go back): ", hidden=True)
        if not t:
            return None
        c = check(repo, need, t, may_create)
        if c == OK:
            return t
        tty.say(WHY[c].format(repo=repo) + ": try again")


def get(tty, repo, need, may_create):
    while True:
        opts = ([("Sign in with GitHub", "sign")] if app(need) else []) + \
               [("Make a token myself", "token"), ("Cancel", "cancel")]
        tty.say("", f"decal needs a GitHub key to {'read' if need == 'read' else 'save to'} {repo}:")
        for i, (label, _) in enumerate(opts, 1):
            tty.say(f"  {i}) {label}")
        a = tty.line("Choose [1]: ")
        if a is None:
            return None
        a = a or "1"
        if not a.isdigit() or not 1 <= int(a) <= len(opts):
            continue
        pick = opts[int(a) - 1][1]
        if pick == "cancel":
            return None
        t = make_token(tty, repo, need, may_create) if pick == "token" else sign_in(tty, repo, need, may_create)
        if t == "paste":
            t = make_token(tty, repo, need, may_create)
        if t:
            return t

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
    ap.add_argument("cmd", choices=["get", "check", "token-url", "install-url"])
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
    elif a.cmd == "get":
        if not a.repo:
            ap.error("get needs a repo")
        try:
            t = get(Tty(), a.repo, a.need, a.may_create)
        except OSError:
            sys.exit("error: no terminal to ask on: set GITHUB_TOKEN or log in with gh auth login")
        except KeyboardInterrupt:
            sys.exit(130)
        if not t:
            sys.exit(1)
        print(t)
    else:
        if not a.repo:
            ap.error("check needs a repo")
        sys.exit(check(a.repo, a.need, os.environ.get("GITHUB_TOKEN", ""), a.may_create))

if __name__ == "__main__":
    main()
