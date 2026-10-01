# decal

Stick your setup onto any Linux machine, and peel it off cleanly.

decal keeps your look and tools in one profile (boot splash, login screen,
wallpaper, cursor, icons, GTK theme, GNOME settings and extensions, apps,
terminal) and applies it module by module on Fedora Atomic (Bazzite,
Silverblue…), Fedora/RHEL, Debian/Ubuntu and Arch. Every module can be removed
again, undoing exactly what it did.

```bash
./decal apply ~/my-profile          # a folder, a .tar.gz, or a git URL: becomes the active profile, then applied (never removes anything)
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
| apps | Flatpaks / packages + default apps (installed if missing) |
| gnome-settings | Appearance, input, power, dock, launcher (dconf file in your profile) |
| gnome-extensions | Extensions + their settings + panel logo colour |
| display | Scaling for every monitor (e.g. 150%), arrangement kept, saved like GNOME Settings does |
| branding | Login-screen logo |
| terminal | Terminal app, Starship prompt, Nerd Font and CLI tools, each feature switchable |
| cursor | Cursor pack (Material Bibata by default), also on the login screen |
| icons | Icon theme from any source, optionally another theme's folders on top |
| gtk-theme | GTK theme for GTK3 apps (optionally forced onto libadwaita apps), Flatpak apps included |
| gnome-extensions → Decal Tweaks | decal's own extension: any accent colour for GNOME Shell (it only offers a fixed list) |
| docker | Docker Engine + Compose, the docker service, you in the docker group |
| claude | Claude Code (CLI) and the Claude desktop app (Linux beta: Debian/Ubuntu only) |
| tools | Command-line tools from their official installers (uv), updated on every apply |
| ollama | Ollama (local AI models) from Homebrew, GPU build, running as your user, plus your models |

Everything fetched from outside has a `source` key: `git+https://…` (with
`path`/`ref`), `github-release:owner/repo` (with `asset`/`version`), an
`https://` URL, or a path inside your profile. Downloads are cached in
`~/.cache/decal/sources`. Each successful `apply` or `fetch` keeps one version per source and drops what
hasn't been used for 30 days.

Adding a module: `modules/<name>/module.sh` (`MODULE_DESC`, `module_add`,
`module_remove`, `module_status`, optionally `module_capture`/`module_fetch`,
`MODULE_NEEDS_ROOT=1`) plus `schema.json` for its profile keys. Tests:
`bash tests/run.sh`; distro e2e: `bash tests/containers/run.sh` (removes the images it
pulled; `--keep-images` keeps them). Neither leaves files behind. Extensions that ship with decal
(Decal Tweaks) are checked inside a throwaway headless GNOME Shell: `bash tests/shell/run.sh`.

## Licence

MIT, see [LICENSE](LICENSE). The bundled GNOME logo (`modules/gnome-extensions/icons/gnome-logo.svg`) is CC BY-SA 4.0.
