<p align="center"><img src="assets/logo.svg" width="200" alt="decal: an iridescent Tux sticker, one corner peeling"></p>

<h1 align="center">decal</h1>

<p align="center">Stick your setup onto any Linux machine, and peel it off cleanly.</p>

decal keeps your look and tools in one profile (boot splash, login screen,
wallpaper, cursor, icons, GTK theme, GNOME settings and extensions, apps,
terminal) and applies it module by module on Fedora Atomic (Bazzite,
Silverblue…), Fedora/RHEL, Debian/Ubuntu and Arch. Every module can be removed
again, undoing exactly what it did.

## Install

No git needed: one line downloads the newest release (checksum verified) to `~/.local/share/decal/app`
and puts `decal` in `~/.local/bin`. Give it a profile and it applies it straight away:

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash                                   # install decal, open the menu
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- ~/my-profile --tags dev     # install + apply
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- github:you/your-profile     # profile from GitHub
```

Installed this way, decal keeps itself current: every run first checks for a newer release and,
if there is one, updates and then runs your command on it (offline, it just carries on;
`--no-update` skips it once). `decal update` updates on demand, `decal version` shows what you have.
Running the one-liner again is safe: an up-to-date decal isn't downloaded again (`DECAL_REINSTALL=1`
forces it), an older one is updated, and a profile you give it is applied either way.
`DECAL_VERSION=v1.2.0` (or `main`) before `bash` picks a release (or the newest commit) and is
remembered. Needs `bash`, `curl` or `wget`, `tar` and `python3`. A git checkout (`./decal`) works the same
but never updates itself.

A profile can be a folder (a USB stick is fine), a `.tar.gz` from `decal stamp`, a git URL, or
`github:owner/repo[@branch]`, downloaded without git. For a private repo set `GITHUB_TOKEN` (a
fine-grained token with read access to it: `curl … | GITHUB_TOKEN=… bash -s -- github:…`), be logged
in with `gh`, or type the token when it asks.

## Use

Run `decal` on its own for the menu:

```
  1   Apply     stick it on      put a profile on this machine
  2   Stamp     take a print     save this machine's setup as a profile
  3   Remove    peel it off      undo what decal changed
  4   Update    fresh sheet      (when a newer version is out)
  5   Logs      the fine print   what the last run did
```

Each one picks what it covers (the profile's tags and its modules, with their status), shows what would
change, and asks before it does anything. It runs the same commands as below and shows them, so nothing
it does is hidden. The tags you last applied are ticked for you next time.

```bash
./decal use ~/my-profile            # make it the active profile, without applying anything
./decal apply ~/my-profile          # a folder, a .tar.gz, a git URL or github:owner/repo: becomes the active profile, then applied (never removes anything)
./decal status                      # what's applied
./decal add cursor icons            # apply some modules from the active profile
./decal remove wallpaper            # undo exactly what add did
./decal --dry-run apply <profile>   # show what would happen
./decal --verbose apply <profile>   # show every command's output (normally only in the log)
./decal --force apply <profile>     # apply every module even if it's already up to date
./decal stamp                       # save this machine's setup as a profile: ~/decal-$USER.tar.gz
./decal fetch                       # pre-download themes, fonts, ...
./decal capture gnome-settings      # print your current settings to copy into the profile
```

Run it as your normal user; it asks for sudo once when needed. A module that is
already applied, with unchanged settings (and unchanged files they point to), is
skipped without downloading anything; `--force` applies it anyway. In a terminal each
module shows one progress line; the full output of every `add`, `remove` and
`apply` is kept in `~/.local/state/decal/logs/` (`last.log` is the newest). The active
profile lives at `~/.config/decal/profile`. Start from
[`examples/profile/profile.toml`](examples/profile/profile.toml): every key is
listed there, and typos are rejected before anything changes.

| Module | What it does |
|---|---|
| plymouth | Boot splash + disk-unlock prompt (themes from any git source) |
| wallpaper | Blurred login-screen background + desktop wallpaper, separate settings |
| apps | Flatpaks / packages + default apps (installed if missing), launchers your distro hides shown again |
| gnome-settings | Appearance, input, power, dock, launcher (dconf file in your profile) |
| gnome-extensions | Extensions + their settings + panel logo colour |
| display | Scaling for every monitor (e.g. 150%), arrangement kept, saved like GNOME Settings does |
| branding | Login-screen logo |
| account | Your account picture (login screen, lock screen, user menu), no sudo |
| brave | Brave settings its Sync keeps per device (look, toolbar, new tab page, search engines) and Brave Origin, applied while Brave is closed; extensions from the Web Store |
| terminal | Terminal app, Starship prompt, Nerd Font and CLI tools, each feature switchable; Bazzite's welcome message off if you like |
| cursor | Cursor pack (Material Bibata by default), also on the login screen |
| icons | Icon theme from any source, optionally another theme's folders on top |
| gtk-theme | GTK theme for GTK3 apps (optionally forced onto libadwaita apps), Flatpak apps included |
| gnome-extensions → Decal Tweaks | decal's own extension for what no other extension does: any accent colour for GNOME Shell (and GTK apps), instant minimize; one switch per tweak |
| docker | Docker Engine + Compose, the docker service, you in the docker group |
| claude | Claude Code (CLI) and the Claude desktop app (Linux beta: Debian/Ubuntu only) |
| tools | Command-line tools from their official installers (uv), updated on every apply |
| ollama | Ollama (local AI models) from Homebrew, GPU build (integrated GPUs too, on machines without a discrete one), running as your user, plus your models |

### Tags: settings for some machines only

Put settings for some machines in a `[section.tag]` table next to the section. Lists
add on to the section's (a single value and a list add up too, e.g. a second settings
`file`), other values replace its. A section that only has tag tables
is only applied on machines given that tag. Nothing untagged changes.

```toml
[apps]
flatpaks = ["com.discordapp.Discord"]

[apps.dev]                          # dev machines also get these
flatpaks = ["dev.zed.Zed"]

[terminal.steamdeck]
font = "FiraCode Nerd Font 12"      # replaces [terminal] font on the Deck

[docker.dev]                        # docker only on dev machines
group = true
```

```bash
./decal add all                     # the untagged settings only
./decal add all --tags dev          # plus [*.dev]; several: --tags dev,laptop; every tag: --tags all
./decal add all --only dev          # just the modules with a [*.dev] table (with dev's settings)
./decal remove all --only dev       # take dev away: [docker.dev]-only modules removed, dev's apps/brew tools uninstalled
./decal tags                        # the tags your profile uses
```

`all` can't be a tag name, a tag no section has is rejected, and `status` names the tag a
module needs. For `remove --only`, a module that is also in the profile without the tag keeps
its own settings and loses what the tag added (apps: flatpaks and shown launchers; terminal:
brew tools, with `remove-brew = true`; brave: extensions); other modules leave it in place and say so.

### Stamp: your setup, saved as a profile

`decal stamp` reads what you've changed from the defaults on this machine and saves it as a profile
that `decal apply` puts on any other:

```bash
decal stamp                    # -> ~/decal-$USER.tar.gz (the previous one kept as .old)
decal stamp ~/backups/me.tgz   # or a .tar.gz / folder of your choice
decal stamp -dr                # --dry-run: show what it would save, save nothing
decal stamp apps brave         # just these modules
decal stamp -gh                # --github: also into a private repo, decal-$USER (or -gh owner/name; --public)
```

Only what's yours goes in, compared with the distro's own defaults:

| | How decal knows it's yours |
|---|---|
| GNOME settings | your dconf values that differ from the distro's (its system databases) and the schema's, in the areas worth carrying (appearance, windows, input, power, shortcuts, app folders, dock, Files, terminal, weather); never app history or state |
| Extensions | the ones that are on, the distro's you turned off, their settings changed from default, config files they point to, decal's panel logo |
| Flatpaks | flatpak's install history: apps installed since the OS was, still here, and the distro's you removed |
| Packages | layered on an Atomic image (`rpm-ostree` records exactly those) |
| Default apps | your `mimeapps.list` |
| Wallpaper, account picture, themes | only if changed; a theme you installed into your home is bundled, the system's aren't |
| Brave | the per-device settings decal knows (no counters or history), Brave Origin, extensions you added from the Web Store |
| Docker, Ollama (with models), Claude Code, uv | installed: under the `dev` tag |

A module decal set up from your profile that is still in place goes in as your profile has it (tags and
sources kept). Display scaling is never stamped (it differs per machine). `-gh` works without git: each
stamp is one commit, and it ends with the line to put the setup on the next machine. The token (from
`GITHUB_TOKEN`, `gh`, or asked for) needs permission to create a repo and write to it.

Everything fetched from outside has a `source` key: `git+https://…` (with
`path`/`ref`), `github-release:owner/repo` (with `asset`/`version`), an
`https://` URL, or a path inside your profile. Downloads are cached in
`~/.cache/decal/sources`. Each successful `apply` or `fetch` keeps one version per source and drops what
hasn't been used for 30 days.

Adding a module: `modules/<name>/module.sh` (`MODULE_DESC`, `module_add`,
`module_remove`, `module_status`, optionally `module_capture`/`module_fetch`,
`MODULE_NEEDS_ROOT=1`, `module_drop` with `MODULE_CAN_DROP=1` for `remove --only`, `module_stamp` printing its
section of a stamp, with `STAMP_LIVE=1` to always read the machine and `STAMP_SKIP=1` to never be stamped) plus `schema.json` for its profile keys. Tests:
`bash tests/run.sh`; distro e2e: `bash tests/containers/run.sh` (removes the images it
pulled; `--keep-images` keeps them). Neither leaves files behind. Extensions that ship with decal
(Decal Tweaks) are checked inside a throwaway headless GNOME Shell: `bash tests/shell/run.sh`.

Logo: Tux, the Linux penguin, after Larry Ewing's original (drawn anew in `assets/logo.py`).

## Licence

MIT, see [LICENSE](LICENSE). The bundled GNOME logo (`modules/gnome-extensions/icons/gnome-logo.svg`) is CC BY-SA 4.0.
