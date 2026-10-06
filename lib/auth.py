#!/usr/bin/env python3
"""auth.py: a GitHub key for decal, by signing in (a code, with a QR code for phones) or a token you make yourself.

  auth.py get REPO --need read|write [--may-create]   ask on the terminal; prints the key on stdout
  auth.py check REPO --need read|write [--may-create] check the key in GITHUB_TOKEN (exit codes: OK, BAD_KEY, ...)
  auth.py token-url --need read|write --days N|none   the pre-filled "new token" page
  auth.py install-url --need read|write               the Decal Profile (Write) app's install page

A key from signing in is only printed, never saved. DECAL_GITHUB / DECAL_GITHUB_API point elsewhere (tests);
DECAL_GITHUB_APP_READ / DECAL_GITHUB_APP_WRITE ("CLIENT_ID:slug") use other apps (forks, tests)."""
import argparse, contextlib, http.client, json, os, re, select, shutil, subprocess, sys, termios, time, tty as ttymod, urllib.error, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qrcodegen  # noqa: E402  (vendored next to this file)
import gh  # noqa: E402
from gh import WEB, Offline  # noqa: E402
# "CLIENT_ID:slug" of the Decal Profile and Decal Profile Write GitHub Apps (public IDs; device flow needs no secret)
APPS = {"read": "Iv23li49m8npqJvYxiW8:decal-profile", "write": "Iv23lia2BX1vjfZuUstJ:decal-profile-write"}
DAYS = [("30 days", "30"), ("90 days", "90"), ("1 year", "365"), ("never expires", "none")]
OK, BAD_KEY, CANT_SEE, READ_ONLY, OFFLINE, BUSY = 0, 10, 11, 12, 13, 14
WHY = {BAD_KEY: "GitHub didn't accept that key (mistyped, revoked or expired)",
       CANT_SEE: "that key can't see {repo}: it doesn't exist, or the key wasn't given access to it",
       READ_ONLY: "that key can only read {repo}; saving needs one that can write",
       OFFLINE: "couldn't reach GitHub: check the internet connection",
       BUSY: "GitHub isn't answering properly right now: try again in a minute"}


def busy(code):
    """GitHub having trouble (a 5xx) or asking us to slow down (429): nothing to do with the key."""
    return code >= 500 or code == 429


def check(repo, need, token, may_create=False):
    """OK when TOKEN can read (or write) REPO; with MAY_CREATE a missing repo is fine (stamp creates it)."""
    try:
        code, me = gh.get("/user", token)
        if busy(code):
            return BUSY
        if code == 401:
            return BAD_KEY
        if repo == "-":   # signing in to list your profiles: the key works, that's all
            return OK if code == 200 else BAD_KEY
        if "/" not in repo:   # stamp before it knows the owner: the key's account
            if code != 200:
                return BAD_KEY
            repo = f"{me.get('login')}/{repo}"
        code, info = gh.get(f"/repos/{repo}", token)
        if busy(code):
            return BUSY
        if code == 401:
            return BAD_KEY
        if code == 404 and may_create:
            return OK if can_create(token) else CANT_SEE
        if code != 200:
            return CANT_SEE
        if need == "write" and not info.get("permissions", {}).get("push", False):
            return READ_ONLY
        return OK
    except Offline:
        return OFFLINE



def scopes_write(scopes):
    """A classic token's X-OAuth-Scopes: can it write to repos?"""
    return any(s.strip() in ("repo", "public_repo") for s in scopes.split(","))


def stick_ok(token):
    """"" when TOKEN may be saved on a USB stick (it can only read); else why not."""
    if token.startswith(("ghp_", "gho_")):
        return "a classic or gh token can write to your repos"
    try:
        code, _, headers = gh.request("GET", "/user", token)
    except Offline:
        return ""   # checked again when it's used; reading is all the stick does
    scopes = (headers.get("X-OAuth-Scopes") or "") if code == 200 else ""
    return "that token can write to your repos (repo scope)" if scopes_write(scopes) else ""


def shown(repo):
    return "your profiles" if repo == "-" else repo


def can_create(token):
    """A repo the key can't see may be created: yes, unless it's an app key whose app is on picked repos only (it
    could neither create a new repo nor see one that's already there and not picked)."""
    code, d = gh.get("/user/installations", token)
    if code != 200:   # not an app's key (a token you made): GitHub decides when decal creates it
        return True
    return any(i.get("repository_selection") == "all" for i in d.get("installations", []))


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
        """A key pressed within TIMEOUT: Esc, t, or "" once TIMEOUT is over (nothing, or other keys: an arrow or
        F-key's escape sequence is read whole, so it neither cancels nor reaches the next prompt)."""
        end = time.monotonic() + timeout
        while True:
            k = self._key(max(0.0, end - time.monotonic()))
            if k or time.monotonic() >= end:
                return k

    def _key(self, timeout):
        if not self.real:   # a file of keystrokes: Esc or t if that's next; anything else is for the next prompt
            pos = self.i.tell()
            c = self.i.read(1)
            if c == b"\x1b":
                after = self.i.tell()
                if self._sequence(lambda: self.i.read(1)):
                    return ""
                self.i.seek(after)   # a plain Esc: what follows is for the next prompt
            if c in (b"\x1b", b"t", b"T"):
                return c.decode()
            self.i.seek(pos)
            time.sleep(timeout)
            return ""
        r, _, _ = select.select([self.i], [], [], timeout)
        if not r:
            return ""
        c = self.i.read(1)
        if c == b"\x1b" and self._sequence(lambda: self.i.read(1) if select.select([self.i], [], [], 0.05)[0] else b""):
            return ""
        return c.decode(errors="replace")

    @staticmethod
    def _sequence(more):
        """After an Esc: True (and the rest read) when an escape sequence follows (ESC [ ... or ESC O x)."""
        c = more()
        if c == b"O":
            more()
            return True
        if c != b"[":
            return False
        while (c := more()) and not 0x40 <= c[0] <= 0x7e:
            pass
        return True

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
            d = json.loads(r.read() or b"{}")
            return d if isinstance(d, dict) else {}
    except urllib.error.HTTPError as e:
        try:
            d = json.loads(e.read() or b"{}")
            return {"error": f"HTTP {e.code}"} | (d if isinstance(d, dict) else {})   # GitHub's own error name wins
        except ValueError:
            return {"error": f"HTTP {e.code}"}
    except (urllib.error.URLError, OSError, http.client.HTTPException, ValueError) as e:
        raise Offline(str(e))   # no answer, or not GitHub's (a Wi-Fi login page)


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
        if "/" not in repo:   # stamp before it knows the owner: the account that just signed in
            try:
                code, me = gh.get("/user", token)
                if code == 200:
                    repo = f"{me.get('login')}/{repo}"
            except Offline:
                pass
        c = check(repo, need, token, may_create)
        if c == OK:
            tty.say("Signed in.")
            return token
        if c not in (CANT_SEE, OFFLINE, BUSY):   # OFFLINE, BUSY: a blip, keep the approved key and try again
            tty.say(WHY[c].format(repo=repo))
            return None
        if time.monotonic() >= give_up:
            tty.say(f"decal still can't see {repo}: check the name (it may be misspelled), or that the app is installed on it")
            return None
        if not told and c == CANT_SEE:
            url = install_url(need)
            opened = open_browser(url)
            tty.say("", *install_layout(need, repo, url, qr_lines(url), tty.width(), opened, may_create))
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
            if d.get("error") == "device_flow_disabled":   # a fork's app set up without it
                tty.say("This GitHub app can't sign in with a code here: choose Make a token myself.")
            else:
                tty.say("GitHub didn't start a sign-in: " + (d.get("error_description") or d.get("error") or "no reason given"))
            return None
        url, code = d["verification_uri"], d["user_code"]
        opened, copied = open_browser(url), copy(code)
        with tty.keys():   # key-at-a-time before the screen says it's waiting: a key pressed at once counts
            tty.say("", *layout(repo, need, code, url, qr_lines(url), tty.width(), opened, copied))
            r = wait_for_token(tty, cid, d)
        if r == "expired":
            tty.say("", "The code expired: here's a new one.")
            continue
        if r == "paste":
            return "paste"
        if r in ("cancel", "denied"):
            return None
        if repo == "-":
            tty.say("Signed in.")
            return r
        with tty.keys():
            return wait_for_access(tty, repo, need, r, may_create)


def make_token(tty, repo, need, may_create):
    """A token the person makes on GitHub's pre-filled page and pastes; None if they give up."""
    tty.say("", "How long should the token last?")
    for i, (label, _) in enumerate(DAYS, 1):
        tty.say(f"  {i}) {label}" + ("   (default)" if i == 2 else ""))
    while True:   # an answer that isn't 1-4 asks again
        a = tty.line("Choose [2]: ")
        if a is None:
            return None
        if (a or "2") in ("1", "2", "3", "4"):
            break
    days = DAYS[int(a or "2") - 1][1]
    url = token_url(need, days)
    where = ('choose "All repositories" (decal creates ' + repo.split("/")[-1] + " if it isn't there yet)") if may_create \
        else 'choose "Only select repositories" and pick your profile repos' if repo == "-" \
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
        tty.say("", f"decal needs a GitHub key to {'read' if need == 'read' else 'save to'} {shown(repo)}:")
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
    what = "read" if need == "read" else "save to"
    return [f"Sign in to GitHub so decal can {what} {shown(repo)}", ""] + columns(left, right, width) + \
           ["", "Waiting for GitHub...   Esc cancel \u00b7 t paste a token instead"]


def install_layout(need, repo, url, qr, width, opened=False, may_create=False):
    """The app can't see REPO yet: install it here (the page, maybe opened for you) or from a phone (the QR code)."""
    name = "Decal Profile" if need == "read" else "Decal Profile Write"
    left = ["On this computer", "\u2500" * 16, "1. Open the install page",
            "   (opened in your browser)" if opened else "   (the link below)",
            *(['2. Choose "All repositories"', f'   (decal creates {repo.split("/")[-1]})'] if may_create else
              ['2. Choose "Only select', f'   repositories": {repo.split("/")[-1]}']), "3. Press Install"]
    right = ["On your phone", "\u2500" * 13] + qr + ["Scan to install from your phone"]
    return [f"{name} can't see {repo} yet: install it on that repo (or check the name)", ""] + \
           columns(left, right, width) + ["", "  " + url, "", "Waiting for it...   Esc cancel"]


def columns(left, right, width):
    """LEFT and RIGHT side by side when the terminal is wide enough (76 at least), else one under the other."""
    widest = max(len(re.sub(r"\033\[[0-9;]*m", "", r)) for r in right)
    if width >= max(76, 41 + widest):
        return [(left[i] if i < len(left) else "").ljust(41) + (right[i] if i < len(right) else "")
                for i in range(max(len(left), len(right)))]
    return left + [""] + right


def days_arg(v):
    if v == "none" or (v.isdigit() and 1 <= int(v) <= 366):
        return v
    raise argparse.ArgumentTypeError("a number of days from 1 to 366, or none")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["get", "check", "stick-ok", "token-url", "install-url"])
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
            sys.exit("error: no Decal Profile app configured")
        print(u)
    elif a.cmd == "stick-ok":   # the key in GITHUB_TOKEN may go on a USB stick: exit 1 with the reason when not
        why = stick_ok(os.environ.get("GITHUB_TOKEN", ""))
        if why:
            sys.exit(f"error: {why}")
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
        c = check(a.repo, a.need, os.environ.get("GITHUB_TOKEN", ""), a.may_create)
        if c != OK:
            print(WHY[c].format(repo=a.repo), file=sys.stderr)
        sys.exit(c)

if __name__ == "__main__":
    main()
