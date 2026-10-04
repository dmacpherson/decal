# GitHub Sign-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** decal gets a GitHub key by signing in (device code, shown with a QR code for phones) or a token the person makes on a pre-filled page, and never stores a key it got by signing in.

**Architecture:** A new Python helper, `lib/auth.py`, owns everything about getting and checking a key (terminal prompts on `/dev/tty`, GitHub's device flow, the install-the-app wait, the pre-filled token page). The `decal` bash script keeps its "a key that's already there" logic (`gh_token`) and calls `auth.py get` when it needs to ask, exporting the result as `GITHUB_TOKEN` for the rest of the run. QR codes come from Nayuki's qrcodegen, vendored as `lib/qrcodegen.py`.

**Tech Stack:** bash, Python 3 standard library (urllib, termios, select), qrcodegen v1.8.0 (MIT), decal's bash test harness (`tests/lib.sh`) with a fake GitHub server (`tests/fixtures/fake_github_api.py`).

**Spec:** `docs/superpowers/specs/2026-10-04-github-sign-in-design.md`

## Global Constraints

- User-facing names: **Decal** (read app), **Decal Write** (write app); commands and files lowercase `decal`.
- A key obtained by signing in is never written to disk by decal; it lives in memory / the environment for one run.
- Key order: `GITHUB_TOKEN`, then `GH_TOKEN`, then `gh auth token`, then ask (sign in / make a token myself / cancel).
- Token page expiry choices: 30 days / 90 days (default) / 1 year (365) / never expires (`none`); GitHub accepts 1–366 or `none`.
- Read key permissions: Contents read. Write: Contents write + Administration write (creating repos).
- The QR code encodes `https://github.com/login/device` (the server's `verification_uri`); the code is shown in both columns.
- Two columns at 76+ terminal columns, stacked below that.
- Browser opened only with `DISPLAY`/`WAYLAND_DISPLAY` set and `xdg-open` present; code copied with `wl-copy` / `xclip` / `xsel`; the "(opened…)" / "(copied…)" notes show only when that happened.
- No test touches the network; tests unset `DISPLAY`/`WAYLAND_DISPLAY` and stub `gh` so a real login never leaks in.
- Python: standard library only (plus the vendored qrcodegen). Bash: shellcheck-clean.
- Commit messages follow the repo style (one descriptive line, lowercase start, `area: what changed`), then a blank line and:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

- Ctrl+C or a crash while the terminal is in key-at-a-time mode must leave the terminal usable (echo back on) and exit without a traceback. (Task 3: `KeyboardInterrupt` test + `try/finally` around every termios change.)
- A pasted token with spaces or a trailing newline from the browser must still work. (Task 3: paste `"  s3cret  "` test.)
- GitHub answering the device-code request with an HTTP error (5xx, or 404 because the app has device flow switched off) must give a plain message and go back to the menu, not a traceback. (Task 3: `device_fail` test.)
- A misspelled repo looks exactly like "app not installed" to a signed-in key; the wait must end on its own and say the name may be wrong. (Task 3: `DECAL_AUTH_WAIT=0` test.)
- A real `gh` login or `DISPLAY` on the developer's machine must never change test results. (Task 2–4 test setup: `stub gh 'exit 1'`, `unset DISPLAY WAYLAND_DISPLAY`.)

---

### Task 1: QR code, screen layout and token links (pure helpers)

**Files:**
- Create: `lib/qrcodegen.py` (vendored, unchanged)
- Create: `lib/auth.py`
- Create: `tests/test_auth.sh`
- Modify: `docs/superpowers/specs/2026-10-04-github-sign-in-design.md` (write token page also pre-fills Administration write)

**Interfaces:**
- Produces (in `lib/auth.py`):
  - `app(need: str) -> tuple[str, str] | None` — `(client_id, slug)` of the Decal (`"read"`) or Decal Write (`"write"`) app, from `DECAL_GITHUB_APP_READ` / `DECAL_GITHUB_APP_WRITE` (`"CLIENT_ID:slug"`) or the built-in `APPS`; `None` when not configured.
  - `token_url(need: str, days: str) -> str`
  - `install_url(need: str) -> str | None`
  - `qr_lines(text: str, border: int = 2) -> list[str]` — rows of half-block characters wrapped in `\033[30;47m…\033[0m`.
  - `layout(repo: str, need: str, code: str, url: str, qr: list[str], width: int, opened: bool = False, copied: bool = False) -> list[str]`
  - Constants `WEB`, `API`, `APPS`, `DAYS`.
  - CLI: `auth.py token-url --need read|write --days N|none`, `auth.py install-url --need read|write`.

- [ ] **Step 1: Vendor qrcodegen**

```bash
cd /var/home/denis/Work/decal
curl -fsSL https://raw.githubusercontent.com/nayuki/QR-Code-generator/v1.8.0/python/qrcodegen.py -o lib/qrcodegen.py
echo "b089855caf16185c61421ea4927c1b213cf9468940d71fa8ab11ef83662dcc84  lib/qrcodegen.py" | sha256sum -c
```
Expected: `lib/qrcodegen.py: OK`

- [ ] **Step 2: Write the failing tests**

Create `tests/test_auth.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN
A="$REPO/lib/auth.py"
py() { python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import auth; $1"; }

# the QR code: half-blocks that decode back to qrcodegen's own matrix for the link (2-module quiet zone)
out=$(py '
import qrcodegen, re
url = "https://github.com/login/device"
q = qrcodegen.QrCode.encode_text(url, qrcodegen.QrCode.Ecc.LOW)
rows = [re.sub(r"\x1b\[[0-9;]*m", "", r) for r in auth.qr_lines(url)]
n, b = q.get_size(), 2
ok = len(rows) == (n + 2 * b + 1) // 2 and all(len(r) == n + 2 * b for r in rows)
for y in range(-b, n + b):
    for x in range(-b, n + b):
        ch = rows[(y + b) // 2][x + b]
        top = (y + b) % 2 == 0
        dark = ch == "█" or (ch == "▀" and top) or (ch == "▄" and not top)
        ok = ok and dark == (0 <= x < n and 0 <= y < n and q.get_module(x, y))
print("ok" if ok else "mismatch", n)')
assert_eq "$out" "ok 25" "QR rows decode to the link's matrix (version 2, 25 modules)"
assert_contains "$(py 'print(repr(auth.qr_lines("x")[0]))')" '\x1b[30;47m' "QR drawn black on white, readable on dark terminals"

# the screen: two columns when wide, stacked when narrow; notes only when they happened
L=$(py 'print("\n".join(auth.layout("me/prof", "read", "WDJB-MJHT", "https://github.com/login/device", ["QQQ"], 100)))')
assert_contains "$L" "Sign in to GitHub so decal can read me/prof" "heading names the repo"
assert_contains "$L" "On this computer                         On your phone" "two columns at 100 wide"
assert_contains "$L" "1. Open  github.com/login/device" "the link, without https://"
assert_contains "$L" "2. Enter WDJB-MJHT" "the code"
assert_contains "$L" "Scan, then enter WDJB-MJHT" "the code under the QR too"
assert_contains "$L" "Esc cancel · t paste a token instead" "the keys"
assert_not_contains "$L" "opened in your browser" "no browser note when it wasn't opened"
assert_not_contains "$L" "copied to your clipboard" "no clipboard note when it wasn't copied"
L=$(py 'print("\n".join(auth.layout("me/prof", "write", "C", "https://github.com/login/device", ["QQQ"], 60, True, True)))')
assert_contains "$L" "so decal can save to me/prof" "write wording"
assert_not_contains "$L" "On this computer                         On your phone" "stacked at 60 wide"
assert_contains "$L" "(opened in your browser)" "browser note"
assert_contains "$L" "(copied to your clipboard)" "clipboard note"

# the pre-filled token page
assert_eq "$(python3 "$A" token-url --need read --days 90)" \
  "https://github.com/settings/personal-access-tokens/new?name=Decal&description=decal%3A+read+your+profile&expires_in=90&contents=read" "read token page"
assert_eq "$(python3 "$A" token-url --need write --days none)" \
  "https://github.com/settings/personal-access-tokens/new?name=Decal&description=decal%3A+save+your+profile&expires_in=none&contents=write&administration=write" "write token page, never expires"
python3 "$A" token-url --need read --days 400 >/dev/null 2>&1; assert_eq "$?" "2" "expiry over 366 days refused"

# the apps: from the environment ("CLIENT_ID:slug"), else built in (none yet: no sign-in offered)
assert_eq "$(DECAL_GITHUB_APP_READ=Iv1.abc:decal python3 "$A" install-url --need read)" "https://github.com/apps/decal/installations/new" "install page"
assert_eq "$(DECAL_GITHUB_APP_WRITE=Iv1.w:decal-write py 'print(auth.app("write"))')" "('Iv1.w', 'decal-write')" "write app from the environment"
assert_eq "$(DECAL_GITHUB_APP_READ=junk py 'print(auth.app("read"))')" "None" "a malformed setting: no app"
t_done
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/test_auth.sh`
Expected: FAIL lines (e.g. `ModuleNotFoundError: No module named 'auth'`), ending `N failed` with N > 0.

- [ ] **Step 4: Write `lib/auth.py` (pure helpers + the two link commands)**

```python
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_auth.sh`
Expected: `test_auth.sh: 20 assertions, 0 failed`

- [ ] **Step 6: Record the write token page's extra permission in the spec**

In `docs/superpowers/specs/2026-10-04-github-sign-in-design.md`, replace
`` `contents=write`), says which repo to pick`` with
`` `contents=write&administration=write`, since a first stamp creates the repo), says which repo to pick``.

- [ ] **Step 7: Lint and commit**

```bash
shellcheck tests/test_auth.sh
git add lib/qrcodegen.py lib/auth.py tests/test_auth.sh docs/superpowers/specs/2026-10-04-github-sign-in-design.md
git commit -m "auth: QR code (vendored qrcodegen), sign-in screen layout and the pre-filled token page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Checking a key, and a fake GitHub that can sign in

**Files:**
- Modify: `tests/fixtures/fake_github_api.py`
- Modify: `lib/auth.py`
- Modify: `tests/test_auth.sh`

**Interfaces:**
- Consumes: `lib/auth.py` from Task 1 (`WEB`, `API`, `main()` argument parser).
- Produces (in `lib/auth.py`):
  - Exit codes `OK = 0, BAD_KEY = 10, CANT_SEE = 11, READ_ONLY = 12, OFFLINE = 13`.
  - `WHY: dict[int, str]` — plain-words reasons, with `{repo}` to format.
  - `class Offline(Exception)`.
  - `api_get(path: str, token: str) -> tuple[int, dict]` (raises `Offline`).
  - `check(repo: str, need: str, token: str, may_create: bool = False) -> int`.
  - CLI: `auth.py check REPO --need read|write [--may-create]` (key from `GITHUB_TOKEN`, exits with the code).
- Produces (fake server, for Tasks 3–4) — files in its `STATE_DIR`:
  - `seed`: repos (`owner/name` per line) that exist from the start.
  - `hidden`: `owner/name N` per line — that repo answers 404 for its next N lookups (an app not installed yet). `N` = `forever` never shows it.
  - `readonly`: if present, `permissions.push` is false.
  - `device_script`: one word per line, consumed by each poll: `pending`, `slow`, `expired`, `denied`, `ok` (empty/missing: `ok`).
  - `device_fail`: if present, `/login/device/code` answers HTTP 500.
  - `device_log`: appended `code client_id=…` / `poll client_id=…` per request.
  - Device endpoints: `POST /login/device/code`, `POST /login/oauth/access_token` (form-encoded, no auth), user code `WDJB-MJHT`, interval 0, `verification_uri` = `<server>/login/device`. Approval issues the server's token.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_auth.sh`, before `t_done`:

```bash
# a fake GitHub (localhost): checking a key
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"; echo me/prof > "$G/seed"
fake_up() {  # (re)start the fake GitHub: it reads seed/hidden when it starts
  if [[ -n ${GHPID:-} ]]; then kill "$GHPID" 2>/dev/null; wait "$GHPID" 2>/dev/null; fi
  rm -f "$G/port"; python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
  for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
  export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
}
fake_up
chk() { GITHUB_TOKEN=$1 python3 "$A" check "${@:2}" >/dev/null 2>&1; echo $?; }
assert_eq "$(chk s3cret me/prof --need read)" "0" "check: a good key reads"
assert_eq "$(chk s3cret me/prof --need write)" "0" "check: ...and writes"
assert_eq "$(chk wrong me/prof --need read)" "10" "check: a rejected key"
assert_eq "$(chk s3cret me/nope --need read)" "11" "check: a repo the key can't see"
assert_eq "$(chk s3cret me/nope --need write --may-create)" "0" "check: a repo to be created is fine"
assert_eq "$(chk s3cret decal-tester --need write --may-create)" "0" "check: no owner yet (stamp): the key is checked"
: > "$G/readonly"; assert_eq "$(chk s3cret me/prof --need write)" "12" "check: a read-only key when writing"; rm "$G/readonly"
assert_eq "$(GITHUB_TOKEN=s3cret DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$A" check me/prof --need read >/dev/null 2>&1; echo $?)" "13" "check: GitHub unreachable"
```

Leave the server running (Task 3 adds more tests below it); add `kill "$GHPID" 2>/dev/null` on the line before `t_done`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_auth.sh`
Expected: FAIL on every `check:` assertion (argparse rejects `check`: exit code 2).

- [ ] **Step 3: Extend the fake server**

In `tests/fixtures/fake_github_api.py`:

1. Update the docstring's first paragraph to:

```python
"""A tiny stand-in for GitHub's REST API and device sign-in (what lib/github.py and lib/auth.py call), for tests:
python3 fake_github_api.py STATE_DIR. Serves on 127.0.0.1 (port written to STATE_DIR/port). Accepts one token
(STATE_DIR/token). Repos live in memory; each ref update writes STATE_DIR/<owner>_<repo>.json with the commit's files
(path -> text) and count. Optional STATE_DIR files: seed (repos that exist: owner/name per line), hidden (owner/name N:
404 for the next N lookups, N=forever never), readonly (no push permission), device_script (one of pending, slow,
expired, denied, ok per poll), device_fail (the code request fails). Device requests are logged to device_log."""
import base64, hashlib, json, os, sys, urllib.parse
```

2. After `repos, blobs, trees, commits = {}, {}, {}, {}`, add:

```python
hidden = {}   # owner/name -> lookups still answered 404 (None: forever)


def state(name):
    p = os.path.join(STATE, name)
    return open(p).read().splitlines() if os.path.exists(p) else None


for line in state("seed") or []:
    if line.strip():
        c = sha({"seed": line.strip()})
        repos[line.strip()] = {"private": True, "default_branch": "main", "head": c, "commits": 1}
for line in state("hidden") or []:
    if line.strip():
        name, n = line.split()
        hidden[name] = None if n == "forever" else int(n)


def next_poll():
    lines = state("device_script") or []
    word = lines[0].strip() if lines else "ok"
    with open(os.path.join(STATE, "device_script"), "w") as f:
        f.write("\n".join(lines[1:]))
    return word
```

3. In `handle_any`, replace the block from `if self.headers.get("Authorization") != …` through `body = json.loads(…)` with:

```python
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        if self.path.startswith("/login/"):
            form = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode()).items()}
            return self.device(form)
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            return self.reply(401, {"message": "Bad credentials"})
        body = json.loads(raw) if raw else None
```

4. In the `if p[0] == "repos" and len(p) >= 3:` branch, replace

```python
            r = repos.get(full)
            if r is None:
                return self.reply(404, {"message": "Not Found"})
```
with
```python
            r = repos.get(full)
            if full in hidden:
                left = hidden[full]
                if left is None or left > 0:
                    if left is not None:
                        hidden[full] = left - 1
                    return self.reply(404, {"message": "Not Found"})
            if r is None:
                return self.reply(404, {"message": "Not Found"})
```
and replace
```python
            if not rest:
                return self.reply(200, {"full_name": full, "default_branch": r["default_branch"]})
```
with
```python
            if not rest:
                push = not os.path.exists(os.path.join(STATE, "readonly"))
                return self.reply(200, {"full_name": full, "default_branch": r["default_branch"],
                                        "permissions": {"pull": True, "push": push}})
```

5. Add this method to class `H` (after `handle_any`):

```python
    def device(self, form):
        cid = form.get("client_id", "")
        kind = "code" if self.path.startswith("/login/device/code") else "poll"
        with open(os.path.join(STATE, "device_log"), "a") as f:
            f.write(f"{kind} client_id={cid}\n")
        if kind == "code":
            if os.path.exists(os.path.join(STATE, "device_fail")):
                return self.reply(500, {"message": "Server Error"})
            host = f"http://127.0.0.1:{self.server.server_address[1]}"
            return self.reply(200, {"device_code": "dev123", "user_code": "WDJB-MJHT", "interval": 0,
                                    "verification_uri": host + "/login/device", "expires_in": 900})
        word = next_poll()
        if word == "ok":
            return self.reply(200, {"access_token": TOKEN, "token_type": "bearer"})
        err = {"pending": "authorization_pending", "slow": "slow_down", "expired": "expired_token",
               "denied": "access_denied"}[word]
        return self.reply(200, {"error": err, "interval": 0})
```

- [ ] **Step 4: Add `check` to `lib/auth.py`**

1. Change the import line to:

```python
import argparse, json, os, sys, urllib.error, urllib.parse, urllib.request
```

2. After `DAYS = …`, add:

```python
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
```

3. Replace `main()` with:

```python
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_auth.sh && bash tests/test_stamp.sh`
Expected: `test_auth.sh: 28 assertions, 0 failed` and `test_stamp.sh: … 0 failed` (the fake server's existing behaviour is unchanged).

- [ ] **Step 6: Commit**

```bash
git add lib/auth.py tests/fixtures/fake_github_api.py tests/test_auth.sh
git commit -m "auth: check a key against a repo (bad key / can't see it / read-only / offline); fake GitHub signs in too

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Asking for a key: sign in, wait for the app, or paste a token

**Files:**
- Modify: `lib/auth.py`
- Modify: `tests/test_auth.sh`

**Interfaces:**
- Consumes: `app`, `token_url`, `install_url`, `qr_lines`, `layout`, `DAYS` (Task 1); `check`, `WHY`, `OK`, `CANT_SEE`, `OFFLINE`, `Offline` (Task 2); fake server files (Task 2).
- Produces:
  - `class Tty` with `say(*lines)`, `line(prompt, hidden=False) -> str | None` (None at end of input), `key(timeout) -> str` (`""` when nothing pressed; with a keystroke file it only takes Esc or `t`, leaving other typing for the next prompt), `width() -> int`. Reads `DECAL_TTY_IN`, writes `DECAL_TTY_OUT` (default `/dev/tty` for both).
  - `get(tty: Tty, repo: str, need: str, may_create: bool) -> str | None`.
  - CLI: `auth.py get REPO --need read|write [--may-create]` — prints the key; exit 1 when cancelled; exit 130 on Ctrl+C.
  - Environment: `DECAL_AUTH_RECHECK` (seconds between install checks, default 5), `DECAL_AUTH_WAIT` (seconds before giving up on an install, default 600).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_auth.sh`, before the `kill "$GHPID"` line:

```bash
# asking: a terminal stand-in (a file of keystrokes in, a file out), the fake server's two apps
export DECAL_GITHUB_APP_READ=Iv-read:decal DECAL_GITHUB_APP_WRITE=Iv-write:decal-write DECAL_AUTH_RECHECK=0 COLUMNS=100
ask() {  # ask KEYS ARGS... : run auth.py get with KEYS as the typing; key on stdout, screen in $T_TMP/screen
  printf "$1" > "$T_TMP/keys"; : > "$G/device_log"
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" python3 "$A" get "${@:2}"
}
touch "$T_TMP/before"
printf 'pending\nslow\nok\n' > "$G/device_script"
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "sign in: the key, after pending and slow_down"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "1) Sign in with GitHub" "the choice offers signing in"
assert_contains "$S" "2. Enter WDJB-MJHT" "the code"
assert_contains "$S" "On your phone" "the phone column"
assert_contains "$S" "Signed in." "says it worked"
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-read" "reading uses the Decal app"
assert_eq "$(grep -c '^poll' "$G/device_log")" "3" "polled until approved"
assert_eq "$(find "$HOME" -type f -newer "$T_TMP/before" | wc -l)" "0" "nothing saved under HOME"
printf 'ok\n' > "$G/device_script"
ask '1\n' me/prof --need write >/dev/null
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-write" "writing uses the Decal Write app"

# the app isn't installed on the repo yet: the install link, then it carries on by itself (no new code)
printf 'ok\n' > "$G/device_script"; echo "me/prof 3" > "$G/hidden"; fake_up
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "not installed yet: the key once it is"
assert_contains "$(cat "$T_TMP/screen")" "Decal can't see me/prof yet: install it on that repo" "says what to do"
assert_contains "$(cat "$T_TMP/screen")" "$DECAL_GITHUB/apps/decal/installations/new" "with the install link"
assert_eq "$(grep -c '^code' "$G/device_log")" "1" "one code only"
# never visible (misspelled?): gives up on its own
echo "me/prof forever" > "$G/hidden"; fake_up
printf 'ok\nok\n' > "$G/device_script"
out=$(DECAL_AUTH_WAIT=0 ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "never visible: no key"
assert_contains "$(cat "$T_TMP/screen")" "still can't see me/prof: check the name" "says the name may be wrong"
rm "$G/hidden"; fake_up

# the code expires: a new one; denied: back to the choice; Esc: back to the choice
printf 'expired\nok\n' > "$G/device_script"
assert_eq "$(ask '1\n' me/prof --need read)" "s3cret" "expired: signed in with a new code"
assert_contains "$(cat "$T_TMP/screen")" "The code expired" "says so"; assert_eq "$(grep -c '^code' "$G/device_log")" "2" "two codes"
printf 'denied\n' > "$G/device_script"
out=$(ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "denied, then cancel: no key"
assert_contains "$(cat "$T_TMP/screen")" "Sign-in was denied on GitHub." "says it was denied"
assert_eq "$(grep -c 'Sign in with GitHub' "$T_TMP/screen")" "2" "back to the choice after denying"
printf 'pending\n' > "$G/device_script"
out=$(ask '1\n\x1b3\n' me/prof --need read); assert_eq "$?" "1" "Esc while waiting, then cancel"
: > "$G/device_fail"
out=$(ask '1\n3\n' me/prof --need read); assert_eq "$?" "1" "the code request fails: no key"
assert_contains "$(cat "$T_TMP/screen")" "GitHub didn't start a sign-in" "plain words, no traceback"
assert_not_contains "$(cat "$T_TMP/screen")" "Traceback" "no traceback on screen"
rm "$G/device_fail"

# make a token myself: expiry, the page, a wrong paste, then a good one (spaces trimmed); t while waiting gets here too
assert_eq "$(ask '2\n\nwrong\n  s3cret  \n' me/prof --need read)" "s3cret" "a pasted token, after a wrong one"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "90 days   (default)" "expiry choice"
assert_contains "$S" "expires_in=90&contents=read" "the pre-filled page, 90 days"
assert_contains "$S" 'choose "Only select repositories" and pick prof' "which repo to pick"
assert_contains "$S" "GitHub didn't accept that key" "the wrong paste explained"
assert_contains "$(ask '2\n4\ns3cret\n' me/prof --need write --may-create; cat "$T_TMP/screen")" "expires_in=none&contents=write&administration=write" "never expires; writing"
assert_contains "$(cat "$T_TMP/screen")" 'choose "All repositories"' "a repo decal may create: all repositories"
printf 'pending\n' > "$G/device_script"
assert_eq "$(ask '1\nt\ns3cret\n' me/prof --need read)" "s3cret" "t while waiting: paste a token instead"
assert_eq "$(DECAL_GITHUB_APP_READ= ask '1\n\ns3cret\n' me/prof --need read)" "s3cret" "no app configured: 1 is make a token"
assert_not_contains "$(cat "$T_TMP/screen")" "Sign in with GitHub" "...and signing in isn't offered"

# no terminal: fails with how to fix it; Ctrl+C: exits 130, no traceback
out=$(DECAL_TTY_IN=/nonexistent python3 "$A" get me/prof --need read 2>&1); assert_eq "$?" "1" "no terminal: fails"
assert_contains "$out" "set GITHUB_TOKEN or log in with gh auth login" "...and says how to fix it"
mkfifo "$T_TMP/fifo"; ( sleep 30 > "$T_TMP/fifo" ) & HOLD=$!
DECAL_TTY_IN="$T_TMP/fifo" DECAL_TTY_OUT="$T_TMP/screen" python3 "$A" get me/prof --need read > /dev/null 2> "$T_TMP/err" & P=$!
sleep 1; kill -INT "$P"; wait "$P"; assert_eq "$?" "130" "Ctrl+C: exit 130"
assert_not_contains "$(cat "$T_TMP/err")" "Traceback" "Ctrl+C: no traceback"; kill "$HOLD" 2>/dev/null
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_auth.sh`
Expected: FAIL on the new assertions (`get` is not a valid choice yet).

- [ ] **Step 3: Implement asking in `lib/auth.py`**

1. Change the import line to:

```python
import argparse, json, os, select, shutil, subprocess, sys, termios, time, tty as ttymod, urllib.error, urllib.parse, urllib.request
```

2. Add after `check()`:

```python
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
        old = termios.tcgetattr(self.i)
        try:
            ttymod.setcbreak(self.i)
            r, _, _ = select.select([self.i], [], [], timeout)
            return self.i.read(1).decode(errors="replace") if r else ""
        finally:
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
        r = wait_for_token(tty, cid, d)
        if r == "expired":
            tty.say("", "The code expired: here's a new one.")
            continue
        if r == "paste":
            return "paste"
        if r in ("cancel", "denied"):
            return None
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
```

3. Update `main()`: add `"get"` to the `cmd` choices, and add this branch before the final `else:` (which handles `check`):

```python
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
```

   The final `else:` stays the `check` branch.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_auth.sh`
Expected: `test_auth.sh: … 0 failed`

- [ ] **Step 5: Try it on a real terminal against the fake server**

```bash
cd /var/home/denis/Work/decal; G=$(mktemp -d); echo s3cret > $G/token; echo me/prof > $G/seed; printf 'pending\npending\npending\nok\n' > $G/device_script
python3 tests/fixtures/fake_github_api.py $G & sleep 1
DECAL_GITHUB=http://127.0.0.1:$(cat $G/port) DECAL_GITHUB_API=http://127.0.0.1:$(cat $G/port) DECAL_GITHUB_APP_READ=Iv-read:decal python3 lib/auth.py get me/prof --need read; kill %1
```
Expected: the two-column screen with a QR code a phone camera recognises as `http://127.0.0.1:…/login/device`, then `s3cret`. Press Esc on a second run: back to the choice, terminal still echoes typing afterwards.

- [ ] **Step 6: Commit**

```bash
git add lib/auth.py tests/test_auth.sh
git commit -m "auth: ask for a key: sign in with a code or QR, wait for the app to be installed, or paste a token you made

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: decal uses it (applying a private profile, stamp --github)

**Files:**
- Modify: `decal` (around lines 290–366: `do_stamp`'s token block, `gh_token`, `gh_ask`, `gh_tarball`)
- Modify: `tests/test_install.sh`
- Modify: `tests/test_stamp.sh`

**Interfaces:**
- Consumes: `auth.py get REPO --need read|write [--may-create]`, `auth.py install-url --need write` (Tasks 1–3); fake server device endpoints (Task 2).
- Produces (in `decal`): `gh_auth REPO read|write [--may-create]` — exports `GITHUB_TOKEN` for the rest of the run; non-zero when there's no terminal or the person cancels. `gh_ask` is removed.

- [ ] **Step 1: Write the failing tests**

In `tests/test_install.sh`, add `stub gh 'exit 1'; unset DISPLAY WAYLAND_DISPLAY` on the line after `t_setup`. Then append before `t_done`:

```bash
# no key: decal asks, signs in (the fake GitHub's Decal app), and uses that key for this run only
G="$T_TMP/ghapi"; mkdir -p "$G"; echo s3cret > "$G/token"; echo me/prof > "$G/seed"; echo ok > "$G/device_script"
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
FAKE="http://127.0.0.1:$(cat "$G/port")"
serve "$FAKE/repos/me/prof/tarball" "$T_TMP/gh.tar.gz"; echo "Bearer s3cret" > "$WEB/$(key "$FAKE/repos/me/prof/tarball").token"   # curl stub
printf '1\n' > "$T_TMP/keys"; : > "$LS_TEST_LOG"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_GITHUB="$FAKE" DECAL_GITHUB_API="$FAKE" DECAL_GITHUB_APP_READ=Iv-read:decal \
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$REPO/decal" apply github:me/prof 2>&1)
assert_eq "$?" "0" "private profile, no key: signed in and applied"
assert_contains "$(cat "$T_TMP/screen")" "2. Enter WDJB-MJHT" "the sign-in screen was shown"
assert_contains "$(cat "$G/device_log")" "client_id=Iv-read" "with the read app"
assert_eq "$(grep -rl s3cret "$HOME" 2>/dev/null | wc -l)" "0" "the key isn't saved anywhere under HOME"
kill "$GHPID" 2>/dev/null
```

`gh_tarball` downloads with `curl` (stubbed in this file: it serves any URL registered with `serve`), and `auth.py` talks to the same fake over HTTP, so both point at `$FAKE`.

In `tests/test_stamp.sh`, add `stub gh 'exit 1'; unset DISPLAY WAYLAND_DISPLAY` on the line after `t_setup`, and append before `kill "$GHPID" 2>/dev/null` (the existing fake-server block):

```bash
# no key: stamp -gh signs in with Decal Write (a repo that doesn't exist yet is fine), the key used for this run only
echo ok > "$G/device_script"; : > "$G/device_log"; printf '1\n' > "$T_TMP/keys"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_GITHUB="$DECAL_GITHUB_API" DECAL_GITHUB_APP_WRITE=Iv-write:decal-write \
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$S" stamp -gh tester/signed-in 2>&1)
assert_eq "$?" "0" "stamp -gh without a key: signed in"
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-write" "with the write app"
assert_file "$G/tester_signed-in.json" "the stamp is on GitHub"
assert_contains "$(cat "$T_TMP/screen")" "so decal can save to tester/signed-in" "says what the key is for"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_install.sh; bash tests/test_stamp.sh`
Expected: the new assertions FAIL (decal still prompts with `gh_ask`, which has no terminal under the test, so it dies with "not found or not allowed" / "no GitHub token").

- [ ] **Step 3: Replace `gh_ask` with `gh_auth` in `decal`**

Replace the comment + `gh_token` + `gh_ask` lines (the block starting `# gh_tarball OWNER/REPO REF OUT : a GitHub repo as a .tar.gz without git.` through the end of `gh_ask`) with:

```bash
# gh_tarball OWNER/REPO REF OUT : a GitHub repo as a .tar.gz without git. Private repos need a key: GITHUB_TOKEN,
# GH_TOKEN or a `gh auth login`; without one, in a terminal, it asks (sign in with GitHub, or a token you make)
gh_token() { local t=${GITHUB_TOKEN:-${GH_TOKEN:-}}; if [[ -z $t ]] && have gh; then t=$(gh auth token 2>/dev/null || true); fi; printf '%s' "$t"; }
# gh_auth REPO read|write [--may-create] : ask on the terminal for a key (lib/auth.py: sign in with a code or QR,
# or paste a token); exported as GITHUB_TOKEN for the rest of this run, never saved. No terminal or cancelled: fails
gh_auth() {
  if [[ -z ${DECAL_TTY_IN:-} ]]; then { : < /dev/tty; } 2>/dev/null || return 1; fi
  local t; t=$(python3 "$LS_REPO/lib/auth.py" get "$1" --need "$2" "${@:3}") || return 1
  [[ -n $t ]] || return 1
  export GITHUB_TOKEN=$t
}
```

In `gh_tarball`, replace

```bash
      if tok=$(gh_ask "$1 needs a GitHub token (private repo?): a fine-grained token with read access to its contents"); then continue; fi
```
with
```bash
      if gh_auth "$1" read; then tok=$GITHUB_TOKEN; continue; fi
```

- [ ] **Step 4: Use it in `do_stamp`**

Replace

```bash
    tok=$(gh_token)
    if [[ -z $tok ]]; then tok=$(gh_ask "a GitHub token to save your stamp (it needs to create a repo and write to it)") || die "no GitHub token: set GITHUB_TOKEN or log in with gh auth login"; fi
```
with
```bash
    tok=$(gh_token)
    if [[ -z $tok ]]; then
      gh_auth "$repo" write --may-create || die "no GitHub key: sign in when asked, set GITHUB_TOKEN, or log in with gh auth login"
      tok=$GITHUB_TOKEN; signed=1
    fi
```

Add `signed=0` to the `local` line at the top of `do_stamp` (`local dest="" gh=0 repo="" public=0 signed=0 me m frag st rc from only=()`).

Replace the push line's failure

```bash
    || die "could not save the stamp to GitHub (it is saved at $dest)"
```
with
```bash
    || { if (( signed )); then local u; u=$(python3 "$LS_REPO/lib/auth.py" install-url --need write 2>/dev/null) && info "Decal Write needs access to $repo: $u"; fi
         die "could not save the stamp to GitHub (it is saved at $dest)"; }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_install.sh && bash tests/test_stamp.sh && bash tests/test_auth.sh`
Expected: all three `… 0 failed`. The existing "private repo without a token (no terminal to ask in): fails" assertion in `test_install.sh` still passes (no `DECAL_TTY_IN`, no `/dev/tty` under `setsid`).

- [ ] **Step 6: Full suite, lint, commit**

```bash
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # expect no output
shellcheck decal tests/test_install.sh tests/test_stamp.sh
git add decal tests/test_install.sh tests/test_stamp.sh
git commit -m "decal signs in to GitHub when it needs a key (applying a private profile, stamp --github); nothing saved

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The real apps, the README, and an end-to-end check

**Files:**
- Modify: `README.md` (In depth section)
- Modify: `lib/auth.py` (`APPS`)

**Interfaces:**
- Consumes: everything above.
- Produces: working sign-in against real GitHub for everyone running the release.

- [ ] **Step 1: Write the README section**

Add under the README's "In depth" heading (after the existing profile-sources material):

```markdown
### Signing in to GitHub

A private profile needs a GitHub key. decal uses `GITHUB_TOKEN`, `GH_TOKEN` or your `gh` login if you have one;
otherwise it asks:

- **Sign in with GitHub:** open the link (or scan the QR code with your phone), enter the code, click Authorize.
  The first time, GitHub asks you to install the app on your profile repo; pick just that repo.
- **Make a token myself:** decal opens GitHub's new-token page filled in (read-only, or read and write for
  `stamp --github`); choose how long it lasts, pick your profile repo, generate, paste.

decal never saves a key it got by signing in. Two GitHub Apps do the signing in:

| App | Can | Its keys |
|---|---|---|
| Decal | read the contents of the repos you install it on | last until you revoke them |
| Decal Write | read and write contents, create repos | expire after 8 hours |

To revoke: GitHub → Settings → Applications → Authorized GitHub Apps → Decal → Revoke (this stops every key it
gave out, on every machine and stick). To take its access away from a repo: Installed GitHub Apps → Decal → Configure.

#### Registering the apps (maintainers and forks)

Done once, by hand, at GitHub → Settings → Developer settings → GitHub Apps → New GitHub App. For each app:

- Name: `Decal` / `Decal Write`; Homepage URL: the decal repo.
- Identifying and authorizing users: no callback URL; **Enable Device Flow** on; "Request user authorization
  during installation" off. **Expire user authorization tokens:** off for Decal, on for Decal Write.
- Webhook: Active off.
- Repository permissions: Decal: Contents read-only. Decal Write: Contents read and write, Administration read and
  write. No account or organisation permissions.
- Where can this GitHub App be installed: Any account.

Then put each app's Client ID and URL slug in `APPS` in `lib/auth.py` (`"Iv23…:decal"`), or, for a fork without
editing code, set `DECAL_GITHUB_APP_READ` / `DECAL_GITHUB_APP_WRITE` to the same `CLIENT_ID:slug`.
```

- [ ] **Step 2: Register the two apps (the maintainer, by hand)**

Follow the checklist in Step 1 on github.com as dmacpherson. Note each app's **Client ID** (General page) and **slug** (the last part of `https://github.com/apps/<slug>`). Expected slugs: `decal` and `decal-write`.

- [ ] **Step 3: Put the real IDs in `lib/auth.py`**

```python
APPS = {"read": "<Decal Client ID>:decal", "write": "<Decal Write Client ID>:decal-write"}
```
(with the two Client IDs from Step 2 in place of the angle-bracket text).

- [ ] **Step 4: Run the suite (tests set their own apps, so the real IDs change nothing there)**

Run: `bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'`
Expected: no output.

- [ ] **Step 5: End-to-end on real GitHub (the maintainer)**

```bash
python3 lib/auth.py get dmacpherson/decal-profile --need read | wc -c
```
Expected: the sign-in screen; scan the QR code with a phone, enter the code, approve, install Decal on `decal-profile` only when asked; decal says "Signed in." and prints a key length (> 30). Then:

```bash
env -u GITHUB_TOKEN -u GH_TOKEN GH_CONFIG_DIR="$(mktemp -d)" ./decal apply github:dmacpherson/decal-profile --dry-run
```
(`GH_CONFIG_DIR` pointed at an empty folder hides your `gh` login for this one command.) Expected: one sign-in, then the dry-run plan, with no second sign-in during the run.

- [ ] **Step 6: Commit**

```bash
git add README.md lib/auth.py
git commit -m "Signing in to GitHub: the Decal and Decal Write apps, how to revoke them, how to register your own

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
