# Software source preference (prefer = ["flatpak", "brew", "distro"])

A preferred source order for software defined in `[apps]`. Wherever a profile lists software to install, decal resolves and installs it from the first source in `prefer` that provides it. Provenance is recorded, and `remove` uninstalls from the exact source that was used.

## Goal

- `[apps] prefer = ["flatpak", "distro", "brew"]` sets the source priority (default: `["flatpak", "distro", "brew"]`).
- `[apps] install = ["firefox", "ripgrep", "btop"]` resolves each application against available sources in the specified order.
- Specific sections/lists continue to work unchanged:
  - `flatpaks = [...]`: Explicitly installs from Flathub.
  - `packages = [...]`: Explicitly installs from the native distro repository.
- Provenance tracking:
  - Resolution recorded per item in `$LS_STATE/apps/prefer-sources` (`$app $src`).
  - Flatpaks recorded in `$MANAGED`.
  - Distro packages recorded under owner `apps` in `pkg_install`.
  - Brew formulas recorded in `$LS_USER_STATE/apps.brew`.
- Clean removal: `decal remove apps` uninstalls every installed application from the exact source that installed it.
- `decal status` reports the resolved source for each managed app.
- `decal review` shows which source will provide each software item.

## Profile Configuration

```toml
[apps]
prefer = ["flatpak", "distro", "brew"]
install = [
  "com.brave.Browser",
  "ripgrep",
  "btop"
]
```

## Resolution Order

For each name `app` in `install`:
1. Check sources in the order given by `prefer`:
   - `flatpak`:
     - If present (`_fp_present`) or available on the configured Flathub remote (`flatpak remote-info`).
   - `distro`:
     - If present (`_pkg_present`) or available in distro repositories (`pkg_known`).
   - `brew`:
     - If `brew` is available on the machine and the formula exists (`brew info`).
2. Use the first source that matches.
3. If none match: warn plainly that `app` was not found in any preferred source.
