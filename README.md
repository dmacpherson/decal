# decal

Stick your setup onto any Linux machine, and peel it off cleanly.

decal keeps your look and tools in one profile (boot splash, login screen,
wallpaper, cursor, icons, GTK theme, GNOME settings and extensions, apps,
terminal) and applies it module by module on Fedora Atomic (Bazzite,
Silverblue…), Fedora/RHEL, Debian/Ubuntu and Arch. Every module can be removed
again, undoing exactly what it did.

## Install

No git needed: one line downloads the newest release (checksum verified) to `~/.local/share/decal/app`
and puts `decal` in `~/.local/bin`. Give it a profile and it applies it straight away:

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash                                   # install decal
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- ~/my-profile --tags dev     # install + apply
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- github:you/your-profile     # profile from GitHub
```

Installed this way, decal keeps itself current: every run first checks for a newer release and,
if there is one, updates and then runs your command on it (offline, it just carries on;
`--no-update` skips it once). `decal update` updates on demand, `decal version` shows what you have.
`DECAL_VERSION=v1.2.0` (or `main`) before `bash` picks a release (or the newest commit) and is
remembered. Needs `bash`, `curl` or `wget`, `tar` and `python3`. A git checkout (`./decal`) works the same
but never updates itself.

A profile can be a folder (a USB stick is fine), a `.tar.gz` from `decal export`, a git URL, or
`github:owner/repo[@branch]`, downloaded without git. For a private repo set `GITHUB_TOKEN` (a
fine-grained token with read access to it: `curl … | GITHUB_TOKEN=… bash -s -- github:…`), be logged
in with `gh`, or type the token when it asks.

## Use

```bash
./decal apply ~/my-profile          # a folder, a .tar.gz, a git URL or github:owner/repo: becomes the active profile, then applied (never removes anything)
./decal status                      # what's applied
./decal add cursor icons            # apply some modules from the active profile
./decal remove wallpaper            # undo exactly what add did
./decal --dry-run apply <profile>   # show what would happen
./decal --verbose apply <profile>   # show every command's output (normally only in the log)
./decal --force apply <profile>     # apply every module even if it's already up to date
./decal export backup.tar.gz        # pack the active profile
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

Everything fetched from outside has a `source` key: `git+https://…` (with
`path`/`ref`), `github-release:owner/repo` (with `asset`/`version`), an
`https://` URL, or a path inside your profile. Downloads are cached in
`~/.cache/decal/sources`. Each successful `apply` or `fetch` keeps one version per source and drops what
hasn't been used for 30 days.

Adding a module: `modules/<name>/module.sh` (`MODULE_DESC`, `module_add`,
`module_remove`, `module_status`, optionally `module_capture`/`module_fetch`,
`MODULE_NEEDS_ROOT=1`, `module_drop` with `MODULE_CAN_DROP=1` for `remove --only`) plus `schema.json` for its profile keys. Tests:
`bash tests/run.sh`; distro e2e: `bash tests/containers/run.sh` (removes the images it
pulled; `--keep-images` keeps them). Neither leaves files behind. Extensions that ship with decal
(Decal Tweaks) are checked inside a throwaway headless GNOME Shell: `bash tests/shell/run.sh`.

## Licence

MIT, see [LICENSE](LICENSE). The bundled GNOME logo (`modules/gnome-extensions/icons/gnome-logo.svg`) is CC BY-SA 4.0.
