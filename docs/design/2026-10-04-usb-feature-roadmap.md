# USB stick feature: roadmap (parts 1–4)

Put a decal installer on a USB stick (or in a folder) from decal itself, so anyone can double-click it on any Linux
machine and get their setup. Agreed with the maintainer on 2026-10-04. Each part gets its own spec → plan →
implementation; this file records what's already decided so each part's design starts from it.

| Part | What | Status |
|---|---|---|
| 1 | GitHub sign-in | **Done** (merged 2026-10-04): `docs/design/2026-10-04-github-sign-in-design.md` |
| 2 | Profile browser | **Done** (merged 2026-10-05): `docs/design/2026-10-04-profile-browser-design.md` |
| 2b | Profile review ("What this profile will do") | After 2 |
| 3 | USB maker | **Done** (merged 2026-10-05; trial release and real-stick test pending): `docs/design/2026-10-05-usb-maker-design.md` |
| 4 | Save back from a stick | **Done** (merged 2026-10-05; bounded: designed in chat) |

Order matters: each part uses the ones before it.

## Naming (all parts)

- `decal` for commands and files; **Decal** for user-facing names: folders, the double-click launcher, apps.
- GitHub Apps: **Decal Profile** (read; keys last until revoked) and **Decal Profile Write** (8-hour keys, never
  saved). "Decal" itself is a taken GitHub account name.
- Case-insensitive filesystems (exFAT/FAT): a `Decal` file and a `Decal/` folder can't share a directory.

## Part 1: GitHub sign-in (done)

What later parts can rely on:

- `gh_auth REPO read|write [--may-create]` in `decal`: asks on the terminal (sign in with a code or QR code, or paste
  a token from a pre-filled page) and exports `GITHUB_TOKEN` for the rest of the run. Nothing saved on the machine.
- `lib/auth.py`: `get`, `check` (exit codes OK/BAD_KEY/CANT_SEE/READ_ONLY/OFFLINE, reason on stderr),
  `token-url --need read|write --days 30|90|365|none`, `install-url --need read|write`; `qr_lines`, `columns`,
  `layout`, `install_layout` for screens; the install step opens the app's install page and shows its QR code.
- Key order everywhere: `GITHUB_TOKEN`, `GH_TOKEN`, `gh auth token`, then ask. A `gh` key is never put on a stick
  (it can do anything to every repo and never expires).

Deferred minors from part 1's review (fix when touching that code):
- Arrow/function keys (escape sequences) cancel the sign-in wait; leftovers reach the next prompt.
- Device flow switched off (a fork's app): the message should suggest "Make a token myself".
- A 5xx / rate limit on `/user` for an owner-less repo reads as "didn't accept that key".
- `lib/ui.py:349` still says "private: it asks for a token".
- Unverified: whether `/repos` `permissions.push` reflects a fine-grained token's access or the user's role.

## Part 2: Profile browser (next)

One screen, reused by apply, stamp, remove and usb in place of their own "where's the profile?" questions:

- Lists: your GitHub profiles (your repos holding a `profile.toml`), stamp files on this machine and on a plugged-in
  stick, and the active profile.
- "Make a new profile" at the bottom (a new GitHub repo, e.g. `decal-work`, stamped from this machine).
- Uses part 1 to sign in when it needs to list private repos or create one.
- Known constraint: a Decal Profile Write installed on picked repos can't create a new repo; part 1's flow already
  waits for "All repositories" in that case. Alternatively send people to GitHub's new-repo page pre-filled, then
  the install page for that repo.

Deferred minors from part 2's review (fix when touching that code):
- Stale GitHub listings in the menu (after `r` or a sign-in) can overwrite fresher ones: number each run.
- A damaged archive with a file and a folder of the same name gives a traceback instead of "could not unpack".
- Listing reads every member of big `~/decal-*.tar.gz` files: stop at the first shallow `profile.toml`.

Open questions for its design: how repos are found (name pattern `decal-*`, a topic, or a `profile.toml` check per
repo), how local stamp files are found, what the browser shows per profile (last stamped, private/public, modules).

## Part 2b: Profile review

A "What this profile will do" screen before applying a profile that isn't yours (and `decal review PROFILE` for any):
everything it installs or downloads, grouped, with notes where a trust signal is weak. Information, not a block.

| Asks for | Check | Flag when |
|---|---|---|
| Flatpaks | Flathub API: exists, verified publisher, install count | not on Flathub, unverified, very few installs |
| GNOME extensions | extensions.gnome.org (reviewed): downloads, last update | from a git URL, or not updated for this GNOME |
| Homebrew formulas | core vs third-party tap | `user/tap/formula` |
| Native packages | the distro's repos | (listed; removals listed too) |
| Theme/icon/font/splash sources | the link's host | not a well-known host, a bare IP, a shortener, `http://` |
| Files in the profile | type and size | executables, scripts, unusually large files |

Honest limit: catches the obvious cases; the "not yours" warning (part 2) stays the real protection.

## Part 3: USB maker

`decal usb` and a **usb** menu item. Steps:

1. **Which profile?** The profile browser (part 2), including "stamp this machine now" (which also pushes the stamp
   to the person's GitHub repo).
2. **How the stick gets it** (one choice):
   - A. GitHub + a saved read key (default for a private repo)
   - B. GitHub, ask for the key each time it's used
   - C. A copy of the profile on the stick (no key; refreshed by running usb again)
   - A public repo skips keys: "always the latest" or "a copy". A stamp file is always copied.
3. **The key** (A/C): part 1's sign-in with the Decal Profile app, or "make a token myself" with an expiry choice
   (30 days / 90 days (default) / 1 year / never). Never a `gh` key. Only read keys are saved on a stick (a write
   key would expire in 8 hours anyway; saving back signs in each time, part 4).
4. **Which drive?** Plugged-in USB drives, a Ventoy stick first ("Ventoy · 14 ISOs · 57.7 GB"), or **"A folder: I'll
   copy it myself"** (default `~/decal-usb`; the summary warns that zipping or some cloud drives drop the executable
   bit). A confirmation lists exactly what will be written.
5. **Done**: what's on the stick; "double-click Decal on any Linux machine"; Ctrl+H shows the hidden folder.

Running usb again on a stick that has decal updates it (new key, fresh profile copy, newer launcher), skipping
answered steps unless the person wants to change them.

**On the stick** (root):

```
Decal        ← double-click (a small static launcher binary)
.Decal/      hidden: decal-me.sh-style script, which profile, the read key or the profile copy
*.iso        (Ventoy's images, untouched)
```

- The launcher is a static x86-64 binary (GNOME Files won't run scripts or .desktop files on double-click). A
  prototype (copies in `docs/design/usb-prototype/`) exists on the maintainer's stick: `launch.c` built with musl in an Alpine container
  (`gcc -Os -static -s`), which runs `Decal/decal-me.sh` (to become `.Decal/…`) next to it; the script reopens itself
  in a terminal (ptyxis, kgx, gnome-terminal, konsole, xfce4-terminal, mate-terminal, tilix, alacritty, kitty,
  x-terminal-emulator, xterm) when started without one. The binary must be built reproducibly in the release
  workflow, not committed blind.
- Ventoy: detect by label and the `ventoy/` folder; never touch `ventoy/` or the images.
- Later idea (not in part 3): Ventoy auto-install files to apply a profile right after a distro installs.

**What double-clicking Decal does:** opens a terminal, installs/updates decal, downloads the profile (or uses the
copy) — nothing applied yet — then opens decal's normal menu with the stick's profile loaded and a header
("From your USB stick: owner/repo · updated just now"), options in this order:

- Apply everything
- Choose what to apply (tags or single modules)
- Preview first (dry run)
- Save this machine to GitHub (part 4)
- Take it all off (`decal remove all`; for borrowed machines)
- What's on this machine (status, out-of-date modules)
- Use a different profile (the profile browser)
- Full menu

No separate stick menu: the normal one, with that header and order. No "temporary mode".

### Part 3: deferred minors (fix when touching that code)

- start.sh blames any failed `decal use` on the key (offline, a declined sign-in…); the dead key stays exported for
  the menu session.
- start.sh with no known terminal carries on without one (curses fails): fall back to opening the README.
- Offline in `newest` mode, the stick's copy can replace a newer decal already installed.
- A stick pulled out between the two renames has only `.Decal.old`/`.Decal.new`: the launcher could try `.Decal.old`.
- An unrelated lowercase `decal/` folder on a FAT stick would be moved to `Decal-old` (FAT ignores case).
- The decal copy from a git checkout includes untracked files and uncommitted edits: use `git ls-files`, mark `-dirty`.
- A saved key is obtained before the confirmation and the launcher download (unused if you answer no).
- The menu's usb entry drops into the full menu after `decal usb` instead of exiting.
- `source.py public` treats "offline" as private, so a public repo is offered a saved key.

### Audit batch 1 (security): deferred minors

- Legitimate package forms now refused: dnf groups (`@virtualization`), provides (`perl(Foo::Bar)`), globs
  (`texlive-*`). Support them deliberately if wanted, or say so in the message.
- Zip theme archives containing symlinks are refused (tar ones with inside links work).
- gnome-extensions `files.*`: a `~/.config/<sub>` that is itself a symlink (dotfile managers) is refused by `inside`.
- `decal new --from <someone else's> --use` makes a local copy that then counts as yours without the question.
- A profile made active before this change (old `use`, never asked) is applied from the menu without the question.
- Git sources check out symlinks as they are; `path`/`theme` could go through one (not traced to a leak).

### Audit batch 2 (your data and clean removal): deferred minors

- `swrite`'s `NAME.decal-new` temp, left by a crash, sits in `.d` folders (`gdm.d`, `apt.conf.d`) that read every
  file; use a dot-prefixed temp or clean it in `etc_restore`.
- `swrite` keeps mode only when the user can see the old file (root-only folders fall back to 644); owner/group
  aren't kept (every target is root-owned today).
- A `/etc` file that was a symlink is now replaced by a file (`etc_restore` puts the link back).
- terminal: `/home/linuxbrew` ownership isn't restored (Homebrew is kept); the `terminal.homebrew` marker is written
  after the installer, so an interrupted Homebrew install isn't noted.
- docker still calls `apt-cache` directly (`modules/docker/module.sh:8`).
- `activate_staged`: killed between the two renames leaves no active profile (same-source re-download only).
  `do_stamp` clears `DEST.decal-new`/`.decal-old` without the `.decal-stamp` check.
- gnome-extensions: a gtk-3.0 `gtk.css` link holding only decal's block is left as an empty file, not removed.
- Release note: records written before this version list flatpaks you already had; remove uninstalls those.

### Audit batch 3 (messages and tests): deferred minors

- `new --to stick:NAME`: the "plugged in:" list ends with a stray space and runs labels with spaces together (join
  with ", "); a full path with a trailing `/` doesn't match; `stick:` alone says "no USB stick named  (".
- `tests/test_auth.sh`: the wait for "Choose" before Ctrl+C falls through silently after 10 s; the pty test still
  sleeps 0.5 s after "Waiting for GitHub" before reading the terminal mode.
- `test_ui.sh` flows at the apply, enter-a-profile and stick-save steps don't check drive_ui's exit code (125 = a
  screen never showed); their content checks catch it, less clearly.
- The start.sh wget path of `reachable` has no test (curl is always on the test machine).
- Release note: the menu keys moved (3 is USB, 4 Remove, 5 Logs, 6 Update when there is one).

### Audit batch 4 (simplicity): deferred minors

- `gh.request` follows redirects with the key (urllib's default), as `auth.api_get`/`github.call` did before; GitHub's
  API only redirects within itself. `source.download`'s `_KeyStaysHome` could serve it too.
- `usb_bin` follows the install's channel: on a branch channel the archive has no launchers (they're built by CI), so
  `decal usb` says the release has none; it could fall back to the latest release.
- The menu's `Data.load` still parses `decal tags`/`decal status` text with regexes; `parse_tags`/`parse_status`
  (or `--json` on those commands) would make it testable on its own. The picker's tick rules could be a pure `toggle`.
- `do_usb` picks the default `--how` and writes `stick.conf` inline (`usb.py conf-text` was suggested).
- A new profile's README is written in two places (`cmd_stamp.sh` and `profiles.py readme`); the default stamp place
  is in bash (`cmd_stamp.sh`) and Python (`profiles.usual_stamp`).

### Deferred minors: cleared 2026-10-05

The lists above and below were worked through in `plans/2026-10-05-deferred-minors.md`: each item fixed, found
already done, or decided against (the reasons are there). Still open:
- Unverified: whether `/repos` `permissions.push` reflects a fine-grained token's access or the user's role (needs a
  real GitHub).
- A git checkout profile's links are checked after `git pull`, so a bad link is refused once it's already there.
- In a real terminal, Esc followed within 50 ms by another key loses that key during the sign-in wait.
- Release notes for v0.4.0: `release-notes-v0.4.0.md` (draft).
- The install address is written twice: `lib/cmd_stamp.sh` (its "on another machine" line) and `profiles.py readme`.
- `usb.py write` moves any case variant of a `Decal` folder aside (with a note), not only `Decal` itself: needed on
  FAT/exFAT, where the launcher can't sit next to it (the plan said "exact case"; this is the ruling).

## Part 4: Save back from a stick

From the stick's menu, **Save this machine** (after Preview first): the module picker and preview, then "Save to":
where the stick's profile came from (its GitHub repo, or the stick's copy), **both** (copy sticks), or **somewhere
else…** (the profile browser). GitHub saves sign in with Decal Profile Write once per menu session (8 hours at most;
in memory only); the stick's read key, GITHUB_TOKEN, GH_TOKEN and the PC's gh login are never used for it
(`clean_env`). The stick's copy is updated in place.

## Ideas (not planned yet)

- **A preferred source order for software.** `prefer = ["flatpak", "brew", "distro"]` in the profile. Wherever a
  module installs software, decal tries each source in that order and uses the first one that has it. It records
  which source it used (as it records ownership today), and `remove` takes the software away from that same source.
  Today each module fixes its own source: apps uses Flatpak, terminal and ollama use Homebrew, the rest use the
  distro through `pkg_install`. To design:
  - how names map between sources (a Flathub id, a formula, a package name);
  - a per-module or per-item override;
  - the default order, which should match today's behaviour so existing profiles don't change;
  - how `status` reports where something came from.

## The maintainer's own stick (works today, keep it working)

`/run/media/denis/Ventoy`: `decal-me` (launcher), `Decal/decal-me.sh`, `Decal/decal-token.txt` (a token with admin
rights on `decal-profile` that's also in a chat transcript: to be replaced with a read-only one). Part 3 should
offer to upgrade a stick laid out like this to the new layout.
