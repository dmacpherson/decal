# USB stick feature: roadmap (parts 1–4)

Put a decal installer on a USB stick (or in a folder) from decal itself, so anyone can double-click it on any Linux
machine and get their setup. Agreed with the maintainer on 2026-10-04. Each part gets its own spec → plan →
implementation; this file records what's already decided so each part's design starts from it.

| Part | What | Status |
|---|---|---|
| 1 | GitHub sign-in | **Done** (merged 2026-10-04): `docs/superpowers/specs/2026-10-04-github-sign-in-design.md` |
| 2 | Profile browser | **Done** (merged 2026-10-05): `docs/superpowers/specs/2026-10-04-profile-browser-design.md` |
| 2b | Profile review ("What this profile will do") | After 2 |
| 3 | USB maker | **Done** (merged 2026-10-05; trial release and real-stick test pending): `docs/superpowers/specs/2026-10-05-usb-maker-design.md` |
| 4 | Save back from a stick | **Built** (bounded: designed in chat; branch `stick-save`) |

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
  prototype (copies in `docs/superpowers/specs/usb-prototype/`) exists on the maintainer's stick: `launch.c` built with musl in an Alpine container
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

## Part 4: Save back from a stick

From the stick's menu, **Save this machine** (after Preview first): the module picker and preview, then "Save to":
where the stick's profile came from (its GitHub repo, or the stick's copy), **both** (copy sticks), or **somewhere
else…** (the profile browser). GitHub saves sign in with Decal Profile Write once per menu session (8 hours at most;
in memory only); the stick's read key, GITHUB_TOKEN, GH_TOKEN and the PC's gh login are never used for it
(`clean_env`). The stick's copy is updated in place.

## The maintainer's own stick (works today, keep it working)

`/run/media/denis/Ventoy`: `decal-me` (launcher), `Decal/decal-me.sh`, `Decal/decal-token.txt` (a token with admin
rights on `decal-profile` that's also in a chat transcript: to be replaced with a read-only one). Part 3 should
offer to upgrade a stick laid out like this to the new layout.
