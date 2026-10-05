<p align="center"><img src="assets/logo.svg" width="200" alt="decal: an iridescent Tux sticker, one corner peeling"></p>

<h1 align="center">decal</h1>

<p align="center">Stick your setup onto any Linux machine, and peel it off cleanly.</p>

decal saves how your Linux desktop looks and works (wallpaper, themes, GNOME settings and extensions,
apps, terminal, and more) and puts it on any other machine in one line. Everything it changes can be
taken off again, cleanly. Works on Bazzite and other Fedora Atomic images, Fedora, Debian/Ubuntu and Arch.

## Get started

Install decal and open its menu:

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash
```

From the menu you can apply a setup, stamp this machine, or take things off again. After this, just run
`decal` to open it.

Want the newest features before they're released? The **dev** build is the latest of the `dev` branch (it may
break); decal then updates itself from dev builds:

```bash
curl -fsSL https://dmacpherson.github.io/decal/dev/install | bash
```

Run the first line again to go back to the stable releases.

## Save your setup

Stamp this machine: decal saves what you've changed from the defaults to `~/decal-$USER.tar.gz`.

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- stamp
```

Or stamp it straight into a private GitHub repo, `decal-$USER`, so you can apply it from anywhere:

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- stamp --github
```

## Put a setup on a machine

From your GitHub stamp (`decal stamp --github` prints this line with your name filled in):

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- github:YOUR-NAME/decal-YOUR-NAME
```

Any GitHub link works too (`https://github.com/you/decal-you`, or just `you/decal-you`), and so does a link to a
`.tar.gz` or `.zip`.

From a stamp file you've copied over:

```bash
curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- ~/decal-$USER.tar.gz
```

A private repo needs a GitHub key: decal lets you sign in (with a code, or a QR code on your phone), or uses `gh`
if you're logged in. Only some
modules? Put their names after the profile, e.g. `… bash -s -- github:YOUR-NAME/decal-YOUR-NAME ollama`.

## Take it off again

Undo everything decal changed on this machine:

```bash
decal remove all
```

## Put it on a USB stick

```bash
decal usb
```

Asks which profile, how the stick gets it (a saved read-only key, signing in each time, or a copy), which decal it
runs and which stick (a Ventoy stick is fine: decal only adds `Decal` and a hidden `.Decal` folder). Then
double-click **Decal** on any Linux PC: a terminal opens, decal installs, your profile is fetched and decal's menu
opens. Run `decal usb` again to update the stick.

## What decal can set

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

## In depth

### Everyday commands

The menu runs these same commands and shows them before it does anything.

```bash
decal use ~/my-profile            # make it the active profile, without applying anything
decal apply ~/my-profile          # a folder, a .tar.gz/.zip, owner/repo or a GitHub link, an archive link, a git URL: becomes the active profile, then applied (never removes anything)
decal profiles                    # the profiles decal can see: yours on GitHub, stamps here, USB sticks, recently used
decal new decal-work --from empty # a new profile: from this machine (default), a copy, or a starter; --to github|file|stick
decal usb --to folder             # the USB stick files in ~/decal-usb, to copy anywhere (decal usb alone asks step by step)
decal status                      # what's applied
decal add cursor icons            # apply some modules from the active profile
decal remove wallpaper            # undo exactly what add did
decal --dry-run apply <profile>   # show what would happen
decal --verbose apply <profile>   # show every command's output (normally only in the log)
decal --force apply <profile>     # apply every module even if it's already up to date
decal stamp                       # save this machine's setup as a profile: ~/decal-$USER.tar.gz
decal fetch                       # pre-download themes, fonts, ...
decal capture gnome-settings      # print your current settings to copy into the profile
```

Run it as your normal user; it asks for sudo once when needed. A module that is
already applied, with unchanged settings (and unchanged files they point to), is
skipped without downloading anything; `--force` applies it anyway. In a terminal each
module shows one progress line; the full output of every `add`, `remove` and
`apply` is kept in `~/.local/state/decal/logs/` (`last.log` is the newest). The active
profile lives at `~/.config/decal/profile`. Start from
[`examples/profile/profile.toml`](examples/profile/profile.toml): every key is
listed there, and typos are rejected before anything changes.

### What a stamp contains

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

### Profiles

A profile can be a folder (a USB stick is fine), a `.tar.gz` / `.tgz` / `.zip` (from `decal stamp`, or a link to
one), `owner/repo` or any GitHub link (downloaded without git; `@branch` or a `/tree/branch` link for a branch), or
a git URL. A folder or file by that name here wins over `owner/repo`. `decal profiles` lists the ones decal can
see: yours on GitHub (repos with a `profile.toml`; stamp tags them `decal-profile`), stamps in your home folder,
USB sticks, and recently used ones. `decal new NAME` makes one: from this machine, a copy of another, or a
starter with everything commented out; on GitHub, in a file, or on the stick. A private repo needs a GitHub
key: `GITHUB_TOKEN`, your `gh` login, or sign in when decal asks (see [Signing in to GitHub](#signing-in-to-github)).

Applying a profile that isn't yours (someone else's repo or link, used for the first time) asks first and offers
a preview: it can install software and change system settings. `--yes` skips the question; the one-line installer
uses it, since you typed the source yourself. Downloads are https only, and archives are unpacked safely (nothing
outside the profile folder, no links, 200 MB at most).

Everything fetched from outside has a `source` key: `git+https://…` (with
`path`/`ref`), `github-release:owner/repo` (with `asset`/`version`), an
`https://` URL, or a path inside your profile. Downloads are cached in
`~/.cache/decal/sources`. Each successful `apply` or `fetch` keeps one version per source and drops what
hasn't been used for 30 days.

### Signing in to GitHub

A private profile needs a GitHub key. decal uses `GITHUB_TOKEN`, `GH_TOKEN` or your `gh` login if you have one;
otherwise it asks:

- **Sign in with GitHub:** open the link (or scan the QR code with your phone), enter the code, click Authorize.
  The first time, GitHub asks you to install the app on your profile repo; pick just that repo.
- **Make a token myself:** decal opens GitHub's new-token page filled in (read-only, or read and write for
  `stamp --github`); choose how long it lasts, pick your profile repo, generate, paste.

decal never saves a key it got by signing in. Two GitHub Apps do the signing in:

| App | Can | Its keys |
|---|---|---|
| Decal Profile | read the contents of the repos you install it on | last until you revoke them |
| Decal Profile Write | read and write contents, create repos | expire after 8 hours |

To revoke: GitHub → Settings → Applications → Authorized GitHub Apps → Decal Profile → Revoke (this stops every key it
gave out, on every machine and stick). To take its access away from a repo: Installed GitHub Apps → Decal Profile → Configure.

#### Registering the apps (maintainers and forks)

Done once, by hand, at GitHub → Settings → Developer settings → GitHub Apps → New GitHub App. For each app:

- Name: `Decal Profile` / `Decal Profile Write` (slugs `decal-profile`, `decal-profile-write`); Homepage URL:
  the decal repo.
- Identifying and authorizing users: no callback URL; **Enable Device Flow** on; "Request user authorization
  during installation" off. **Expire user authorization tokens:** off for Decal Profile, on for Decal Profile Write.
- Webhook: Active off.
- Repository permissions: Decal Profile: Contents read-only. Decal Profile Write: Contents read and write, Administration read and
  write. No account or organisation permissions.
- Where can this GitHub App be installed: Any account.

Then put each app's Client ID and URL slug in `APPS` in `lib/auth.py` (`"Iv23…:decal-profile"`), or, for a fork without
editing code, set `DECAL_GITHUB_APP_READ` / `DECAL_GITHUB_APP_WRITE` to the same `CLIENT_ID:slug`.

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
decal add all                     # the untagged settings only
decal add all --tags dev          # plus [*.dev]; several: --tags dev,laptop; every tag: --tags all
decal add all --only dev          # just the modules with a [*.dev] table (with dev's settings)
decal remove all --only dev       # take dev away: [docker.dev]-only modules removed, dev's apps/brew tools uninstalled
decal tags                        # the tags your profile uses
```

Name a module on its own and it doesn't need the tag: `decal add ollama` uses `[ollama.dev]`'s settings
for Ollama only, without the rest of `dev`. `all` can't be a tag name, a tag no section has is rejected,
and `status` names the tag a module needs. For `remove --only`, a module that is also in the profile without the tag keeps
its own settings and loses what the tag added (apps: flatpaks and shown launchers; terminal:
brew tools, with `remove-brew = true`; brave: extensions); other modules leave it in place and say so.

### Installing and updating

The one-line installer downloads the newest release (checksum verified) to `~/.local/share/decal/app` and
puts `decal` in `~/.local/bin`; no git needed. Installed this way, decal keeps itself current: every run first checks for a newer release and,
if there is one, updates and then runs your command on it (offline, it just carries on;
`--no-update` skips it once). `decal update` updates on demand, `decal version` shows what you have.
Running the one-liner again is safe: an up-to-date decal isn't downloaded again (`DECAL_REINSTALL=1`
forces it), an older one is updated, and a profile you give it is applied either way. After `bash -s --`
it takes a profile to apply (with any `decal apply` options, e.g. `--tags dev`), or `stamp` and any
`decal stamp` options; with nothing, it opens the menu (`DECAL_NO_MENU=1`: it just installs).
`DECAL_VERSION=v1.2.0` (or `main`) before `bash` picks a release (or the newest commit) and is
remembered; `DECAL_VERSION=dev` (what `/dev/install` uses) follows the dev builds, `latest` the stable releases. Needs `bash`, `curl` or `wget`, `tar` and `python3`. A git checkout (`./decal`) works the same
but never updates itself.

### Adding a module

A module is `modules/<name>/module.sh` (`MODULE_DESC`, `module_add`,
`module_remove`, `module_status`, optionally `module_capture`/`module_fetch`,
`MODULE_NEEDS_ROOT=1`, `module_drop` with `MODULE_CAN_DROP=1` for `remove --only`, `module_stamp` printing its
section of a stamp, with `STAMP_LIVE=1` to always read the machine and `STAMP_SKIP=1` to never be stamped) plus `schema.json` for its profile keys. Tests:
`bash tests/run.sh`; distro e2e: `bash tests/containers/run.sh` (removes the images it
pulled; `--keep-images` keeps them). Neither leaves files behind. Extensions that ship with decal
(Decal Tweaks) are checked inside a throwaway headless GNOME Shell: `bash tests/shell/run.sh`.

Logo: Tux, the Linux penguin, after Larry Ewing's original (drawn anew in `assets/logo.py`).

## Licence

MIT, see [LICENSE](LICENSE). The bundled GNOME logo (`modules/gnome-extensions/icons/gnome-logo.svg`) is CC BY-SA 4.0.
