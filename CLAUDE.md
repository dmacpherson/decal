# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

decal saves how a Linux desktop looks and works as a **profile** (`profile.toml` + files), puts it on any machine, and
takes it off again cleanly. Bash + Python 3 (standard library only); a tiny C launcher for USB sticks.
Supported: Fedora Atomic (Bazzite, Silverblue), Fedora/RHEL, Debian/Ubuntu, Arch.

## Commands

```bash
bash tests/run.sh                    # every tests/test_*.sh (each prints "N assertions, M failed")
bash tests/test_usb.sh               # one suite
bash tests/run.sh 2>&1 | grep failed | grep -v ' 0 failed'   # only the failures
shellcheck decal install.sh usb/start.sh tools/*.sh          # bash lint (tests/*.sh report SC1091 info: expected)
bash tests/containers/run.sh         # distro end-to-end in podman (slow; --keep-images keeps the images)
bash tests/shell/run.sh              # the bundled GNOME extension in a headless GNOME Shell
./decal --dry-run apply <profile>    # what would change, without changing anything
./decal ui                           # the menu (a git checkout never updates itself)
```

`tests/test_ui.sh` drives the curses menu in a pseudo-terminal (`tests/fixtures/drive_ui.py`); it takes a few
minutes. Use `UNTIL:text` steps rather than sleeps when adding flows.

## Architecture

- **`decal`** (bash) is the entry point: option parsing, the command `case` at the bottom, and the runner. Each module
  runs in an isolated subshell (`run_module`) with its profile settings as `P_*` variables from `lib/profile.py shell`.
  `add`/`remove`/`apply` re-run themselves through a logging wrapper (spinner on the terminal, full log in
  `~/.local/state/decal/logs/`). A module whose settings, files and decal code are unchanged since its last add is
  skipped (`lib/fingerprint.py`).
- **Modules** (`modules/<name>/`): `module.sh` (`module_add`, `module_remove`, `module_status`, optional
  `module_stamp`/`module_capture`/`module_fetch`/`module_drop`, flags `MODULE_NEEDS_ROOT`, `STAMP_LIVE`, `STAMP_SKIP`,
  `MODULE_CAN_DROP`) and `schema.json` (its profile keys; `lib/profile.py` validates against it). Contract in
  README → Adding a module.
- **Platforms**: `lib/platform.sh` picks `lib/backends/<platform>.sh` (package install/remove, initramfs, transaction
  hooks); `_shared.sh` records what each module installed so `remove` takes away exactly that.
- **State**: system state under `$LS_STATE` (root-owned, `/var/lib/decal`), user state under `$LS_USER_STATE`
  (`~/.local/state/decal`: `applied/` fingerprints, `recent`, `tags`, logs). Tests redirect both (`DECAL_STATE`,
  `DECAL_USER_STATE`) and a fake root (`DECAL_ROOT`; use `sys_path` for system paths).
- **Profiles and sources**: `stage_profile` (in `decal`) turns any source into a validated folder via
  `lib/source.py` (GitHub links / `owner/repo`, archive links, git, local paths; safe unpacking, https only);
  `activate_staged` makes it the active profile at `~/.config/decal/profile`. `lib/profiles.py` finds profiles
  (GitHub, `~/decal-*`, sticks, recent); `decal new` makes them; `decal stamp` reads the machine into one.
- **GitHub**: `lib/auth.py` gets keys (device-flow sign-in with a QR code, or a pre-filled token page) through two
  GitHub Apps: **Decal Profile** (read, keys until revoked) and **Decal Profile Write** (8-hour keys, never saved).
  Key order everywhere: `GITHUB_TOKEN`, `GH_TOKEN`, `gh auth token`, then ask (`gh_auth` in `decal`).
  `lib/github.py` pushes stamps without git.
- **Menu** (`lib/ui.py`, curses): every action runs `decal` commands you could type; pure helpers (`apply_cmds`,
  `usb_cmd`, `browser_rows`, …) are unit-tested, flows are driven in a pty. Stick mode when `DECAL_STICK` is set.
- **USB sticks**: `decal usb` assembles `Decal` (launcher, `usb/launch.c`) + `.Decal/` (`usb/start.sh`,
  `stick.conf`, read key or profile copy, a decal copy) and writes it with `lib/usb.py` (`.Decal.new` swap).
- **Install and release**: `install.sh` (served at `dmacpherson.github.io/decal/install`, `/dev/install` for the dev
  channel) installs to `~/.local/share/decal/app` and decal updates itself from its channel. `.github/workflows/`:
  `build.yml` (launchers + `decal.tar.gz`, shared), `release.yml` (tags `v*`; `-` tags are pre-releases),
  `dev.yml` (each push to `dev` → the rolling `dev` pre-release), `pages.yml` (the installers site, main only).

Design history and decisions: `docs/superpowers/specs/` (the USB feature roadmap lists what's done, what's next and
the deferred minor fixes), plans in `docs/superpowers/plans/`.

## How decal is built

**Keep it simple; build it once.** Prefer the plainest code that does the job. When something is done twice, make
it one shared piece both use, with parameters where their needs differ (`stage_profile` serves apply, use, new and
usb; `build.yml` serves releases and dev builds). One code path per job: no second version for one caller.

**Logic in small pure functions, input/output in thin shells.** Decisions (what to run, what to show, which rows,
which environment) live in functions that are tested without a terminal or network (`browser_rows`, `usb_cmd`,
`clean_env`). Files have one purpose (`auth.py`, `source.py`, `profiles.py`, `usb.py`); split one when it starts
doing two jobs.

**Peel it off cleanly.** Everything `add` changes, `remove` undoes exactly: record what you did at add time
(state files, `pkg_install` ownership, `etc_write` backups) and undo from the record, even after the profile section
is gone. Never remove what decal didn't add. Replaced user files are kept as dated backups.

**Write new, then swap.** Never leave anything half-written: build the new thing beside the old and swap it in when
complete (`.Decal.new` → `.Decal`, the installer's app folder). A failure midway leaves the old one working.

**Don't break people who already use it.** Existing profiles, installs, keys (`GITHUB_TOKEN`, `gh`) and sticks keep
working; when a layout changes, give an upgrade path (the hand-made stick → `decal usb`).

**The menu and the command line always agree; everything is scriptable.** No logic lives only in the menu: it
runs the same `decal` commands, shown before they run. Every question the menu asks has a command-line option.

**Give people choices, with a default and a way past.** Ask when the choice is theirs, offer a sensible default
first, and let a switch skip the question (`--yes`, `--how`, `--to`, …). Don't guess silently for them.

**Nothing changes without a preview or a question.** Dry runs show the exact commands; someone else's profile asks
first; writing a USB stick lists the files first. Never format, never touch files outside what a command owns.

**Fix the cause, not the symptom.** A flaky test or an odd failure is a bug somewhere: find it (a race, a swallowed
key) instead of retrying around it.

**Build what's needed now; write down the rest.** Ideas and deferred minor fixes go in the roadmap
(`docs/superpowers/specs/2026-10-04-usb-feature-roadmap.md`), not into code "just in case".

**Say it plainly.** Messages say what happened and what to do next, in everyday words ("The key on this stick no
longer works: run decal usb on your own machine to give it a new one"). No tracebacks reach the person. The menu's
sticker words (stick it on, peel it off, take a print) are flavour and fun, never at the cost of clarity.

**User-facing things look clean.** Clean names (see Naming), one obvious thing at the root of anything a person
opens (a stick has `Decal` and a hidden `.Decal/`), short screens with the likely choice first.

**Every platform, or a clear skip.** Use the backend functions, never a distro's package manager directly. A module
that can't apply somewhere (no GNOME, no GDM, wrong distro) warns and skips; it doesn't fail the run.

**Prefer what's already there.** Bash for the runner and anything that must run before decal is installed; the
Python 3 standard library for the rest. A new dependency is fine when it clearly earns its place: it must be
available on all four platforms (or installed by decal itself), and the commit says why. Vendored code
(`lib/qrcodegen.py`) stays unmodified, with its licence.

**Tests are hermetic and come first.** Write the failing test, watch it fail, then the code. Tests never touch the
network, the real home, real drives or `/run/media`: stub commands with `stub` (tests/lib.sh), use the fake GitHub
(`tests/fixtures/fake_github_api.py`), unset `DISPLAY`/`WAYLAND_DISPLAY`, stub `gh`. A test that hangs or depends on
timing is a bug in the test.

## Security

decal runs with sudo, applies profiles from other people, downloads from the internet and handles GitHub keys, so
security is part of every change, not a pass at the end.

**Safe by default, risky by choice.** The default is always the safer option: read-only keys, private repos, no
ARM launcher unless asked, asking before someone else's profile, https only. Anything riskier is an explicit choice
with a plain warning (a public repo: "anyone can see what's in it").

**Least privilege.** Never run as root (decal refuses); ask for sudo once, only for modules that need it
(`MODULE_NEEDS_ROOT`), and do everything on the user's side without it (mounting sticks, keys, profiles, stamps).

**Treat input as untrusted.** Profiles, archives, links, sticks, `stick.conf` and GitHub's answers can be hostile:
- validate profiles against each module's `schema.json` before anything runs; never `eval` or source values from a
  profile (only decal's own generated `P_*` assignments);
- unpack only through `lib/source.py` (no paths outside the target, no links or devices, a size cap);
- confine file paths (`sys_path`, no `..`), and quote every variable in bash;
- https only, redirects to http refused; check what a download is before using it.

**Know whose it is.** A profile that isn't yours (not your account's repo, not local, not recently applied by you)
asks first and offers a preview. Only applying makes a source "yours". On a borrowed machine, nothing of its owner's
(their `gh` login, their environment keys) is used for your repos.

**Keys are handled like keys.** Never on a command line (`ps` shows it), never in a log or error message, never on
disk except a read-only key the person chose to save on their own stick (mode 0600 where the filesystem allows).
A key that can write is never stored: write keys come from Decal Profile Write sign-ins (8 hours) and live in memory
for one run or menu session. Classic (`ghp_`) and gh (`gho_`) tokens never go on a stick. Tests assert keys don't
appear in process lists, logs, files or HTTP traffic.

**Verify what you install.** Release downloads are checksum-verified (`decal.tar.gz.sha256`), including the copy on
a stick; releases are built by CI from the tagged commit, never by hand. Fail closed: a mismatch, an unknown source
or a damaged archive stops with a message, changing nothing.

**Reversible and auditable.** Every add/remove/apply is logged (`~/.local/state/decal/logs/`), every change can be
undone, replaced files are backed up.

**Attack tests for sensitive code.** Changes to keys, downloads, unpacking, sudo, trust or anything that writes
outside decal's own folders get tests that try the attack (`../` paths, symlinks, an http redirect, a key in the
wrong place, a stranger's profile) and a security review (`/security-review`) before merging. `gitleaks` runs before
every release.

## Naming

`decal` (lowercase) for the command, files and code; **Decal** for user-facing names: the GitHub Apps, folders on a
stick (`.Decal/`), the double-click launcher (`Decal`). No spaces in folder names. FAT/exFAT ignore case: a `Decal`
file and a `Decal/` folder can't share a directory.

## Workflow

- **New features**: design first (brainstorming → a spec in `docs/superpowers/specs/` → a plan in
  `docs/superpowers/plans/` → build task by task, test first → a fresh whole-branch review → fix → merge).
  Small, well-scoped changes are designed in chat and approved before building.
- **Reviews**: every feature branch gets a fresh whole-branch code review before merging; small changes get one when
  they touch security-sensitive code (see Security) or more than a couple of files; anything security-sensitive also
  gets `/security-review`. Fix Critical and Important findings (each with a test that fails first); record Minor ones
  in the roadmap; record every ruling (a decision the spec or plan didn't make) in the commit or the plan's ledger.
- **Branches**: work merges into `dev`; each push to `dev` publishes a dev build for testing
  (`curl -fsSL https://dmacpherson.github.io/decal/dev/install | bash`). When it's good, merge `dev` into `main` and
  tag a release (`v0.4.0`); only tags reach stable installs.
- **Commits**: one line in the repo's style (`area: what changed, plainly`, lowercase start), then the
  Co-Authored-By trailer. Run the suite and `shellcheck` before committing.
- Don't push, tag or publish without the maintainer's go.
