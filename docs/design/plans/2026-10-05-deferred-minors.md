# The deferred minors

> Executed with superpowers:executing-plans (native). Source: the "deferred minors" lists in
> `docs/design/2026-10-04-usb-feature-roadmap.md` (parts 1–3, audit batches 1–4).

**Goal:** clear the small fixes the reviews set aside. Each list item is either fixed here (test first), already done,
or decided against (with the reason, recorded in the roadmap).

## Tasks

1. **Sign-in and GitHub** (part 1, batch 4):
   - Arrow/function keys no longer cancel the sign-in wait, and leave nothing for the next prompt.
   - Device flow switched off (a fork's app): suggest "Make a token myself".
   - A 5xx or rate limit on `/user` is "GitHub isn't answering properly", not "didn't accept that key".
   - The menu no longer says "private: it asks for a token".
   - `gh.request` doesn't carry the key across a redirect to another host (one handler, shared with
     `source.download`).
2. **Profiles and archives** (part 2, batch 1):
   - Menu listings are numbered, so a stale one can't overwrite a fresher one.
   - A damaged archive (a file and a folder with the same name) says "could not unpack".
   - Listing stops at the first shallow `profile.toml` in a big archive.
   - Zip theme archives keep links that stay inside.
   - Git sources: a link that leads outside the checkout is refused.
   - Package groups, provides and wildcards are refused with a message that names them.
3. **Trust** (batch 1):
   - `decal new --from <someone else's> --use` asks first.
   - `decal add` with an active profile that was never asked about (made active by an older `use`) asks first.
4. **The stick** (part 3, batch 3, batch 4):
   - `start.sh` with no terminal opens the README instead of failing.
   - Offline, the stick's copy doesn't replace a newer decal that's already installed.
   - The launcher falls back to `.Decal.old` when `.Decal` is missing (a stick pulled out mid-update).
   - Only a `Decal` folder in that exact case is moved aside.
   - The decal copy from a git checkout holds tracked files only, marked `-dirty` when edited.
   - The read key is fetched after the confirmation.
   - The menu's USB item exits after `decal usb` when it was started as `decal usb`.
   - `stick.conf` is written by `usb.py`.
   - `usb_bin` falls back to the latest release when the channel has no launchers.
   - `new --to stick:NAME`: a clean list of the plugged-in sticks, a trailing `/` matches, and an empty name is
     refused.
5. **Your data** (batch 2):
   - `swrite`'s temp is dot-prefixed (folders that read every file never see it).
   - Mode and owner are kept, including in root-only folders.
   - terminal's Homebrew marker is written before the installer runs.
   - docker asks the backend whether a package exists, never `apt-cache` directly.
6. **The menu's logic** (batch 4):
   - `parse_tags`, `parse_status` and `toggle` become pure functions with tests.
   - Stamp's README comes from `profiles.py readme`.
   - The default stamp place is decided once (`profiles.py usual-stamp`).
7. **Tests** (batch 3):
   - test_auth waits loudly, with no fixed sleep.
   - test_ui's flows fail when a screen never showed.
   - start.sh's wget path is tested.
8. **Release housekeeping**:
   - The workflow actions move to their Node 24 versions, and runners are pinned to `ubuntu-24.04`.
   - Draft v0.4.0 release notes (menu keys moved, old flatpak records).

## Decided against (recorded in the roadmap)

- `/etc` files that were links become files on add. `etc_restore` puts the link back, so the result is the same.
- A gtk-3.0 `gtk.css` link that held only decal's block is left empty. Removing the link would leave you a broken
  dotfile.
- The `activate_staged` and `do_stamp` rename windows: the names involved are decal's own, and they're recoverable.
- `/home/linuxbrew` ownership: Homebrew is kept, so the folder stays usable as it is.
- `source.py public` offline: making a stick downloads the profile first, so it's already online.
- gnome-extensions `files.*` through a symlinked `~/.config/<sub>`: confinement is the point. The message names the
  link so you know why.
- Fine-grained tokens' `permissions.push`: needs a real GitHub to check (left in the roadmap).

Then: full suite, a fresh whole-branch review (plus `/security-review` for tasks 1–3), fix, merge into dev.
