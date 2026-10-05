# Profile browser (part 2 of 4)

Part of the USB stick feature (roadmap: `docs/superpowers/specs/2026-10-04-usb-feature-roadmap.md`). Builds on part 1
(GitHub sign-in: `gh_auth`, `lib/auth.py`). Part 2b (profile review: Flathub/GNOME/Homebrew/link checks) comes
after this and is out of scope here.

## Goal

One place to see and pick profiles, wherever they live, and to make new ones: used by the menu's apply and stamp
today, and by part 3's USB maker. Anything a person can paste — a GitHub link, `owner/name`, a link to an archive,
a file — just works. Profiles that aren't yours get a clear warning before they change anything.

Success looks like:

- Opening apply in the menu lists your GitHub profiles, stamp files on this machine, profiles on plugged-in sticks,
  and ones used recently, with the active one marked; GitHub fills in after a sign-in if there's no key.
- `decal apply https://github.com/friend/decal-setup` works without git; so do `friend/decal-setup`,
  `github.com/friend/decal-setup/tree/laptop`, a `.zip` link, a `.tar.gz` file.
- `decal new decal-work --from empty --to github` makes a private repo with a starter profile; nothing is ever
  overwritten.
- Applying a stranger's profile shows who it's from and offers a preview before anything happens.

## The two commands

Both live in a new `lib/profiles.py` (listing, `new`) and `lib/source.py` (recognising and unpacking sources),
called from `decal` like the other helpers. The menu only runs these commands (its rule: "every action runs the same
decal commands you could type").

### `decal profiles [--json] [--sign-in]`

Finds profiles in four places:

| Where | How |
|---|---|
| GitHub (repos you own) | Candidates: repos with the topic `decal-profile`, repos named `decal-*`, and every repo you own when you own 100 or fewer. Each candidate is checked for a `profile.toml` at the top (8 at a time); only those are listed. |
| This machine | `~/*.tar.gz` / `~/*.tgz` / `~/*.zip` whose name starts with `decal-`, and `~/decal-*` folders an earlier stamp made (`.decal-stamp` inside); each must hold a `profile.toml`. |
| Plugged-in sticks | `.Decal/profile/` (a profile folder) on each drive mounted under `/run/media/$USER` (part 3 writes it; part 2 reads it). |
| Recently used | the last 10 sources applied on this machine, from `~/.local/state/decal/recent` (`source<TAB>ISO date` per line; no keys, ever). |

The active profile (its recorded source, or the folder/file it came from) is marked on whichever entry matches.

GitHub details:
- The key comes from part 1's order (`GITHUB_TOKEN`, `GH_TOKEN`, `gh auth token`). With none, nothing is asked: the
  GitHub group is a single row "Sign in to see your GitHub profiles"; `--sign-in` signs in (Decal Profile, read)
  first. A Decal Profile key sees only the repos the app is installed on, which is normally exactly your profiles.
- Listing: `GET /user/repos?affiliation=owner&per_page=100` (all pages); topic search
  `GET /search/repositories?q=topic:decal-profile+user:LOGIN`; check `GET /repos/O/R/contents/profile.toml`.
- Organisation repos: not in part 2.
- From now on `decal stamp --github` (and `decal new --to github`) adds the `decal-profile` topic to the repo.

Each entry: `kind` (`github` / `file` / `stick` / `recent`), `source` (exactly what `decal apply` takes:
`github:owner/repo` or a path), `name` (what's shown), `private` (GitHub only), `updated` (ISO: the repo's last push,
the file's or folder's modification time, the date last used), `modules` (how many module sections the profile has),
`active` (bool), `label` (a stick's volume label). Text output: one aligned line per entry, grouped like the menu.

Failures: GitHub unreachable → local, stick and recent entries still listed, plus one line "couldn't reach GitHub";
a candidate whose check fails is left out; a stick or file that can't be read is left out.

### `decal new NAME [--from this-machine|PROFILE|empty] [--to github|file[:PATH]|stick] [--public] [--use]`

| `--from` | What goes in |
|---|---|
| `this-machine` (default) | a stamp of this machine (`decal stamp`'s output) |
| `PROFILE` (anything `apply` takes) | a copy of that profile; its README is rewritten to name the new one; nothing applied |
| `empty` | `examples/profile/profile.toml` with every section commented out, and a short README |

| `--to` | Where |
|---|---|
| `github` (default) | a new private repo `NAME` on your account (`--public` for public), signing in with Decal Profile Write when there's no key; part 1's install step asks for "All repositories" when the app can't create it |
| `file[:PATH]` | `~/NAME.tar.gz`, or PATH |
| `stick` | `.Decal/profile/` on the plugged-in stick (asks which when there are several; says to plug one in when there are none) |

`new` never overwrites: an existing repo, file or stick profile stops it with "it already exists: use decal stamp
to update it". `--use` makes the new profile the active one (nothing applied). In the menu, "+ Make a new profile"
asks: start from (this machine / a copy of one / empty), where (GitHub / this machine / the stick), the name
(suggests `decal-<user>`, or `decal-<user>-2` when taken), then "use it now?".

## Recognising sources

One function, `lib/source.py resolve INPUT`, prints the canonical source and how it was read; `set_profile` calls it
first, so the menu, `decal apply`, `decal new --from` and the one-line installer all agree.

| Input | Becomes |
|---|---|
| An existing file or folder here (relative or absolute, `~` expanded) | that path — local wins |
| `github:owner/repo[@ref]` | itself |
| `owner/repo[@ref]` (not an existing path) | `github:owner/repo[@ref]` |
| `github.com/owner/repo…`, `https://github.com/owner/repo[.git]`, `…/tree/REF`, `…/commit/SHA` | `github:owner/repo[@REF]` (downloaded without git; private via sign-in) |
| `https://…` ending `.tar.gz` / `.tgz` / `.zip` | download, then unpack |
| `https://…` ending `.git`, `git+…`, `ssh://…`, `git@…` | git clone (as today) |
| Any other `https://…` | download; an archive holding a `profile.toml` is used; otherwise try a git clone; otherwise "that link isn't a decal profile" |
| `http://…` | refused: "use an https:// link" |

When an input could be both a local path and `owner/repo`, decal says which it used ("using the folder
./friend/setup; for GitHub, write github:friend/setup").

## Trust and safety

- **Not yours → warn, preview, confirm.** Yours: a GitHub repo owned by the account of the key in use, a source in
  the recently-used list, a local file or folder, a stick. Anything else (a stranger's repo, a link): before
  applying, decal says "This profile is from friend/decal-setup, not you. It can install software and change system
  settings." and offers the preview (dry run) first, then asks to go on. The menu's apply already previews; the
  command line asks on the terminal, and `--yes` skips the question. Without a terminal and without `--yes`, it
  stops with that message (the one-line installer passes `--yes`: the person typed the source themselves).
- **Safe unpacking** of every archive (downloaded or local), by Python: members must stay inside the target folder
  (no absolute paths, no `..`), no symlinks/hardlinks/devices, regular files and folders only, 200 MB unpacked at
  most. `.tar.gz`, `.tgz` and `.zip`. Replaces `tar -xzf` in `set_profile`.
- **https only** for downloads (redirects to `http://` refused).

## The menu

```
 Profiles · which one?                                        (Looking for your profiles…)

 On GitHub
   dmacpherson/decal-profile    private · stamped 3 days ago · 14 modules    ← active
   dmacpherson/decal-work       private · stamped 2 months ago · 6 modules
 On this machine
   ~/decal-denis.tar.gz         file · 2 days ago · 15 modules
 On USB sticks
   Ventoy: .Decal               copy · 1 week ago · 14 modules
 Recently used
   friend/decal-setup           public · used 2 weeks ago
 + Make a new profile
 › Enter a profile…             a link, owner/name, a file or a folder

 ↑↓ move · enter choose · r refresh · esc back
```

- **Apply:** "which profile?" becomes this screen; a choice goes on to the existing picker → preview → apply.
- **Stamp:** "save it to" becomes this screen: an existing entry updates it (GitHub repo, file or stick), "+ Make a
  new profile" runs `decal new … --from this-machine`, "Enter a profile…" saves to a typed path or repo.
- Local, stick and recent entries show at once; GitHub fills in when `decal profiles --json` returns (shown as
  "Looking for your profiles…"); `r` refreshes; results kept for the menu session.
- Choosing "Sign in to see your GitHub profiles" leaves the menu screen (as running a command does), runs
  `auth.py get` for Decal Profile, and the menu keeps the key in its own environment for the rest of the session
  (passed to the decal commands it runs; never written anywhere).
- `lib/ui.py`'s "private: it asks for a token" wording goes with the old screen (a part 1 deferred minor).

## Components

- `lib/source.py`: `resolve(input) -> (kind, source, note)`; `unpack(archive, dest)` (safe, size-capped);
  `download(url, dest)` (https only). CLI: `resolve INPUT`, `unpack ARCHIVE DIR`, `fetch URL DIR` (download +
  unpack-or-clone, prints the profile folder).
- `lib/profiles.py`: `find_github(token)`, `find_local(home)`, `find_sticks(media)`, `read_recent(state)`,
  `entries() -> list[dict]`, text/JSON output; `new(...)`. CLI: `list [--json]`, `new …`.
- `lib/github.py`: `set_topic(repo)` used by `push`; repo listing / search / contents helpers for `profiles.py`.
- `decal`: `profiles` and `new` commands; `set_profile` calls `source.py resolve` and uses `source.py` for archives
  and links; `apply` records the source in `recent` and runs the "not yours" check (`--yes`); `stamp --github`
  tags the topic.
- `install.sh`: passes `--yes` with the source it was given.
- `lib/ui.py`: the browser screen (pure layout function + curses loop), used by `do_apply` and `do_stamp`; the
  session key.
- `examples/profile/profile.toml`: unchanged; `new --from empty` comments out its sections on the fly.

## Testing

Against the fake GitHub from part 1, extended with `/user/repos` (paged), `/search/repositories`, `contents`, repo
`pushed_at`, topics. No network.

- Discovery: topic + name + full scan union; `decal-notes` without `profile.toml` left out; over 100 repos → no full
  scan, topic and names still found; GitHub down → local entries plus the note; no key → the sign-in row.
- Local, stick (a fake `/run/media/$USER` via an override variable) and recent entries; the active mark.
- `resolve`: every row of the table, including local-wins and its note, `http://` refused.
- Archives: `.tar.gz`, `.zip`, a GitHub-style single top folder; `../` member, absolute path, symlink, hardlink,
  device, over 200 MB → refused with nothing written outside the target.
- `new`: each `--from` × each `--to`; existing target refused; `--use`; the topic set on GitHub.
- Trust: a stranger's repo without `--yes` and without a terminal → stops with the message; with `--yes` → applies;
  own repo / recent / local → no question.
- Menu: the browser layout as plain text (grouping, active mark, sign-in row, narrow terminal); apply and stamp
  build the expected `decal profiles` / `decal new` commands (pure helpers like `apply_cmds`), and whole flows
  typed into the menu in a pseudo-terminal with `tests/fixtures/drive_ui.py`, as `tests/test_ui.sh` does today.

## Out of scope

- Profile review with Flathub / GNOME / Homebrew / link checks (part 2b).
- Organisation repos; GitLab/Codeberg as first-party listings (their links still work through git).
- The USB maker itself and the stick layout beyond `.Decal/profile/` (part 3); saving back (part 4).
