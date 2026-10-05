# Profile Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One place to see, pick and make decal profiles (GitHub, this machine, USB sticks, recently used), with any link or `owner/name` accepted as a source and a warning before applying a profile that isn't yours.

**Architecture:** Two new Python helpers: `lib/source.py` (recognise a source, download over https, unpack archives safely, the recently-used list, "is it yours") and `lib/profiles.py` (find profiles, starter profiles, READMEs). The `decal` script gains `profiles` and `new`, and its `set_profile` is split into `stage_profile` (get a source into a validated folder) and activation. The menu (`lib/ui.py`) gets a browser screen built on `decal profiles --json`, used by apply and stamp.

**Tech Stack:** bash, Python 3.11+ standard library (urllib, tarfile, zipfile, tomllib, concurrent.futures), curses, decal's bash test harness and the fake GitHub server from part 1.

**Spec:** `docs/superpowers/specs/2026-10-04-profile-browser-design.md` (roadmap: `docs/superpowers/specs/2026-10-04-usb-feature-roadmap.md`)

## Global Constraints

- `decal` lowercase for commands/files; **Decal** for user-facing names (apps, folders, the launcher).
- Every menu action runs `decal` commands you could type; the menu never has logic the command line lacks.
- Never overwrite: `decal new` refuses an existing repo, file or stick profile ("use decal stamp to update it").
- Keys: never written to disk, never on a command line; the recently-used list never holds keys.
- Downloads: https only (redirects to http refused); `DECAL_ALLOW_HTTP_LOCAL=1` allows `http://127.0.0.1` for tests only.
- Archives: `.tar.gz`, `.tgz`, `.zip`; unpacked by Python; nothing outside the target, no links/devices, 200 MB at most.
- Local wins: an existing path beats `owner/name`, and decal says which it used.
- "Yours": a local path, a stick, a source in the recently-used list, or a GitHub repo owned by the key's account.
- GitHub discovery: topic `decal-profile` ∪ names `decal-*` ∪ every owned repo when there are ≤ 100; each confirmed by a top-level `profile.toml`; 8 checks at a time; owned repos only.
- No test touches the network or the real `/run/media`; tests stub `gh`, unset `DISPLAY`/`WAYLAND_DISPLAY`, and set `DECAL_MEDIA`.
- Python standard library only. Bash shellcheck-clean (`shellcheck decal`).
- Commit messages: one descriptive line in the repo's style, blank line, then
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

- A GitHub-style tarball (`pax_global_header`, one top folder `owner-repo-sha/`) and a stamp tarball (`./profile.toml`) must both unpack and be found. (Task 2: both shapes tested.)
- A friend's private repo the key can't see, applied with `--yes` from the installer, must still fail cleanly with part 1's message, not hang on a prompt. (Task 3: no-terminal + `--yes` path.)
- `decal profiles` on a machine whose `~` has stray `decal-*.tar.gz.old` files or a broken archive must list the rest, not crash. (Task 4: broken archive and `.old` file in the fixture.)
- The menu must stay usable while GitHub is slow: keys work during "Looking for your profiles…", Esc leaves at once. (Task 6: the github listing is a background thread; drive_ui test presses keys before it finishes.)
- Existing menu flows (`tests/test_ui.sh`) keep their keystrokes: apply's first Enter picks the active profile. (Task 6: the cursor starts on the active row.)

---

### Task 1: Recognising sources (`source.py resolve`)

**Files:**
- Create: `lib/source.py`
- Create: `tests/test_source.sh`

**Interfaces:**
- Produces:
  - `class Bad(Exception)` — a plain-words reason.
  - `allowed(url: str) -> bool` — https, or http to 127.0.0.1 with `DECAL_ALLOW_HTTP_LOCAL=1`.
  - `resolve(text: str) -> tuple[str, str, str]` — `(kind, source, note)`; kind ∈ `dir`, `archive`, `github`, `url`, `git`; source canonical (absolute path, `github:owner/repo[@ref]`, the link); note "" or the local-wins message. Raises `Bad`.
  - CLI `source.py resolve INPUT` → prints `KIND<TAB>SOURCE<TAB>NOTE`; exit 1 with the reason on stderr.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_source.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
SRC="$REPO/lib/source.py"
r() { python3 "$SRC" resolve "$1" 2>&1; }

# GitHub, every way people write it
assert_eq "$(r github:me/prof)" $'github\tgithub:me/prof\t' "github:owner/repo as is"
assert_eq "$(r github:me/prof@laptop)" $'github\tgithub:me/prof@laptop\t' "...with a ref"
assert_eq "$(r me/prof)" $'github\tgithub:me/prof\t' "owner/repo"
assert_eq "$(r me/prof@v2)" $'github\tgithub:me/prof@v2\t' "owner/repo@ref"
assert_eq "$(r https://github.com/me/prof)" $'github\tgithub:me/prof\t' "a GitHub link"
assert_eq "$(r https://github.com/me/prof.git)" $'github\tgithub:me/prof\t' "...ending .git"
assert_eq "$(r https://github.com/me/prof/)" $'github\tgithub:me/prof\t' "...with a trailing slash"
assert_eq "$(r github.com/me/prof)" $'github\tgithub:me/prof\t' "...without https://"
assert_eq "$(r https://www.github.com/me/prof)" $'github\tgithub:me/prof\t' "...with www."
assert_eq "$(r https://github.com/me/prof/tree/feature/x)" $'github\tgithub:me/prof@feature/x\t' "a branch link (slashes kept)"
assert_eq "$(r https://github.com/me/prof/commit/abc123)" $'github\tgithub:me/prof@abc123\t' "a commit link"
assert_eq "$(r http://github.com/me/prof)" $'github\tgithub:me/prof\t' "an http GitHub link: GitHub's https download anyway"
# other links
assert_eq "$(r https://example.com/p.tar.gz)" $'url\thttps://example.com/p.tar.gz\t' "an archive link"
assert_eq "$(r https://example.com/page)" $'url\thttps://example.com/page\t' "any other https link: fetch decides"
assert_eq "$(r https://gitlab.com/me/prof.git)" $'git\thttps://gitlab.com/me/prof.git\t' "a .git link: git"
assert_eq "$(r git+https://example.com/p)" $'git\tgit+https://example.com/p\t' "git+ link"
assert_eq "$(r git@example.com:me/p.git)" $'git\tgit@example.com:me/p.git\t' "ssh shorthand"
out=$(r http://example.com/p.tar.gz); assert_contains "$out" "use an https:// link" "plain http refused"
assert_eq "$(DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" resolve http://127.0.0.1:8/p.zip)" $'url\thttp://127.0.0.1:8/p.zip\t' "tests may use http to 127.0.0.1"
# local paths win, and say so when it could have been GitHub
mkdir -p "$T_TMP/w/me/prof"; : > "$T_TMP/w/me/prof/profile.toml"; : > "$T_TMP/w/p.tar.gz"; : > "$T_TMP/w/notes.txt"
cd "$T_TMP/w" || exit 1
assert_eq "$(r me/prof)" $'dir\t'"$T_TMP/w/me/prof"$'\tusing the folder me/prof; for GitHub, write github:me/prof' "a folder named like owner/repo: local wins, with a note"
assert_eq "$(r ./p.tar.gz)" $'archive\t'"$T_TMP/w/p.tar.gz"$'\t' "a local archive"
assert_eq "$(HOME=$T_TMP/w r '~/p.tar.gz')" $'archive\t'"$T_TMP/w/p.tar.gz"$'\t' "~ expanded"
out=$(r notes.txt); assert_contains "$out" "not a folder or a .tar.gz/.tgz/.zip" "another kind of file: refused"
out=$(r nothing-here); assert_contains "$out" "not found here, and not a link or owner/name" "nothing matches: says so"
cd "$REPO" || exit 1
t_done
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_source.sh`
Expected: FAIL on every assertion (`lib/source.py` doesn't exist), `N failed` with N > 0.

- [ ] **Step 3: Write `lib/source.py`**

```python
#!/usr/bin/env python3
"""source.py: what a profile source is, and getting it safely.

  source.py resolve INPUT         KIND<TAB>SOURCE<TAB>NOTE (kind: dir, archive, github, url, git)

https only; DECAL_ALLOW_HTTP_LOCAL=1 also allows http://127.0.0.1 (tests)."""
import argparse, os, re, sys, urllib.parse

NAME = r"[A-Za-z0-9_.-]+"
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
        if re.fullmatch(rf"{NAME}/{NAME}(@\S+)?", t):
            note = f"using the {'folder' if kind == 'dir' else 'file'} {t}; for GitHub, write github:{t}"
        return kind, p, note
    if re.fullmatch(rf"github:{NAME}/{NAME}(@\S+)?", t):
        return "github", t, ""
    if re.fullmatch(rf"{NAME}/{NAME}(@\S+)?", t):
        return "github", "github:" + t, ""
    m = re.fullmatch(rf"(?:https?://)?(?:www\.)?github\.com/({NAME})/({NAME})(?:/(?:tree|commit)/(.+?))?/?", t)
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_source.sh`
Expected: `test_source.sh: 24 assertions, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/source.py tests/test_source.sh
git commit -m "source: recognise any profile source (GitHub links and owner/name, archive links, git, local paths first)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Getting it safely (`unpack`, `fetch`, `remember`, `yours`)

**Files:**
- Modify: `lib/source.py`
- Modify: `tests/test_source.sh`

**Interfaces:**
- Consumes: `Bad`, `allowed`, `resolve` (Task 1).
- Produces:
  - `unpack(archive: str, dest: str) -> None` — `.tar.gz`/`.tgz`/`.zip` by content (gzip or zip magic); raises `Bad`.
  - `download(url: str, path: str) -> None` — https only, redirects to http refused, 200 MB cap; raises `Bad`.
  - `fetch(url: str, dest: str) -> bool` — download; True and unpacked into dest when it's an archive, False otherwise.
  - `remember(source: str) -> None` — prepends to `$DECAL_USER_STATE/recent` (default `~/.local/state/decal/recent`), `source<TAB>ISO time`, 10 kept, no duplicates.
  - `recent() -> list[tuple[str, str]]`.
  - `yours(source: str, login: str = "") -> bool`.
  - CLI: `unpack ARCHIVE DIR`, `fetch URL DIR` (prints `archive`; exit 3 when not an archive), `remember SOURCE`, `yours SOURCE [--login L]` (exit 0 yours, 1 not).
  - Env: `DECAL_UNPACK_LIMIT` (bytes; tests make it small).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_source.sh`, before `t_done`:

```bash
# unpacking: the two real shapes (GitHub's archive with a pax header and one top folder; a stamp with ./profile.toml)
U="$T_TMP/u"; mkdir -p "$U/gh/me-prof-abc123" "$U/st"
printf '[p]\n' > "$U/gh/me-prof-abc123/profile.toml"; printf '[p]\n' > "$U/st/profile.toml"; echo hi > "$U/st/wall.txt"
tar --format=pax -czf "$U/gh.tar.gz" -C "$U/gh" me-prof-abc123; tar -czf "$U/st.tgz" -C "$U/st" .
(cd "$U/st" && python3 -c 'import zipfile; z=zipfile.ZipFile("../st.zip","w"); z.write("profile.toml"); z.write("wall.txt"); z.close()')
python3 "$SRC" unpack "$U/gh.tar.gz" "$U/o1"; assert_file "$U/o1/me-prof-abc123/profile.toml" "GitHub-style tarball unpacked"
python3 "$SRC" unpack "$U/st.tgz" "$U/o2"; assert_eq "$(cat "$U/o2/wall.txt")" "hi" "stamp tarball (./ names) unpacked"
python3 "$SRC" unpack "$U/st.zip" "$U/o3"; assert_file "$U/o3/profile.toml" "zip unpacked"
# unsafe archives: refused, nothing written outside the target
mk_tar='import io,tarfile,sys
t=tarfile.open(sys.argv[1],"w:gz")
def f(n,data=b"x"):
  i=tarfile.TarInfo(n); i.size=len(data); t.addfile(i,io.BytesIO(data))'
python3 -c "$mk_tar"'
f("../escaped.txt"); t.close()' "$U/dotdot.tgz"; out=$(python3 "$SRC" unpack "$U/dotdot.tgz" "$U/t1" 2>&1); rc=$?
assert_eq "$rc" "1" "../ member: refused"; assert_contains "$out" "points outside the archive" "...says why"; assert_nofile "$U/escaped.txt" "...nothing written outside"
python3 -c "$mk_tar"'
f("/tmp/abs-decal-test.txt"); t.close()' "$U/abs.tgz"; out=$(python3 "$SRC" unpack "$U/abs.tgz" "$U/t2" 2>&1)
assert_contains "$out" "an absolute path" "absolute path: refused"; assert_nofile /tmp/abs-decal-test.txt "...not written"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("link"); i.type=tarfile.SYMTYPE; i.linkname="/etc/passwd"; t.addfile(i); t.close()' "$U/sym.tgz"
out=$(python3 "$SRC" unpack "$U/sym.tgz" "$U/t3" 2>&1); assert_contains "$out" "links and special files aren't allowed" "symlink: refused"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("hard"); i.type=tarfile.LNKTYPE; i.linkname="x"; t.addfile(i); t.close()' "$U/hard.tgz"
out=$(python3 "$SRC" unpack "$U/hard.tgz" "$U/t4" 2>&1); assert_contains "$out" "links and special files aren't allowed" "hardlink: refused"
python3 -c "$mk_tar"'
i=tarfile.TarInfo("dev"); i.type=tarfile.CHRTYPE; t.addfile(i); t.close()' "$U/dev.tgz"
out=$(python3 "$SRC" unpack "$U/dev.tgz" "$U/t5" 2>&1); assert_contains "$out" "links and special files aren't allowed" "device: refused"
python3 -c 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("../../zip-escaped.txt","x"); z.close()' "$U/slip.zip"
out=$(python3 "$SRC" unpack "$U/slip.zip" "$U/t6" 2>&1); assert_contains "$out" "points outside the archive" "zip slip: refused"
head -c 3000 /dev/zero > "$U/big"; tar -czf "$U/big.tgz" -C "$U" big
out=$(DECAL_UNPACK_LIMIT=1000 python3 "$SRC" unpack "$U/big.tgz" "$U/t7" 2>&1); assert_contains "$out" "more than" "over the size limit: refused"
echo "not an archive" > "$U/plain.tgz"; out=$(python3 "$SRC" unpack "$U/plain.tgz" "$U/t8" 2>&1)
assert_contains "$out" "not a .tar.gz or .zip archive" "not an archive: says so"

# fetch over a local web server (tests only: http to 127.0.0.1)
mkdir -p "$U/www"; cp "$U/st.zip" "$U/www/p.zip"; echo "<html>hi</html>" > "$U/www/page"
(cd "$U/www" && exec python3 -m http.server 0 --bind 127.0.0.1 > "$U/http.log" 2>&1) & WPID=$!
for _ in $(seq 50); do PORT=$(grep -o 'port [0-9]*' "$U/http.log" | grep -o '[0-9]*'); [[ -n $PORT ]] && break; sleep 0.1; done
W="http://127.0.0.1:$PORT"
assert_eq "$(DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" fetch "$W/p.zip" "$U/f1")" "archive" "fetch: an archive link is unpacked"
assert_file "$U/f1/profile.toml" "...into the folder"
DECAL_ALLOW_HTTP_LOCAL=1 python3 "$SRC" fetch "$W/page" "$U/f2" >/dev/null 2>&1; assert_eq "$?" "3" "fetch: not an archive: exit 3 (try git)"
out=$(python3 "$SRC" fetch "$W/p.zip" "$U/f3" 2>&1); assert_contains "$out" "use an https:// link" "fetch: plain http refused"
kill "$WPID" 2>/dev/null

# recently used, and whose it is
python3 "$SRC" remember github:friend/setup; python3 "$SRC" remember "$T_TMP/w/p.tar.gz"; python3 "$SRC" remember github:friend/setup
assert_eq "$(cut -f1 "$DECAL_USER_STATE/recent" | tr '\n' ' ')" "github:friend/setup $T_TMP/w/p.tar.gz " "recent: newest first, no duplicates"
for i in $(seq 12); do python3 "$SRC" remember "github:x/r$i"; done
assert_eq "$(wc -l < "$DECAL_USER_STATE/recent")" "10" "recent: 10 kept"
y() { python3 "$SRC" yours "$@"; echo $?; }
assert_eq "$(y "$T_TMP/w/p.tar.gz")" "0" "yours: a local path"
assert_eq "$(y github:x/r12)" "0" "yours: recently used"
assert_eq "$(y github:me/prof --login me)" "0" "yours: your GitHub account's"
assert_eq "$(y github:me/prof --login Me)" "0" "...any letter case"
assert_eq "$(y github:stranger/prof --login me)" "1" "not yours: someone else's repo"
assert_eq "$(y https://example.com/p.zip)" "1" "not yours: a link"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_source.sh`
Expected: the new assertions FAIL (`unpack`, `fetch`, `remember`, `yours` aren't commands yet).

- [ ] **Step 3: Implement in `lib/source.py`**

1. Update the docstring's command list:

```python
"""source.py: what a profile source is, and getting it safely.

  source.py resolve INPUT         KIND<TAB>SOURCE<TAB>NOTE (kind: dir, archive, github, url, git)
  source.py unpack ARCHIVE DIR    a .tar.gz/.tgz/.zip, safely: nothing outside DIR, no links, 200 MB at most
  source.py fetch URL DIR         download; an archive is unpacked into DIR (prints "archive"); else exit 3
  source.py remember SOURCE       put SOURCE first in the recently-used list (10 kept; never a key)
  source.py yours SOURCE [--login L]  exit 0 when SOURCE is yours: local, recently used, or L's on GitHub

https only; DECAL_ALLOW_HTTP_LOCAL=1 also allows http://127.0.0.1 (tests)."""
import argparse, datetime, os, re, shutil, stat, sys, tarfile, tempfile, urllib.error, urllib.parse, urllib.request, zipfile
```

2. After `ARCHIVES = …` add:

```python
LIMIT = int(os.environ.get("DECAL_UNPACK_LIMIT", str(200 * 1024 * 1024)))
STATE = os.environ.get("DECAL_USER_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "decal")
RECENT = os.path.join(STATE, "recent")
```

3. After `resolve()` add:

```python
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
    if source.startswith("/") or any(s == source for s, _ in recent()):
        return True
    m = re.fullmatch(rf"github:({NAME})/{NAME}(@\S+)?", source)
    return bool(m and login and m.group(1).lower() == login.lower())
```

4. Replace `main()` with:

```python
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["resolve", "unpack", "fetch", "remember", "yours"])
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
        else:
            sys.exit(0 if yours(a.args[0], a.login) else 1)
    except Bad as e:
        sys.exit(f"error: {e}")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_source.sh`
Expected: `test_source.sh: … 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/source.py tests/test_source.sh
git commit -m "source: unpack archives safely (no escaping paths, links or devices; 200 MB cap), download over https, recently used, whose it is

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: decal uses it: staging, any source, recently used, the "not yours" warning

**Files:**
- Modify: `decal` (`set_profile` → `stage_profile` + activation; `apply`/`use` cases; global `--yes`; usage text)
- Modify: `install.sh` (pass `--yes` with a profile to apply)
- Modify: `tests/test_install.sh`, `tests/test_apply.sh`

**Interfaces:**
- Consumes: `source.py resolve|unpack|fetch|remember|yours` (Tasks 1–2); `gh_tarball`, `gh_token`, `gh_auth` (part 1).
- Produces (in `decal`):
  - `stage_profile SOURCE` — sets globals `STAGE_KIND` (dir/archive/github/url/git), `STAGE_DIR` (a validated folder with `profile.toml`), `STAGE_SRC` (canonical source). Not run in a subshell, so a sign-in during it lasts the whole run.
  - `set_profile SOURCE` — `stage_profile`, then make it active (unchanged rules: dry-run only stages; a folder becomes a symlink; a repeat download of the same github/url source replaces without a backup; anything else keeps a dated backup). Writes `.decal-source` for archive/github/url copies.
  - `trust SOURCE` — returns when yours or confirmed; dies otherwise. `--yes` / `DECAL_YES=1` skips the question.
  - `decal use` and `decal apply` record the canonical source with `source.py remember` (not in dry-run).
  - Global flag `--yes` / `-y` → `DECAL_YES=1`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_install.sh`, before `t_done` (after part 1's sign-in block):

```bash
# any source: a GitHub link and owner/name are the same github: source; the source is remembered
: > "$LS_TEST_LOG"
GITHUB_TOKEN=s3cret "$REPO/decal" --yes apply https://github.com/me/prof >/dev/null 2>&1; assert_eq "$?" "0" "a GitHub link applies"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "...as github:me/prof"
assert_eq "$(head -1 "$DECAL_USER_STATE/recent" | cut -f1)" "github:me/prof" "...and is remembered as recently used"
# not yours: a stranger's repo without a terminal and without --yes stops, before anything changes
mkdir -p "$T_TMP/gh2/stranger-prof-1"; printf '[eee-conf]\nword = "stranger"\n' > "$T_TMP/gh2/stranger-prof-1/profile.toml"
tar -czf "$T_TMP/gh2.tar.gz" -C "$T_TMP/gh2" stranger-prof-1; serve https://api.github.com/repos/stranger/prof/tarball "$T_TMP/gh2.tar.gz"
: > "$LS_TEST_LOG"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply stranger/prof 2>&1 < /dev/null); assert_eq "$?" "1" "someone else's profile, no terminal: stops"
assert_contains "$out" "this profile is from stranger/prof, not you" "...says whose it is"
assert_contains "$out" "decal --yes apply github:stranger/prof" "...and how to apply it anyway"
assert_eq "$(cat "$LS_TEST_LOG")" "" "...nothing added"
assert_contains "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "...and the active profile is unchanged"
# with a terminal: p previews (nothing changes), then y applies
printf 'p\ny\n' > "$T_TMP/keys"; : > "$LS_TEST_LOG"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$REPO/decal" apply stranger/prof 2>&1)
assert_eq "$?" "0" "someone else's profile, previewed then confirmed: applied"
assert_eq "$(grep -o 'p preview' "$T_TMP/screen" | wc -l)" "2" "...asked, previewed, asked again"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add stranger" "...then added (the fixture logs during the preview too)"
# now it's recently used: no question next time
: > "$LS_TEST_LOG"
setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply stranger/prof >/dev/null 2>&1 < /dev/null
assert_eq "$?" "0" "recently used: no question"
# install.sh passes --yes with the profile it was given
grep -q 'cmd=(apply --yes)' "$REPO/install.sh"; assert_eq "$?" "0" "the installer applies with --yes"
```

In `tests/test_apply.sh`, append before `t_done`:

```bash
# a .zip profile, and a link to one is refused over plain http
mkdir -p "$T_TMP/z"; printf '[p2]\nword = "zip"\n' > "$T_TMP/z/profile.toml"
(cd "$T_TMP/z" && python3 -c 'import zipfile; z=zipfile.ZipFile("../p.zip","w"); z.write("profile.toml"); z.close()')
"$S" apply "$T_TMP/p.zip" >/dev/null 2>&1; assert_eq "$?" "0" "a .zip profile applies"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "$T_TMP/p.zip" "...its source recorded"
out=$("$S" apply http://example.com/p.zip 2>&1); assert_eq "$?" "1" "http link: refused"; assert_contains "$out" "use an https:// link" "...says why"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_install.sh; bash tests/test_apply.sh`
Expected: the new assertions FAIL (a GitHub link is cloned with git, no `recent`, no `--yes`, no warning, `.zip` unknown).

- [ ] **Step 3: Global `--yes` and usage**

In `decal`'s option loop add a case before `-h|--help)`:

```bash
    -y|--yes) export DECAL_YES=1 ;;
```

In `usage()`, change the `apply` lines to:

```
  apply  <source> [module...]  make it the active profile, then add everything in it (or just those modules).
                             source: a folder, a .tar.gz/.tgz/.zip, owner/repo or any GitHub link, an https://
                             link to an archive, a git URL. Someone else's profile: decal asks first (--yes skips)
```

- [ ] **Step 4: Replace `set_profile` with `stage_profile` + `set_profile`**

Replace the whole `set_profile()` function (and its two comment lines above it) with:

```bash
# stage_profile SOURCE : SOURCE as a validated folder holding profile.toml, in STAGE_DIR (a folder source as is;
# anything else downloaded/unpacked into a temp folder); STAGE_KIND and STAGE_SRC (canonical) set too. Not run in
# a subshell: a sign-in it needs lasts the whole run.
stage_profile() {
  local r note tmp rc
  r=$(python3 "$LS_REPO/lib/source.py" resolve "$1") || exit 1   # the reason is already on stderr
  IFS=$'\t' read -r STAGE_KIND STAGE_SRC note <<<"$r"
  if [[ -n $note ]]; then info "$note"; fi
  case $STAGE_KIND in
    dir)
      [[ -f $STAGE_SRC/profile.toml ]] || die "$STAGE_SRC has no profile.toml"
      STAGE_DIR=$(cd "$STAGE_SRC" && pwd -P); STAGE_SRC=$STAGE_DIR ;;
    archive)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      python3 "$LS_REPO/lib/source.py" unpack "$STAGE_SRC" "$tmp/x" || die "could not unpack $STAGE_SRC"
      STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC contains no profile.toml" ;;
    github)
      [[ $STAGE_SRC =~ ^github:([^@]+)(@(.+))?$ ]] || die "not a GitHub source: $STAGE_SRC"
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      gh_tarball "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$tmp/p.tar.gz"
      python3 "$LS_REPO/lib/source.py" unpack "$tmp/p.tar.gz" "$tmp/x" || die "could not unpack $STAGE_SRC"
      STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC has no profile.toml" ;;
    url)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX"); rc=0
      python3 "$LS_REPO/lib/source.py" fetch "$STAGE_SRC" "$tmp/x" >/dev/null || rc=$?
      if (( rc == 0 )); then
        STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC: the archive has no profile.toml"
      elif (( rc == 3 )) && have git && git clone -q "$STAGE_SRC" "$tmp/p" 2>/dev/null && [[ -f $tmp/p/profile.toml ]]; then
        STAGE_KIND=git; STAGE_DIR=$tmp/p
      else
        (( rc != 3 )) || die "$STAGE_SRC isn't a decal profile (not an archive with a profile.toml, nor a git repo with one)"
        exit 1   # source.py said why
      fi ;;
    git)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      git clone -q "${STAGE_SRC#git+}" "$tmp/p" || die "git clone failed: ${STAGE_SRC#git+}"
      [[ -f $tmp/p/profile.toml ]] || die "${STAGE_SRC#git+} has no profile.toml"
      STAGE_DIR=$tmp/p ;;
  esac
  python3 "$LS_REPO/lib/profile.py" check --profile "$STAGE_DIR" --modules "$MODULES_DIR" \
    || die "$STAGE_SRC: the profile is invalid (the active profile was not changed)"
}
# set_profile SOURCE : make SOURCE the active profile at $PROFILE_HOME (dry-run: only staged). A replaced real
# folder is kept as a dated backup, except a newer download of the same GitHub repo or link.
set_profile() {
  local t=$PROFILE_HOME
  stage_profile "$1"
  _aside() {  # move the active profile out of the way (a symlink is just dropped)
    local b
    if [[ -L $t ]]; then rm -f "$t"
    elif [[ -e $t ]]; then b="$t.old-$(date +%Y%m%d-%H%M%S)"; [[ ! -e $b ]] || b+="-$$"; mv "$t" "$b"; info "previous profile kept at $b"; fi
    mkdir -p "$(dirname "$t")"
  }
  if [[ ${LS_DRY_RUN:-0} == 1 ]]; then PROFILE_DIR=$STAGE_DIR; return 0; fi
  case $STAGE_KIND in
    dir)
      if [[ -e $t && $(readlink -f "$t") == "$STAGE_DIR" ]]; then PROFILE_DIR=$t; info "$STAGE_DIR is already the active profile"; return 0; fi
      _aside; ln -s "$STAGE_DIR" "$t" ;;
    git)
      if [[ -d $t/.git && ! -L $t && $(git -C "$t" remote get-url origin 2>/dev/null) == "${STAGE_SRC#git+}" ]]; then
        git -C "$t" pull -q --ff-only || die "git pull failed in $t"
      else _aside; mv "$STAGE_DIR" "$t"; fi ;;
    *)   # archive, github, url: an unpacked copy
      echo "$STAGE_SRC" > "$STAGE_DIR/.decal-source"
      if [[ $STAGE_KIND != archive && -d $t && ! -L $t && $(cat "$t/.decal-source" 2>/dev/null) == "$STAGE_SRC" ]]; then rm -rf "$t"; else _aside; fi
      mv "$STAGE_DIR" "$t" ;;
  esac
  PROFILE_DIR=$t
  info "active profile: $t -> $(readlink -f "$t")"
}
# trust SOURCE : a profile that isn't yours (lib/source.py yours): say whose it is, offer a preview, ask.
# --yes / DECAL_YES=1 skips the question; no terminal: stops with how to go on.
trust() {
  local src=$1 login="" tok a fd
  if [[ $src == github:* ]]; then tok=$(gh_token); if [[ -n $tok ]]; then login=$(GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" whoami 2>/dev/null || true); fi; fi
  if python3 "$LS_REPO/lib/source.py" yours "$src" --login "$login"; then return 0; fi
  warn "this profile is from ${src#github:}, not you: it can install software and change system settings"
  if [[ ${DECAL_YES:-} == 1 ]]; then return 0; fi
  if [[ -z ${DECAL_TTY_IN:-} ]] && ! { : < /dev/tty; } 2>/dev/null; then die "not applied: to apply it anyway, run decal --yes apply $src"; fi
  exec {fd}<"${DECAL_TTY_IN:-/dev/tty}"
  while :; do
    printf 'p preview what it would change · y apply it · n stop [p]: ' > "${DECAL_TTY_OUT:-/dev/tty}"
    IFS= read -r a <&"$fd" || a=n
    case ${a:-p} in
      p|P) DECAL_NO_UPDATE=1 DECAL_YES=1 DECAL_PROFILE=$STAGE_DIR "$LS_REPO/decal" --dry-run add all || true ;;
      y|Y) exec {fd}<&-; return 0 ;;
      *) die "not applied" ;;
    esac
  done
}
```

- [ ] **Step 5: Use them in `apply` and `use`**

Replace the start of the `apply)` case

```bash
  apply)
    [[ $# -ge 1 ]] || usage
    set_profile "$1"; export PROFILE_DIR; shift
```
with
```bash
  apply)
    [[ $# -ge 1 ]] || usage
    if [[ ${LS_DRY_RUN:-0} != 1 ]]; then stage_profile "$1"; trust "$STAGE_SRC"; fi
    set_profile "$1"; export PROFILE_DIR; shift
    if [[ ${LS_DRY_RUN:-0} != 1 ]]; then python3 "$LS_REPO/lib/source.py" remember "$STAGE_SRC" || true; fi
```

(`set_profile` stages again: cheap for folders and archives; for GitHub the key from the first staging is already exported, so no second sign-in. A second download is the cost of keeping `set_profile` one function; acceptable.)

Replace the `use)` case's body with:

```bash
  use)
    [[ $# -eq 1 ]] || usage
    set_profile "$1"
    if [[ ${LS_DRY_RUN:-0} != 1 ]]; then python3 "$LS_REPO/lib/source.py" remember "$STAGE_SRC" || true; fi
    info "active profile: $PROFILE_DIR (nothing applied yet: decal add all, or the menu)" ;;
```

- [ ] **Step 6: The installer passes `--yes`**

In `install.sh`, change `local cmd=(apply); if [[ $1 == stamp ]]; then cmd=(stamp); shift; fi` to:

```bash
  local cmd=(apply --yes); if [[ $1 == stamp ]]; then cmd=(stamp); shift; fi   # --yes: the person typed the source
```

and update the header comment's `PROFILE is anything` sentence to: `PROFILE is anything decal apply takes: a folder, a .tar.gz/.zip, owner/repo or a GitHub link, an https link to an archive, a git URL (private GitHub repos: GITHUB_TOKEN, gh auth login, or decal signs you in).`

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash tests/test_install.sh; bash tests/test_apply.sh; bash tests/test_source.sh`
Expected: all three `… 0 failed`. If an existing `test_apply.sh` assertion about backups fails, compare against the rule in `set_profile` (archives always keep a backup, as before) before changing anything.

- [ ] **Step 8: Full suite, lint, commit**

```bash
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # expect no output
shellcheck decal
git add decal install.sh tests/test_install.sh tests/test_apply.sh
git commit -m "apply takes any source (GitHub links, owner/repo, .zip, archive links), remembers it, and asks before applying someone else's profile (--yes skips)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Finding profiles (`decal profiles`)

**Files:**
- Modify: `tests/fixtures/fake_github_api.py`
- Modify: `lib/github.py` (topic on push; `exists`)
- Modify: `lib/auth.py` (`get -`: sign in without a repo)
- Create: `lib/profiles.py`
- Modify: `decal` (`profiles` command, usage)
- Create: `tests/test_profiles.sh`

**Interfaces:**
- Consumes: `auth.api_get`, `auth.Offline`, `auth.install_url` (part 1); `source.recent()` (Task 2); `gh_token`, `gh_auth` (part 1).
- Produces:
  - `lib/profiles.py`:
    - `count(text: str) -> int | None` (module sections; None when not valid TOML)
    - `toml_in_archive(path) -> str | None`
    - `find_github(token) -> tuple[list[dict], list[str]]` (raises `auth.Offline`)
    - `find_local() -> list[dict]`, `sticks() -> list[str]`, `find_sticks() -> list[dict]`, `find_recent() -> list[dict]`
    - `active() -> str`
    - `listing(only: str) -> dict` = `{"entries": [...], "notes": [...], "signed_in": bool | None, "active": str}`
    - `ago(iso: str) -> str`, `describe(entry) -> str`
    - CLI: `list [--json] [--only local|github]`, `sticks`.
    - Env: `DECAL_MEDIA` (default `/run/media/$USER`), `DECAL_PROFILE_HOME`/`DECAL_PROFILE`, `DECAL_MODULES_DIR`.
  - Entry dict keys: `kind`, `source`, `name`, `private` (github), `updated`, `modules`, `active`, `label` (stick).
  - `lib/github.py`: `push` adds the `decal-profile` topic; CLI `exists REPO` (exit 0 yes, 1 no, 2 error).
  - `lib/auth.py`: repo `-` means "your profiles": no repo check after signing in.
  - `decal profiles [--json] [--only local|github] [--sign-in]`.
- Fake server (`STATE_DIR` files): `seed` lines may add words `public` and `topic`; `many N` adds N plain repos for `tester`; `contents/OWNER/REPO/PATH` files are served by `GET /repos/O/R/contents/PATH`; pushed files are served too; `PUT /repos/O/R/topics` stores topics; `GET /user/repos` (paged by `per_page`/`page`) lists `tester`'s repos; `GET /search/repositories?q=topic:decal-profile+user:tester` lists those with the topic.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_profiles.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
P="$REPO/lib/profiles.py"
export DECAL_MEDIA="$T_TMP/media" DECAL_PROFILE_HOME="$T_TMP/active"; mkdir -p "$DECAL_MEDIA"
M="$T_TMP/mods"; for n in apps wallpaper; do mkdir -p "$M/$n"; echo '{"keys": {}}' > "$M/$n/schema.json"; : > "$M/$n/module.sh"; done
export DECAL_MODULES_DIR="$M"
TOML=$'[apps]\n[wallpaper]\n[notamodule]\n'

assert_eq "$(python3 -c "import sys; sys.path.insert(0,'$REPO/lib'); import profiles; print(profiles.count('''$TOML'''))")" "2" "count: module sections only"
assert_eq "$(python3 -c "import sys; sys.path.insert(0,'$REPO/lib'); import profiles; print(profiles.ago('2000-01-01T00:00:00+00:00'))")" "26 years ago" "ago: years"

# this machine: stamp files and folders; strays left out
mkdir -p "$T_TMP/s"; printf '%s' "$TOML" > "$T_TMP/s/profile.toml"
tar -czf "$HOME/decal-me.tar.gz" -C "$T_TMP/s" .; cp "$HOME/decal-me.tar.gz" "$HOME/decal-me.tar.gz.old"
echo junk > "$HOME/decal-broken.tar.gz"; mkdir -p "$HOME/decal-work"; cp "$T_TMP/s/profile.toml" "$HOME/decal-work/"; : > "$HOME/decal-work/.decal-stamp"
mkdir -p "$HOME/decal-notastamp"; cp "$T_TMP/s/profile.toml" "$HOME/decal-notastamp/"
# a stick, and recently used
mkdir -p "$DECAL_MEDIA/Ventoy/.Decal/profile"; cp "$T_TMP/s/profile.toml" "$DECAL_MEDIA/Ventoy/.Decal/profile/"
python3 "$REPO/lib/source.py" remember github:friend/setup
J=$(python3 "$P" list --json --only local)
q() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($2)" "$J"; }
assert_eq "$(q x "sorted(e['name'] for e in d['entries'] if e['kind']=='file')")" "['~/decal-me.tar.gz', '~/decal-work']" "local: the stamp file and stamp folder; .old, broken and non-stamp folders left out"
assert_eq "$(q x "[e['modules'] for e in d['entries'] if e['kind']=='file']")" "[2, 2]" "local: module counts"
assert_eq "$(q x "[(e['name'], e['label']) for e in d['entries'] if e['kind']=='stick']")" "[('Ventoy: .Decal', 'Ventoy')]" "stick: found"
assert_eq "$(q x "[e['source'] for e in d['entries'] if e['kind']=='recent']")" "['github:friend/setup']" "recent: listed"
assert_eq "$(q x "d['signed_in']")" "None" "--only local: GitHub not looked at"
# the active profile is marked
mkdir -p "$DECAL_PROFILE_HOME"; echo "$HOME/decal-me.tar.gz" > "$DECAL_PROFILE_HOME/.decal-source"
J=$(python3 "$P" list --json --only local)
assert_eq "$(q x "[e['name'] for e in d['entries'] if e['active']]")" "['~/decal-me.tar.gz']" "active: marked"
# no key: a sign-in row instead of GitHub
out=$(python3 "$P" list); assert_contains "$out" "Sign in to see your GitHub profiles" "no key: says how to see GitHub profiles"
assert_contains "$out" "On this machine" "text: grouped"; assert_contains "$out" "← active" "text: the active mark"

# GitHub: topic, names, full scan; each confirmed by profile.toml
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"
printf 'tester/decal-profile\ntester/oddname topic\ntester/handmade public\ntester/decal-notes\nother/decal-x\n' > "$G/seed"
for r in decal-profile oddname handmade; do mkdir -p "$G/contents/tester/$r"; printf '%s' "$TOML" > "$G/contents/tester/$r/profile.toml"; done
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
J=$(GITHUB_TOKEN=s3cret python3 "$P" list --json --only github)
assert_eq "$(q x "sorted(e['name'] for e in d['entries'])")" "['tester/decal-profile', 'tester/handmade', 'tester/oddname']" "github: profiles found three ways; decal-notes (no profile.toml) and others' repos left out"
assert_eq "$(q x "[e['private'] for e in d['entries'] if e['name']=='tester/handmade']")" "[False]" "github: public/private"
echo 120 > "$G/many"; kill "$GHPID"; wait "$GHPID" 2>/dev/null; rm -f "$G/port"
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
J=$(GITHUB_TOKEN=s3cret python3 "$P" list --json --only github)
assert_eq "$(q x "sorted(e['name'] for e in d['entries'])")" "['tester/decal-profile', 'tester/oddname']" "over 100 repos: no full scan; topic and names still found"
J=$(GITHUB_TOKEN=s3cret DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$P" list --json)
assert_eq "$(q x "d['notes']")" "[\"couldn't reach GitHub\"]" "GitHub down: a note"
assert_eq "$(q x "len([e for e in d['entries'] if e['kind']=='file'])")" "2" "...and local profiles still listed"
# decal profiles: the key it finds (GITHUB_TOKEN here), never on a command line
out=$(GITHUB_TOKEN=s3cret "$REPO/decal" profiles 2>&1); assert_contains "$out" "tester/decal-profile" "decal profiles lists GitHub"
assert_contains "$out" "~/decal-work" "...and this machine"
# stamp tags the repo with the topic
J2=$(GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" push "$T_TMP/s" tester/fresh --message t 2>&1)
assert_contains "$(cat "$G/topics.log" 2>/dev/null)" "tester/fresh decal-profile" "push: the decal-profile topic set"
GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" exists tester/fresh; assert_eq "$?" "0" "exists: yes"
GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" exists tester/nope; assert_eq "$?" "1" "exists: no"
kill "$GHPID" 2>/dev/null
t_done
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_profiles.sh`
Expected: FAIL throughout (`lib/profiles.py` doesn't exist).

- [ ] **Step 3: Extend the fake server**

In `tests/fixtures/fake_github_api.py`:

1. Add to the docstring's file list: `seed lines may add "public" and "topic"; many (N plain repos for tester); contents/OWNER/REPO/PATH (served by the contents API); PUT topics are logged to topics.log`.

2. Change the seed loader to read the extra words:

```python
for line in state("seed") or []:
    words = line.split()
    if words:
        c = sha({"seed": words[0]})
        repos[words[0]] = {"private": "public" not in words, "default_branch": "main", "head": c, "commits": 1,
                           "topics": ["decal-profile"] if "topic" in words else [], "files": {}}
for i in range(int((state("many") or ["0"])[0])):
    repos[f"{USER}/filler-{i}"] = {"private": True, "default_branch": "main", "head": sha({"f": i}), "commits": 1,
                                   "topics": [], "files": {}}
```

3. In `handle_any`, parse the path once: replace `p = self.path.strip("/").split("/")` with

```python
        url = urllib.parse.urlparse(self.path)
        p = url.path.strip("/").split("/")
        qs = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
```

4. After the `if p == ["user"]:` branch add:

```python
        if p == ["user", "repos"] and method == "GET":
            mine = sorted(n for n in repos if n.startswith(USER + "/"))
            per, page = int(qs.get("per_page", 30)), int(qs.get("page", 1))
            return self.reply(200, [self.repo_json(n) for n in mine[(page - 1) * per:page * per]])
        if p == ["search", "repositories"]:
            items = [self.repo_json(n) for n in sorted(repos) if n.startswith(USER + "/") and "decal-profile" in repos[n]["topics"]]
            return self.reply(200, {"total_count": len(items), "items": items})
```

5. In the `repos` branch, after `if not rest:` (the repo JSON reply), add:

```python
            if rest[0] == "contents" and method == "GET":
                path = "/".join(rest[1:])
                text = r["files"].get(path)
                disk = os.path.join(STATE, "contents", p[1], p[2], path)
                if text is None and os.path.isfile(disk):
                    text = open(disk).read()
                if text is None:
                    return self.reply(404, {"message": "Not Found"})
                return self.reply(200, {"content": base64.b64encode(text.encode()).decode(), "encoding": "base64"})
            if rest == ["topics"] and method == "PUT":
                r["topics"] = body["names"]
                with open(os.path.join(STATE, "topics.log"), "a") as f:
                    f.write(f"{full} {' '.join(body['names'])}\n")
                return self.reply(200, {"names": body["names"]})
```

6. Make the plain repo reply use the shared JSON: replace the `if not rest:` reply's dict with `self.repo_json(full)` merged with permissions:

```python
            if not rest:
                push = not os.path.exists(os.path.join(STATE, "readonly"))
                return self.reply(200, dict(self.repo_json(full), permissions={"pull": True, "push": push}))
```

and add the method:

```python
    def repo_json(self, full):
        r = repos[full]
        return {"full_name": full, "name": full.split("/", 1)[1], "private": r["private"],
                "default_branch": r["default_branch"], "topics": r["topics"], "pushed_at": "2026-10-01T12:00:00Z"}
```

7. In repo creation (`POST /user/repos`) add `"topics": [], "files": {}` to the new repo dict, and in the ref-update branch keep the files in memory: after computing `files = {...}` add `r["files"] = files`.

8. Add `do_PUT(self): self.handle_any("PUT")`.

- [ ] **Step 4: `lib/github.py`: topic and `exists`**

In `push()`, after the final `need(call("PATCH", …), f"update {branch}")` line and before `print(repo)`, add:

```python
    topics = info.get("topics") or []
    if "decal-profile" not in topics:   # so decal profiles finds it, whatever its name
        code, _ = call("PUT", f"/repos/{repo}/topics", {"names": sorted(set(topics) | {"decal-profile"})})
        if code != 200:
            print("note: couldn't tag the repo with the decal-profile topic", file=sys.stderr)
```

In `main()`: add `"exists"` to `cmd` choices (and the docstring: `github.py exists REPO : exit 0 when it exists, 1 when not`), and the branch:

```python
        elif a.cmd == "exists":
            code, _ = call("GET", f"/repos/{a.folder}", ok=(200, 404))
            sys.exit(0 if code == 200 else 1 if code == 404 else 2)
```

(`a.folder` is the first positional argument; for `exists` it holds the repo.)

- [ ] **Step 5: `lib/auth.py`: signing in without a repo**

1. In `check()`, first line of the `try:` body after `code, me = api_get("/user", token)` and the 401 test, add:

```python
        if repo == "-":   # signing in to list your profiles: the key works, that's all
            return OK if code == 200 else BAD_KEY
```

2. Add a helper after `check()`:

```python
def shown(repo):
    return "your profiles" if repo == "-" else repo
```

3. Use `shown(repo)` in `layout` (`f"Sign in to GitHub so decal can {what} {shown(repo)}"`), in `get` (`f"decal needs a GitHub key to {…} {shown(repo)}:"`), and in `make_token`: when `repo == "-"`, the "where" line is `'choose "Only select repositories" and pick your profile repos'`.

4. In `sign_in`, right after `r = wait_for_token(...)` handling and before `with tty.keys(): return wait_for_access(...)`, add:

```python
        if repo == "-":
            tty.say("Signed in.")
            return r
```

5. Add to `tests/test_auth.sh` before its final `kill`: 

```bash
echo ok > "$G/device_script"
assert_eq "$(ask '1\n' - --need read)" "s3cret" "sign in without a repo (to list your profiles)"
assert_contains "$(cat "$T_TMP/screen")" "so decal can read your profiles" "...says what for"
```

- [ ] **Step 6: Write `lib/profiles.py`**

```python
#!/usr/bin/env python3
"""profiles.py: the profiles decal can see, and pieces for making new ones.

  profiles.py list [--json] [--only local|github]   GitHub (repos you own holding a profile.toml), this machine
                                                     (~/decal-* stamps), USB sticks (.Decal/profile), recently used
  profiles.py sticks                                 mounted drives (one per line)
  profiles.py empty DIR                              a starter profile: examples/profile, every section commented out
  profiles.py readme DIR NAME FROM                   DIR/README.md for a profile called NAME, made from FROM

GitHub uses the key in GITHUB_TOKEN (decal passes the one it found); none: a sign-in row instead. Never asks."""
import argparse, base64, concurrent.futures, datetime, glob, json, os, sys, tarfile, tomllib, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auth, source  # noqa: E402

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
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


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
            except OSError:
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
        except OSError:
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
    """(entries, notes) for the repos the key's account owns that hold a profile.toml. Raises auth.Offline."""
    code, me = auth.api_get("/user", token)
    if code != 200:
        return [], ["GitHub didn't accept the key"]
    login = me.get("login", "")
    repos, page = [], 1
    while True:
        code, batch = auth.api_get(f"/user/repos?affiliation=owner&per_page=100&page={page}", token)
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
    code, found = auth.api_get(f"/search/repositories?q=topic:decal-profile+user:{login}&per_page=100", token)
    if code == 200:
        for r in found.get("items", []):
            by.setdefault(r["full_name"], r)
            cand.add(r["full_name"])
    cand = {n for n in cand if n.split("/")[0].lower() == login.lower()}

    def check(full):
        try:
            code, f = auth.api_get(f"/repos/{full}/contents/profile.toml", token)
            n = count(base64.b64decode(f["content"]).decode()) if code == 200 and "content" in f else None
        except (auth.Offline, ValueError, KeyError):
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
        code, _ = auth.api_get("/user/installations", token)
        if code == 200:   # an app key: the app may not be on any profile repo yet
            notes.append(f"no profiles found: install Decal Profile on your profile repos: {auth.install_url('read')}")
        else:
            notes.append(f"no profiles found on GitHub for {login}")
    return entries, notes


def active():
    d = os.environ.get("DECAL_PROFILE") or PROFILE_HOME
    if os.path.islink(d) or os.environ.get("DECAL_PROFILE"):
        return os.path.realpath(d)
    try:
        return open(os.path.join(d, ".decal-source")).read().strip()
    except OSError:
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
            except auth.Offline:
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
    with open(os.path.join(dest, "README.md"), "w") as f:
        f.write(f"# {name}\n\nA [decal](https://github.com/dmacpherson/decal) profile, {how}.\n\n"
                "## Put it on a machine\n\n```bash\ncurl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- "
                f"{name}\n```\n\n(Use `owner/{name}` for a GitHub repo, or the path of a file.)\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "sticks", "empty", "readme"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--only", choices=["local", "github"], default="")
    a = ap.parse_args()
    if a.cmd == "list":
        d = listing(a.only)
        print(json.dumps(d) if a.json else text(d))
    elif a.cmd == "sticks":
        print("\n".join(sticks()))
    elif a.cmd == "empty":
        empty(a.args[0])
    else:
        readme(*a.args[:3])


if __name__ == "__main__":
    main()
```

- [ ] **Step 7: `decal profiles`**

Add to `usage()` after the `use` line:

```
  profiles [--json] [--sign-in]  the profiles decal can see: yours on GitHub, stamps on this machine, USB
                             sticks, recently used (--sign-in: sign in to GitHub first if there's no key)
```

Add a case before `stamp)`:

```bash
  profiles)
    signin=0; pargs=()
    for a in "$@"; do case $a in --sign-in) signin=1 ;; --json|--only=*) pargs+=("${a/--only=/--only }") ;; *) die "profiles: unknown option $a" ;; esac; done
    tok=$(gh_token)
    if [[ -z $tok ]] && (( signin )); then gh_auth - read || die "not signed in"; tok=$GITHUB_TOKEN; fi
    # shellcheck disable=SC2086  # "--only local" is two words on purpose
    GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/profiles.py" list ${pargs[*]} ;;
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bash tests/test_profiles.sh; bash tests/test_auth.sh; bash tests/test_stamp.sh`
Expected: all three `… 0 failed` (the fake server's existing behaviour for stamp is unchanged; stamp now also tags the topic).

- [ ] **Step 9: Full suite, lint, commit**

```bash
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # expect no output
shellcheck decal
git add lib/profiles.py lib/github.py lib/auth.py decal tests/test_profiles.sh tests/test_auth.sh tests/fixtures/fake_github_api.py
git commit -m "decal profiles: your profiles on GitHub (topic, decal-* names, small accounts scanned; each with a profile.toml), stamps here, USB sticks, recently used; stamp tags the topic

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Making a new profile (`decal new`)

**Files:**
- Modify: `decal` (`do_new`, `new` command, usage)
- Create: `tests/test_new.sh`

**Interfaces:**
- Consumes: `stage_profile`, `set_profile` (Task 3); `do_stamp` (existing); `gh_token`, `gh_auth` (part 1); `github.py whoami|exists|push`, `profiles.py sticks|empty|readme` (Task 4).
- Produces: `decal new NAME [--from this-machine|PROFILE|empty] [--to github|file|file:PATH|stick] [--public] [--use]`; prints `new profile: SOURCE` on success.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_new.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
export DECAL_MEDIA="$T_TMP/media" DECAL_PROFILE_HOME="$T_TMP/active"; mkdir -p "$DECAL_MEDIA"
M="$T_TMP/mods"; mkdir -p "$M/live"; echo '{"keys": {"word": {"type": "string", "default": "x"}}}' > "$M/live/schema.json"
printf 'module_stamp() { printf "[live]\\nword = \\"here\\"\\n"; }\n' > "$M/live/module.sh"
export DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora
N() { "$REPO/decal" new "$@" 2>&1; }
x() { rm -rf "$T_TMP/x"; mkdir -p "$T_TMP/x"; tar -xzf "$1" -C "$T_TMP/x"; }

# from this machine, to a file
out=$(N decal-a --to file); assert_eq "$?" "0" "this machine → file"; assert_contains "$out" "new profile: $HOME/decal-a.tar.gz" "...says where"
x "$HOME/decal-a.tar.gz"; assert_contains "$(cat "$T_TMP/x/profile.toml")" 'word = "here"' "...the stamp is in it"
assert_contains "$(cat "$T_TMP/x/README.md")" "# decal-a" "...a README naming it"
assert_nofile "$T_TMP/x/.decal-stamp" "...no stamp marker in a file"
out=$(N decal-a --to file); assert_eq "$?" "1" "never overwrites"; assert_contains "$out" "already exists: use decal stamp to update it" "...says what to do"
# empty, to a chosen path
out=$(N decal-b --from empty --to "file:$T_TMP/b.tgz"); assert_eq "$?" "0" "empty → file:PATH"
x "$T_TMP/b.tgz"; assert_eq "$(grep -cv '^\s*#\|^\s*$' "$T_TMP/x/profile.toml")" "0" "empty: every line a comment"
python3 "$REPO/lib/profile.py" check --profile "$T_TMP/x" --modules "$M"; assert_eq "$?" "0" "empty: a valid profile"
# a copy of another profile, to the stick
mkdir -p "$T_TMP/src"; printf '[live]\nword = "copied"\n' > "$T_TMP/src/profile.toml"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "1" "no stick plugged in: refused"; assert_contains "$out" "plug in a USB stick" "...says so"
mkdir -p "$DECAL_MEDIA/Ventoy"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "0" "copy → stick"
assert_contains "$(cat "$DECAL_MEDIA/Ventoy/.Decal/profile/profile.toml")" 'word = "copied"' "...copied"
assert_file "$DECAL_MEDIA/Ventoy/.Decal/profile/.decal-stamp" "...stamp can update it later"
assert_contains "$(cat "$DECAL_MEDIA/Ventoy/.Decal/profile/README.md")" "copied from $T_TMP/src" "...README says where it came from"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "1" "stick profile exists: refused"
# --use makes it active (nothing applied)
out=$(N decal-d --from "$T_TMP/src" --to file --use); assert_eq "$?" "0" "--use"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "$HOME/decal-d.tar.gz" "...the new one is active"

# to GitHub: signs in with the write app when there's no key; a repo that exists is refused
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"; echo tester/decal-taken > "$G/seed"; echo ok > "$G/device_script"
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_APP_WRITE=Iv-write:decal-write
printf '1\n' > "$T_TMP/keys"
out=$(DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" N decal-e --from empty); assert_eq "$?" "0" "empty → GitHub (signed in)"
assert_contains "$out" "new profile: github:tester/decal-e" "...says where"
assert_contains "$(cat "$G/device_log")" "client_id=Iv-write" "...with the write app"
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$G/tester_decal-e.json")" "True" "...private"
assert_contains "$(cat "$G/topics.log")" "tester/decal-e decal-profile" "...tagged as a profile"
out=$(GITHUB_TOKEN=s3cret N decal-taken --from empty); assert_eq "$?" "1" "an existing repo: refused"
assert_contains "$out" "github:tester/decal-taken already exists" "...says so"
GITHUB_TOKEN=s3cret N decal-f --from empty --public >/dev/null
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$G/tester_decal-f.json")" "False" "--public"
out=$(N 'bad name' --from empty --to file); assert_eq "$?" "1" "a name with a space: refused"
kill "$GHPID" 2>/dev/null
t_done
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_new.sh`
Expected: FAIL throughout (`new` is not a command: usage, exit 1).

- [ ] **Step 3: Implement `do_new` in `decal`**

Add after `do_stamp()`:

```bash
# do_new NAME [--from this-machine|PROFILE|empty] [--to github|file[:PATH]|stick] [--public] [--use] : a new profile.
# Never overwrites: an existing repo, file or stick profile stops it before any work.
do_new() {
  local name="" from=this-machine to=github public=0 use=0 dest="" repo="" tok="" src stage sticks n a
  while (( $# )); do
    case $1 in
      --from) from=${2:?--from needs this-machine, a profile, or empty}; shift ;;
      --to) to=${2:?--to needs github, file, file:PATH or stick}; shift ;;
      --public) public=1 ;;
      --use) use=1 ;;
      -*) die "new: unknown option $1" ;;
      *) [[ -z $name ]] || die "new: one name (got $name and $1)"; name=$1 ;;
    esac; shift
  done
  [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] || die "new: a name like decal-work (letters, digits, - _ .)"
  case $to in   # where, checked first
    github) ;;
    file) dest="$HOME/$name.tar.gz" ;;
    file:*) dest=${to#file:}; dest=${dest/#\~/$HOME} ;;
    stick)
      mapfile -t sticks < <(python3 "$LS_REPO/lib/profiles.py" sticks | sed '/^$/d')
      (( ${#sticks[@]} )) || die "no USB stick found: plug in a USB stick and try again"
      if (( ${#sticks[@]} == 1 )); then dest="${sticks[0]}/.Decal/profile"
      else
        { : < "${DECAL_TTY_IN:-/dev/tty}"; } 2>/dev/null || die "several USB sticks: unplug the others"
        n=0; for a in "${sticks[@]}"; do n=$((n + 1)); printf '  %s) %s\n' "$n" "$(basename "$a")" > "${DECAL_TTY_OUT:-/dev/tty}"; done
        printf 'Which stick? ' > "${DECAL_TTY_OUT:-/dev/tty}"; IFS= read -r a < "${DECAL_TTY_IN:-/dev/tty}"
        [[ $a =~ ^[0-9]+$ ]] && (( a >= 1 && a <= ${#sticks[@]} )) || die "no stick chosen"
        dest="${sticks[$((a - 1))]}/.Decal/profile"
      fi ;;
    *) die "new: --to github, file, file:PATH or stick" ;;
  esac
  if [[ -n $dest && -e $dest ]]; then die "$dest already exists: use decal stamp to update it"; fi
  if [[ $to == github ]]; then
    tok=$(gh_token)
    if [[ -z $tok ]]; then gh_auth "$name" write --may-create || die "no GitHub key: sign in when asked, set GITHUB_TOKEN, or log in with gh auth login"; tok=$GITHUB_TOKEN; fi
    repo="$(GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" whoami)/$name" || die "GitHub didn't accept the key"
    if GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" exists "$repo"; then die "github:$repo already exists: use decal stamp -gh $repo to update it"; fi
  fi
  stage="$LS_RUNTMP/new/$name"
  case $from in   # what goes in
    this-machine) do_stamp "$stage" ;;
    empty) python3 "$LS_REPO/lib/profiles.py" empty "$stage" ;;
    *) stage_profile "$from"; mkdir -p "$stage"; cp -a "$STAGE_DIR/." "$stage/"; rm -rf "$stage/.git" "$stage/.decal-source" ;;
  esac
  rm -f "$stage/.decal-stamp"
  python3 "$LS_REPO/lib/profiles.py" readme "$stage" "$name" "$( [[ $from == this-machine || $from == empty ]] && echo "$from" || echo "${STAGE_SRC:-$from}")"
  case $to in   # where it goes
    github)
      local pub=(); if (( public )); then pub=(--public); fi
      GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" push "$stage" "$repo" "${pub[@]}" --message "decal new: $name" >/dev/null \
        || die "could not create github:$repo"
      src="github:$repo" ;;
    stick) mkdir -p "$dest"; cp -a "$stage/." "$dest/"; : > "$dest/.decal-stamp"; src=$dest ;;
    *) mkdir -p "$(dirname "$dest")"; tar -czf "$dest" -C "$stage" .; src=$dest ;;
  esac
  info "new profile: $src"
  if (( use )); then set_profile "$src"; python3 "$LS_REPO/lib/source.py" remember "$STAGE_SRC" || true; fi
}
```

Add the command to the `case $cmd in` block (`new) do_new "$@" ;;` next to `stamp)`) and to `usage()`:

```
  new NAME [--from this-machine|PROFILE|empty] [--to github|file[:PATH]|stick] [--public] [--use]
                             a new profile: a stamp of this machine (default), a copy of PROFILE, or a starter
                             with everything commented out; on GitHub (default: a private repo), in a file
                             (~/NAME.tar.gz) or on the USB stick. Never overwrites. --use: make it active
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_new.sh`
Expected: `test_new.sh: … 0 failed`

- [ ] **Step 5: Full suite, lint, commit**

```bash
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # expect no output
shellcheck decal
git add decal tests/test_new.sh
git commit -m "decal new: a profile from this machine, a copy, or a commented-out starter, on GitHub, in a file or on the stick; never overwrites

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The browser in the menu

**Files:**
- Modify: `lib/ui.py`
- Modify: `tests/test_ui.sh`

**Interfaces:**
- Consumes: `decal profiles --json [--only local|github]` (Task 4), `decal new` (Task 5), `decal use` (Task 3), `source.py resolve|yours` (Tasks 1–2), `github.py whoami`, `auth.py get - --need read` (part 1 / Task 4).
- Produces (in `lib/ui.py`):
  - `browser_rows(data: dict, purpose: str, user: str) -> list[tuple[str, str, str, dict | None]]` — `(style, label, aside, value)`; style ∈ `head`, `row`, `note`; value None for headings and notes. Pure.
  - `UI.browse(title, purpose) -> dict | None` — purpose `apply` or `stamp`; returns the chosen row's value: an entry dict (with `source`, `kind`), `{"action": "new"}`, `{"action": "enter"}`, or None (Esc).
  - `UI.trusted(src) -> bool`, `UI.sign_in()`, `UI.do_new(start_from="")`.
  - Session key: `ENV["GITHUB_TOKEN"]` set after a sign-in, for the rest of the menu.

- [ ] **Step 1: Write the failing tests**

In `tests/test_ui.sh`, add after `t_setup`: `unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'; export DECAL_MEDIA="$T_TMP/media"; mkdir -p "$DECAL_MEDIA"`. Then append before `t_done`:

```bash
# the browser: groups, the active row, sign-in row, new and enter; pure layout
rows() { python3 -c "import sys,json; sys.path.insert(0, '$REPO/lib'); import ui
d = json.loads(sys.argv[1]); [print(s, '|', l, '|', a) for s, l, a, v in ui.browser_rows(d, sys.argv[2], 'me')]" "$1" "$2"; }
D1='{"entries": [{"kind": "file", "source": "/h/decal-me.tar.gz", "name": "~/decal-me.tar.gz", "updated": "2026-10-01T00:00:00+00:00", "modules": 3, "active": true},
 {"kind": "recent", "source": "github:friend/setup", "name": "friend/setup", "updated": "2026-10-01T00:00:00+00:00", "active": false}],
 "notes": [], "signed_in": false, "active": "/h/decal-me.tar.gz"}'
R=$(rows "$D1" apply)
assert_contains "$R" "head | On GitHub |" "browser: GitHub group"
assert_contains "$R" "row | Sign in to see your GitHub profiles |" "browser: no key → sign-in row"
assert_contains "$R" "row | ~/decal-me.tar.gz | file · " "browser: a local stamp"
assert_contains "$R" "← active" "browser: the active mark"
assert_contains "$R" "head | Recently used |" "apply: recently used shown"
assert_contains "$R" "row | + Make a new profile |" "browser: new"
assert_contains "$R" "row | › Enter a profile… | a link, owner/name, a file or a folder" "browser: enter"
R=$(rows "$D1" stamp)
assert_not_contains "$R" "Recently used" "stamp: no recently used (others' profiles)"
assert_contains "$R" "row | ~/decal-me.tar.gz" "stamp: the stamp file to update"
D2='{"entries": [], "notes": [], "signed_in": false, "active": "/x/folder"}'
R=$(rows "$D2" apply); assert_contains "$R" "head | Active |" "an active profile listed nowhere else: its own group"
R=$(rows "$D2" stamp); assert_contains "$R" "row | ~/decal-me.tar.gz | the usual place" "stamp: the usual file offered when missing"
D3='{"entries": [], "notes": [], "signed_in": true, "loading": true, "active": ""}'
assert_contains "$(rows "$D3" apply)" "note | Looking for your profiles…" "loading: says so"

# whole flows: apply's first Enter still picks the active profile (keystrokes unchanged above);
# Enter a profile… with a folder of someone else's? a local folder is yours: no warning, used, then applied
mkdir -p "$T_TMP/other"; printf '[base]\non = true\n' > "$T_TMP/other/profile.toml"; : > "$LS_TEST_LOG"
D "$REPO/decal" ui -- 1 END ENTER WAIT "$T_TMP/other" ENTER WAIT ENTER WAIT ENTER WAIT ENTER WAIT ENTER q
assert_contains "$(cat "$T_TMP/screen")" "$ decal use $T_TMP/other" "enter a profile: used"
assert_contains "$(cat "$LS_TEST_LOG")" "base add" "...then applied"
```

(`END` jumps to the last row, "Enter a profile…". Add `"END": "\x1b[F"` to `NAMES` in `tests/fixtures/drive_ui.py`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test_ui.sh`
Expected: the new assertions FAIL (`ui.browser_rows` doesn't exist).

- [ ] **Step 3: Implement in `lib/ui.py`**

1. After `remove_cmds`, add the pure layout:

```python
GROUPS = [("github", "On GitHub"), ("file", "On this machine"), ("stick", "On USB sticks"), ("recent", "Recently used")]


def browser_rows(data, purpose, user):
    """The browser's lines: (style, label, aside, value). Stamp leaves out recently used (others' profiles) and offers
    the usual ~/decal-USER.tar.gz when it isn't there yet."""
    rows, entries, act = [], data.get("entries", []), data.get("active", "")
    if purpose == "apply" and act and not any(e.get("active") for e in entries):
        rows += [("head", "Active", "", None), ("row", tilde(act), "← active", {"source": act, "kind": "active", "active": True})]
    for kind, title in GROUPS:
        if purpose == "stamp" and kind == "recent":
            continue
        es = [e for e in entries if e["kind"] == kind]
        extra = []
        if kind == "github":
            if data.get("loading"):
                extra = [("note", "Looking for your profiles…", "", None)]
            elif data.get("signed_in") is False:
                extra = [("row", "Sign in to see your GitHub profiles", "", {"action": "sign-in"})]
        if kind == "file" and purpose == "stamp":
            usual = os.path.join(os.path.expanduser("~"), f"decal-{user}.tar.gz")
            if not any(e["source"] == usual for e in es):
                extra = [("row", tilde(usual), "the usual place", {"source": usual, "kind": "file"})]
        if not es and not extra:
            continue
        rows.append(("head", title, "", None))
        rows += extra + [("row", e["name"], profiles.describe(e) + ("    ← active" if e.get("active") else ""), e) for e in es]
    rows += [("note", n, "", None) for n in data.get("notes", [])]
    rows += [("row", "+ Make a new profile", "", {"action": "new"}),
             ("row", "› Enter a profile…", "a link, owner/name, a file or a folder", {"action": "enter"})]
    return rows
```

2. In `UI.key`, return `None` when no key is waiting (needed for the polling screen), and map End/Home:

```python
    def key(self):
        try:
            k = self.scr.get_wch()
        except curses.error:   # nothing pressed within the timeout
            return None
```
(keep the existing mapping dict; `curses.KEY_END: "end"` and `curses.KEY_HOME: "home"` are already there.)

3. Add to `class UI`:

```python
    def profiles_json(self, only):
        rc, out = decal("profiles", "--json", f"--only={only}")
        try:
            return json.loads(out[out.index("{"):]) if rc == 0 else {}
        except ValueError:
            return {}

    def browse(self, title, purpose):
        """The profile browser: local entries at once, GitHub filled in by a background thread."""
        state = {"data": self.profiles_json("local"), "gh": None}
        state["data"].setdefault("entries", [])

        def github():
            state["gh"] = self.profiles_json("github")

        def start():
            state["gh"] = None
            threading.Thread(target=github, daemon=True).start()

        start()
        user = os.environ.get("USER") or "me"
        i = None
        self.scr.timeout(200)
        try:
            while True:
                d = dict(state["data"])
                gh = state["gh"]
                if gh is None:
                    d["loading"], d["signed_in"] = True, True
                else:
                    seen = {e["source"] for e in gh.get("entries", [])}
                    d["entries"] = gh.get("entries", []) + [e for e in d["entries"] if e["source"] not in seen]
                    d["signed_in"], d["notes"] = gh.get("signed_in"), gh.get("notes", [])
                    d["loading"] = False
                rows = browser_rows(d, purpose, user)
                pickable = [n for n, r in enumerate(rows) if r[0] == "row"]
                if i is None or i not in pickable:
                    act = [n for n in pickable if (rows[n][3] or {}).get("active")]
                    usual = [n for n in pickable if rows[n][2] == "the usual place"]
                    i = (act or usual or pickable)[0]
                top = self.header(title)
                h = self.scr.getmaxyx()[0] - top - 2
                first = max(0, i - h + 1)
                for n, (style, label, aside, _) in enumerate(rows[first:first + h]):
                    y = top + n
                    if style == "head":
                        self.put(y, 2, label, self.c(4, curses.A_BOLD))
                    elif style == "note":
                        self.put(y, 4, label, curses.A_DIM)
                    else:
                        self.put(y, 4, f" {label:<30} ", (curses.A_REVERSE if first + n == i else 0) | curses.A_BOLD)
                        self.put(y, 37, aside, curses.A_DIM)
                self.footer("↑↓ move · enter choose · r refresh · esc back")
                k = self.key()
                if k is None:
                    continue
                pos = pickable.index(i)
                if k == "up": i = pickable[(pos - 1) % len(pickable)]
                elif k == "down": i = pickable[(pos + 1) % len(pickable)]
                elif k == "home": i = pickable[0]
                elif k == "end": i = pickable[-1]
                elif k == "r":
                    state["data"] = self.profiles_json("local"); start()
                elif k in ("esc", "q"):
                    return None
                elif k == "enter":
                    v = rows[i][3]
                    if v.get("action") == "sign-in":
                        self.sign_in(); start()
                        continue
                    return v
        finally:
            self.scr.timeout(-1)

    def sign_in(self):
        """Sign in for this menu session: the key lives in ENV (passed to every decal command), never on disk."""
        curses.endwin()
        r = subprocess.run([sys.executable, os.path.join(REPO, "lib", "auth.py"), "get", "-", "--need", "read"],
                           stdout=subprocess.PIPE, text=True, env=ENV)
        if r.returncode == 0 and r.stdout.strip():
            ENV["GITHUB_TOKEN"] = r.stdout.strip()
        self.scr.refresh()

    def trusted(self, src):
        """Someone else's profile: say so before using it (the preview comes later, before anything changes)."""
        lib = os.path.join(REPO, "lib")
        r = subprocess.run([sys.executable, os.path.join(lib, "source.py"), "resolve", src], capture_output=True, text=True, env=ENV)
        if r.returncode != 0:
            self.view("Apply · that profile", r.stderr.strip() or "decal couldn't read that", "esc back")
            return False
        canon = r.stdout.split("\t")[1]
        login = ""
        if canon.startswith("github:") and ENV.get("GITHUB_TOKEN"):
            w = subprocess.run([sys.executable, os.path.join(lib, "github.py"), "whoami"], capture_output=True, text=True, env=ENV)
            login = w.stdout.strip()
        y = subprocess.run([sys.executable, os.path.join(lib, "source.py"), "yours", canon, "--login", login], env=ENV)
        if y.returncode == 0:
            return True
        who = canon.removeprefix("github:")
        return self.view("Apply · someone else's profile",
                         f"This profile is from {who}, not you.\n\nIt can install software and change system settings.\n"
                         "You'll see a preview of every change before anything happens.",
                         "enter go on · esc back")

    def do_new(self, start_from=""):
        how = start_from or self.choose("New profile · start from", [
            ("this machine", "a stamp of how it's set up now", "this-machine"),
            ("a copy of a profile…", "then change it", "copy"),
            ("empty", "every section commented out", "empty")])
        if how is None:
            return None
        frm = how
        if how == "copy":
            v = self.browse("New profile · copy which one?", "apply")
            if not v or v.get("action"):
                return None
            frm = v["source"]
        where = self.choose("New profile · where", [("GitHub", "a private repo on your account", "github"),
                                                   ("this machine", "~/NAME.tar.gz", "file"),
                                                   ("the USB stick", ".Decal/profile", "stick")])
        if where is None:
            return None
        me = os.environ.get("USER") or "me"
        name = self.ask("New profile · name", "letters, digits, - _ .", f"decal-{me}")
        if not name:
            return None
        use = self.choose("New profile · use it now?", [("yes", "make it the active profile", True), ("no", "", False)])
        if use is None:
            return None
        cmd = ["new", name, "--from", frm, "--to", where] + (["--use"] if use else [])
        self.run([cmd], f"New profile: {name}", "Couldn't make it (see above)")
        return name
```

Add `json` and `threading` to the imports at the top (`import curses, glob, json, os, re, subprocess, sys, threading`), and below them `import profiles  # noqa: E402  (lib/, next to this file: describe() and ago())` — `lib/` is on `sys.path` because `ui.py` runs from it (tests add it too).

4. Replace `do_apply`'s profile question (from `opts = [...]` through the `if self.run([["use", src]], …) != 0: return` block) with:

```python
        v = self.browse("Apply · stick it on · which profile?", "apply")
        if v is None:
            return
        if v.get("action") == "new":
            self.do_new()
            return
        if v.get("action") == "enter":
            src = self.ask("Apply · which profile?", "a link, owner/name, a file or a folder")
            if not src:
                return
            src = os.path.expanduser(src)
        else:
            src = v["source"]
        if not v.get("active"):
            if not self.trusted(src):
                return
            if self.run([["use", src]], "that's the active profile now", "couldn't use it (see above)") != 0:
                return
```

5. Replace `do_stamp`'s "save it to" question (from `me = os.environ…` through the `elif where == "github":` block, keeping `self.run([stamp_cmd(...)])`) with:

```python
        v = self.browse("Stamp · save it to", "stamp")
        if v is None:
            return
        dest, gh, public = "", None, False
        if v.get("action") == "new":
            self.do_new("this-machine")
            return
        if v.get("action") == "enter":
            to = self.ask("Stamp · save it to", "a .tar.gz, a folder, or owner/name on GitHub")
            if not to:
                return
            if re.fullmatch(r"[\w.-]+/[\w.-]+", to) and not os.path.exists(os.path.expanduser(to)):
                gh = to
            else:
                dest = os.path.expanduser(to)
        elif v["kind"] == "github":
            gh = v["source"].removeprefix("github:")
        else:
            dest = v["source"]
```

6. Remove the now-unused prompt text `"owner/name (private: it asks for a token)"` (it went with the old screen).

7. In `tests/fixtures/drive_ui.py`, add `"END": "\x1b[F"` to `NAMES`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_ui.sh`
Expected: `test_ui.sh: … 0 failed` — including the existing flows (apply's `1 ENTER …` lands on the active profile).

- [ ] **Step 5: Try it on a real terminal**

```bash
./decal ui    # 1 (Apply): the browser shows your stamps and sticks; GitHub fills in or offers sign-in; Esc back
```
Expected: the list appears at once; "Looking for your profiles…" turns into your GitHub profiles (with a key) or the sign-in row; arrows/Esc respond while it loads.

- [ ] **Step 6: Full suite, commit**

```bash
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # expect no output
git add lib/ui.py tests/test_ui.sh tests/fixtures/drive_ui.py
git commit -m "menu: the profile browser for apply and stamp (GitHub fills in as it loads, sign in once per menu session, make or enter a profile), and a word before someone else's profile

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: README and roadmap

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-04-usb-feature-roadmap.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: README**

1. In "Put a setup on a machine", after the GitHub one-liner, add: `Any GitHub link works too (https://github.com/you/decal-you, or just you/decal-you), and so does a link to a .tar.gz or .zip.`
2. In "In depth → Profiles", replace the first paragraph with:

```markdown
A profile can be a folder (a USB stick is fine), a `.tar.gz` / `.tgz` / `.zip` (from `decal stamp`, or a link to
one), `owner/repo` or any GitHub link (downloaded without git; `@branch` or a `/tree/branch` link for a branch), or
a git URL. A folder or file by that name here wins over `owner/repo`. `decal profiles` lists the ones decal can
see: yours on GitHub (repos with a `profile.toml`; stamp tags them `decal-profile`), stamps in your home folder,
USB sticks, and recently used ones. `decal new NAME` makes one: from this machine, a copy of another, or a
starter with everything commented out; on GitHub, in a file, or on the stick.

Applying a profile that isn't yours (someone else's repo or link, used for the first time) asks first and offers
a preview: it can install software and change system settings. `--yes` skips the question; the one-line installer
uses it, since you typed the source yourself. Downloads are https only, and archives are unpacked safely (nothing
outside the profile folder, no links, 200 MB at most).
```

3. In "Everyday commands", add rows/lines for `decal profiles` and `decal new NAME` matching the usage text.

- [ ] **Step 2: Roadmap**

In the roadmap's status table, set part 2 to `**Done** (merged …): spec docs/superpowers/specs/2026-10-04-profile-browser-design.md`, and under Part 2 note the deferred minors from its final review (added at finish).

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-04-usb-feature-roadmap.md
git commit -m "README: profiles from anywhere (links, owner/repo, .zip), decal profiles, decal new, the not-yours question

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
