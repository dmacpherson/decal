# USB maker (part 3 of 4)

Part of the USB stick feature (roadmap: `docs/design/2026-10-04-usb-feature-roadmap.md`). Builds on part 1
(GitHub sign-in: `gh_auth`, `lib/auth.py`) and part 2 (profile browser: `lib/source.py`, `lib/profiles.py`,
`decal profiles`, `decal new`, the menu's `browse()`). Part 4 (save back from a stick) comes next.

## Goal

From decal itself, put a double-clickable decal on a USB stick (or in a folder) that, on any Linux PC, installs
decal, fetches the chosen profile and opens decal's menu, ready to apply. It replaces the hand-made stick (`decal-me`,
`Decal/decal-me.sh`, `Decal/decal-token.txt`) and never stores a key that can write.

Success looks like:

- `decal usb` (or the menu's usb item) walks through profile → how the stick gets it → key → which decal → where →
  confirm, and writes the stick; running it again updates the stick.
- Double-clicking `Decal` on a fresh PC opens a terminal, gets decal and the profile, and shows the stick menu;
  with no internet it still opens using the stick's decal copy (when it has one).
- Pulling the stick out mid-write never leaves it without a working setup.
- The maintainer's existing stick is upgraded, its admin-capable token file removed only after the new setup works.

## Naming

`Decal` (the launcher, at the root) and `.Decal/` (everything else, hidden); `decal` for commands and files inside.
On exFAT/FAT a `Decal` file and a `Decal/` folder can't coexist, hence the hidden folder.

## `decal usb`: the steps

Menu item **usb** ("put decal on a USB stick"); command `decal usb [options]` with an option for every question
(`--profile SOURCE`, `--how saved-key|sign-in|copy|latest`, `--days 30|90|365|none` (token page), `--decal
newest|copy|online`, `--arm`, `--to DRIVE|folder[:PATH]`, `--yes` to skip the confirmation).

1. **Which profile?** Part 2's browser, plus "Stamp this machine now" (runs `decal new … --from this-machine` to the
   place the person picks, e.g. their GitHub repo; then that profile is used).
2. **How the stick gets it:**
   - Private GitHub repo: **A. saved read key** (default) · **B. sign in each time** · **C. a copy**.
   - Public GitHub repo: **latest** (default; no key) · **a copy**.
   - A file, folder, link or stick profile: always **a copy**.
3. **The key (A):** part 1's sign-in with **Decal Profile** (read-only; lasts until revoked), or "make a token
   myself" (read-only, 30/90/365 days or never; the pre-filled page). Checked with `auth.py check REPO --need read`
   before going on. A `gh` login or a key that can write is never saved: decal says why and asks for a sign-in.
4. **Which decal the stick runs:** **newest, with a copy as backup** (default) · **always the copy** · **always the
   newest, no copy**. And **Also for ARM machines** (off by default).
5. **Where:** plugged-in USB drives (removable or USB transport; a Ventoy stick first, shown as "Ventoy · 14 ISOs ·
   57.7 GB"); a plugged-in but unmounted drive is mounted with `udisksctl mount` (no sudo); or **a folder** ("I'll copy
   it myself", default `~/decal-usb`; the summary warns that zipping or some cloud drives drop the "can run" bit).
6. **Confirm:** the exact files to be written; nothing outside `Decal` and `.Decal/` is touched; a drive is never
   formatted.
7. **Done:** a summary: what's on the stick, "double-click Decal on any Linux PC", Ctrl+H shows `.Decal`, and on ARM
   `.Decal/Decal-ARM` (when added).

**Updating:** a drive with `.Decal/stick.conf` starts with "Update this stick?": the decal copy, launchers and profile
copy are refreshed; answers are kept and each can be changed (e.g. a new key).

**Upgrading the old layout:** a drive with `decal-me` and `Decal/decal-me.sh` (the hand-made stick) is offered an
upgrade. The new setup is written and checked first; then `decal-me`, `Decal/decal-me.sh` and `Decal/decal-token.txt`
are removed (and the empty `Decal/`), and the summary says to revoke that old token on GitHub. Other files in
`Decal/` are left alone (and `Decal/` with them).

## On the stick

```
Decal                 the launcher (x86-64): runs .Decal/start.sh; without it, opens .Decal/README.txt
.Decal/
  start.sh            the stick script (the same on every stick)
  stick.conf          the answers (key=value lines)
  key                 the read-only key (A only)
  profile/            the profile copy (C only; part 2 lists it)
  decal.tar.gz        the decal copy, and decal.tar.gz.sha256 (unless "always the newest")
  Decal-ARM           the ARM launcher (only with "Also for ARM machines")
  README.txt          what this is, how to use it, ARM, how to revoke the key
```

`stick.conf` (written by decal, readable by people):

```
# Made by decal v0.4.0 on 2026-10-05. Run decal usb to change it.
profile=github:dmacpherson/decal-profile     # or: copy
key=saved                                    # saved | ask | none
decal=newest                                 # newest | copy | online
version=v0.4.0                               # of the decal copy
```

**Writing safely:** everything is written to `.Decal.new/` (and `Decal.new`), then swapped in with two renames;
the previous `.Decal/` is kept as `.Decal.old/` until the swap succeeded, then removed. A stick pulled out midway has
either the old or the new setup, never half of one. Writes are followed by `sync`.

## Double-clicking `Decal` (`start.sh`)

1. Not in a terminal → reopen in one (ptyxis, kgx, gnome-terminal, konsole, xfce4-terminal, mate-terminal, tilix,
   alacritty, kitty, x-terminal-emulator, xterm); the window stays open at the end ("Press Enter to close").
2. **decal:** `newest` → the online installer (with a timeout); if it can't, "Couldn't check for a newer decal: using
   the copy on this stick (v0.4.0)" and install from the copy. `copy` → install from the copy. `online` → online only.
   The copy is checked against its `.sha256` before use; a mismatch → "the decal copy on this stick is damaged".
3. **The profile:** A → `GITHUB_TOKEN` from `.Decal/key`, `decal use github:…`; B → `decal use github:…` (signs in
   with part 1's screen); C → the folder is packed into a temporary `.tar.gz` and `decal use`d, so the profile lives
   on the machine (unplugging the stick is fine). Nothing applied yet.
4. **The menu:** `decal ui` with `DECAL_STICK=<.Decal path>`: header "From your USB stick: <profile> · updated <when>",
   choices in this order: Apply everything · Choose what to apply · Preview first · Take it all off · What's on this
   machine · Use a different profile · Full menu. ("Save this machine to GitHub" arrives with part 4.)

Trust: a profile on the stick (copy) is local → yours; a GitHub repo the key's account owns → yours; anything else
gets part 2's question the first time.

Failures say what to do, then wait for Enter:

| Situation | Message |
|---|---|
| No internet, no copy | "No internet, and this stick has no copy of decal: connect to the internet and try again." |
| Key revoked/expired (401/404) | "The key on this stick no longer works (revoked or expired): run decal usb on your own machine to give it a new one. Or press s to sign in now." |
| Damaged copy | "The decal copy on this stick is damaged (checksum): run decal usb to refresh it." (falls back to online when allowed) |
| Not x86-64 (start.sh run by hand on ARM) | works; `start.sh` itself is architecture-independent |

## Building and shipping the launchers

- `usb/launch.c` (from the prototype): finds its own folder via `/proc/self/exe`, runs `bash <dir>/.Decal/start.sh`;
  missing → `xdg-open <dir>/.Decal/README.txt`. Built static (`gcc -Os -static -s`, musl).
- The release workflow builds `Decal-x86_64` (Alpine on `ubuntu-latest`) and `Decal-aarch64` (Alpine on
  `ubuntu-24.04-arm`), and adds them to the release's `decal.tar.gz` as `decal/usb/bin/` before its checksum is made.
- `decal usb` takes them from `$LS_REPO/usb/bin/`; a git checkout without them downloads them from the latest
  release's `decal.tar.gz` (checksum-verified) into `~/.cache/decal/usb-bin/`.

## Components

- `usb/launch.c`, `usb/start.sh`, `usb/README.txt` (template).
- `lib/usb.py`: `drives()` (lsblk JSON: removable/usb, mounted or mountable; Ventoy by label + `ventoy/` folder; ISO
  count; size), `mount(dev)`, `read_conf`/`write_conf`, `write_stick(target, files)` (the `.Decal.new` swap),
  `old_layout(target)`, `upgrade(target)`. CLI used by `decal`: `drives --json`, `mount DEV`, `write …`, `conf PATH`.
- `decal`: `usb` command (`do_usb`), reusing `stage_profile`, `do_new`, `gh_auth`, `auth.py`, `profiles.py`.
- `install.sh`: `DECAL_ARCHIVE=PATH` installs from a local `decal.tar.gz` (+ `.sha256`) instead of downloading.
- `lib/ui.py`: the usb item (runs `decal usb` steps through the same screens), and stick mode (`DECAL_STICK`).
- `.github/workflows/release.yml`: build both launchers, add them to the archive.

## Testing

No real drives, no network.

- `lib/usb.py`: fake `lsblk` JSON (a Ventoy stick, a plain stick, an unmounted one, an internal disk that must not
  show), a fake media folder; Ventoy first with ISO count; `udisksctl` stubbed.
- Writing: each A/B/C × decal choice → the right files and `stick.conf`; `--arm` adds `Decal-ARM`; an interrupted
  write (fail after `.Decal.new`) leaves the old `.Decal/` working; update keeps answers; upgrade removes the old
  token file only after the new setup is in place; nothing outside `Decal`/`.Decal/` changes (a checksum of the rest
  of the fake drive before and after); the folder target.
- Keys: a `gh` key refused for saving; a key that can write refused; `auth.py check` failure stops before writing.
- `start.sh` with a fake installer and a stub `decal`: newest → copy fallback with the message; copy-only; online-only
  with no internet → the message; a damaged copy refused; A/B/C reach `decal use` with the right source and key; the
  revoked-key message; started without a terminal → a stub terminal is launched.
- `install.sh` with `DECAL_ARCHIVE`: installs from the file; a bad checksum is refused.
- Launcher: when `gcc` with static libc (or podman) is available, built and run from another folder: it runs
  `.Decal/start.sh`; without it, the README is opened (stub `xdg-open`). Skipped with a note otherwise.
- Menu: the usb item's commands (pure helpers), the stick header and order (plain text), a driven flow writing to a
  fake stick.
- The release workflow: checked after merging with a test tag (`v0.4.0-rc1`), whose `decal.tar.gz` must contain both
  launchers that run (`file` says static x86-64 / aarch64).

## Out of scope

- Saving back from a stick (part 4); profile review (part 2b).
- Ventoy auto-install integration (later idea in the roadmap).
- Formatting or partitioning drives; Windows/macOS launchers.
