# Audit batch 1: security

> Executed with superpowers:executing-plans (native). Spec: the 2026-10-05 compliance audit against CLAUDE.md →
> Security (findings summarised below; each task names the finding it closes).

**Goal:** a profile, archive, link or stick can't run code, write outside its place, or escalate with sudo; keys reach
only what needs them; trust and borrowed-PC protection live in `decal` itself, not just the menu.

## Global constraints
- CLAUDE.md → Security and How decal is built apply. Tests first; each attack gets a test that tries it.
- Existing legitimate profiles keep validating: `examples/profile`, `tests/fixtures/profile`, every module test's
  profiles, and the maintainer's real profile (checked by hand, not committed).
- No network in tests.

## Review focus
- A value valid before and still legitimate (an icon theme with spaces, `org.gnome.Platform//47`, `llama3:8b`,
  `user/tap/formula`, `bibata-*.tar.gz`) must still pass.
- Defence in depth: modules re-check names even though the profile check already did.

---

### Task 1: Profile value rules (`lib/profile.py`, `modules/*/schema.json`)
Closes: package/flatpak names as options (root), plymouth/terminal/extension/theme `../` names, Brewfile injection,
unconfined `path` values, http `remote-url`/extension `source`, unvalidated `files.*` keys and git `ref`s.

New schema types, each a string (`…s` = a list of them):
- `name`/`names`: packages, flatpaks, extension UUIDs, app ids, models, tools, Brave extension ids, the flatpak remote.
  `^[A-Za-z0-9][A-Za-z0-9._+:@/~=-]*$`, no `..`, no `//` except flatpak refs (`app//branch` allowed once).
- `formula`/`formulas`: Homebrew (`name`, `user/tap/name`): `^[a-z0-9][a-z0-9._+@-]*(/[a-z0-9._+@-]+){0,2}$`.
- `theme`: a theme, terminal app/layout/theme, nerd font, Brave profile, icon folders: no `/`, not `.`/`..`, no
  leading `-`, no control characters (spaces allowed).
- `relpath`: a folder inside a source (`path`): relative, no `..` component, no leading `-`.
- `ref`: a git ref: `^[A-Za-z0-9._/-]+$`, no leading `-`, no `..`.
- `glob`/`globs`: release asset patterns: no `/`, no leading `-`.
- `url`: https only.
- `path` (existing): must resolve (realpath) inside the profile folder.
- `"key": "relpath"` on a `name.*` table: each key is checked as `relpath`.

Schemas updated to use them (apps, brave, cursor, gnome-extensions, gtk-theme, icons, ollama, plymouth, terminal,
tools). `tests/test_profile.sh`: every attack value from the audit rejected with a plain message; the review-focus
values accepted; every fixture/example profile still validates.

### Task 2: Defence in depth in the code
Closes the same findings at the point of use.
- Backends: `--` before package names in every `_pkg_add`/`_pkg_rm`/`_pkg_present` (apt, dnf, rpm-ostree, pacman,
  rpm, dpkg); flatpak install/uninstall `--` before ids.
- `terminal`: `_load_adapter` accepts only `terminals/<name>.sh` that exists, name `^[a-z0-9-]+$`; `_preset` refuses
  names with `/`; Homebrew via `brew install -- NAMES` checked against the formula rule (Brewfile kept for the update
  timer only, written from checked names).
- `gnome-extensions`: UUIDs re-checked before any `rm -rf`/`cp`; `files.*` targets must stay under their config dir.
- `plymouth`: `realpath -m` of the destination must be under `/usr/share/plymouth/themes/`.
- Tests: the backend calls carry `--`; each module refuses a crafted value even when handed it directly.

### Task 3: One safe downloader (`lib/fetch.py` → `lib/source.py`)
Closes: fetch.py's own unpacker (no size cap, unfiltered fallback), http redirects followed.
- `source.unpack(archive, dest, links="inside")`: also `.tar.xz`/`.txz`/`.tar.bz2`/`.tar` by content; with
  `links="inside"`, symlinks whose target stays inside `dest` are kept (themes use them), others refused.
- `fetch.py` downloads with `source.download` and unpacks with `source.unpack(..., links="inside")`; `extract` and
  the `except TypeError` shim go.
- `tests/test_fetch.sh`: an http redirect refused; a symlink to `/etc/passwd` refused; a symlink inside kept; a theme
  archive (xz) still unpacks; the size cap applies.

### Task 4: https only for every download
Closes: gnome-extensions `source` http, curl/wget following http redirects.
- `curl` everywhere decal downloads (install.sh `_get`, usb/start.sh, decal `usb_bin`/`gh_tarball`,
  gnome-extensions) gets `--proto =https --proto-redir =https` (tests' http fakes go through stubs).
- gnome-extensions `source` becomes type `url`.

### Task 5: Keys only where needed
Closes: keys inherited by modules and third-party installers; the key briefly on disk.
- `run_module` unsets `GITHUB_TOKEN`/`GH_TOKEN` (no module needs them).
- `gh_tarball` passes the header on stdin (`curl -H @-`), not through a file.
- Tests: a module sees no key; no `gh-auth` file is ever created.

### Task 6: Trust and borrowed-PC protection in `decal`
Closes: `decal use` + `add` skipping the question; the borrowed-PC protection living only in the menu.
- `decal use` runs `trust` (as `apply` does; `--yes` skips). The menu runs `decal use` in the terminal and its own
  `trusted()` copy goes.
- With `DECAL_STICK` set, decal's writes to GitHub (`stamp -gh`, `new --to github`) never use `GITHUB_TOKEN`,
  `GH_TOKEN` or `gh`: they sign in fresh with Decal Profile Write (the menu's `clean_env` key still works:
  `DECAL_WRITE_KEY` is the one key they accept).
- Tests: `decal use stranger/x; decal add all` without a terminal stops; `decal stamp -gh` with `DECAL_STICK` set and
  a `GITHUB_TOKEN` signs in instead; the menu flows still pass.

Then: full suite, a fresh whole-branch review, `/security-review`, fix, merge.
