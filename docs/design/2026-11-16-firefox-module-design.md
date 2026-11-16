# Firefox module design

A `firefox` module matching `brave`'s model: captures, applies, checks, and cleanly removes all Firefox customizations that Firefox Sync does not sync across machines, supporting both Flatpak (`org.mozilla.firefox`) and native Firefox installations.

## What Firefox Sync Covers vs. Misses

Firefox Sync covers bookmarks, history, tabs, passwords, form autofill, AMO add-on reinstallation (when enabled), and ~111 allowlisted preferences marked by `services.sync.prefs.sync.*`. It leaves behind:

1. **Non-allowlisted `about:config` preferences (`prefs.js`)**: e.g., `browser.uiCustomization.state` (toolbar & pinned extension layout), `sidebar.*` (vertical tabs, sidebar visibility/tools), `doh-rollout.*` / `network.trr.*` / `network.dns.*`, `toolkit.legacyUserProfileCustomizations.stylesheets`, `privacy.fingerprintingProtection` / `query_stripping` / `bounceTrackingProtection`, `browser.newtabpage.activity-stream.*` logo/widgets, and `browser.compactmode.show`.
2. **Search engines, defaults, hidden built-ins, and custom shortcuts (`search.json.mozlz4`)**: Firefox Sync only syncs a legacy default preference; `search.json.mozlz4` is local and includes machine-salted hashes (`defaultEngineIdHash`) that reset if copied raw to another profile. Cross-machine sync works reliably via Firefox's `SearchEngines` enterprise policy (supported on Rapid Release since Firefox 139 and ESR since 60).
3. **Containers (`containers.json`)**: Not synced by core Firefox Sync.
4. **Custom UI CSS (`chrome/userChrome.css`, `chrome/userContent.css`)**: Local profile files only.
5. **MIME / protocol handlers (`handlers.json`)**: Local OS/profile file; opt-in.
6. **Declarative extensions & enterprise policies (`policies.json`)**: Ensures AMO extensions install deterministically (`ExtensionSettings` with `normal_installed`, keeping the user able to toggle them) alongside `SearchEngines` and optional user policies.

## Paths & Resolution

### Profile Directory Discovery (`_dir`, `_profile_dir`)
Check both native and Flatpak locations (supporting Firefox 147+ XDG `~/.config/mozilla/firefox` and legacy `~/.mozilla/firefox`):
1. `${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox` (native XDG)
2. `$HOME/.mozilla/firefox` (native legacy)
3. `$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox` (Flatpak XDG)
4. `$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox` (Flatpak legacy)

Resolve the target profile folder through `profiles.ini`:
- When `profile` is `"default-release"` (default), prefer `[Install*]` `Default=...` if present and matching, then `[Profile*]` where `Name=<profile>` (resolving `IsRelative=1` against the base directory), then fallback to `Default=1`.

### Policy Targets (`_policy_targets`)
From Firefox's `EnterprisePoliciesParent.sys.mjs`, Linux release builds read `policies.json` from `SysConfD/policies/policies.json`:
- **Native Firefox** (`firefox` installed / `/etc/firefox` present): `/etc/firefox/policies/policies.json` (root-owned via `etc_write`/`etc_restore`).
- **System Flatpak** (`org.mozilla.firefox` installed `--system`): `/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/<arch>/stable/policies/policies.json` (root-owned via `etc_write`/`etc_restore`).
- **User Flatpak** (`org.mozilla.firefox` installed `--user`): `${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/extension/org.mozilla.firefox.systemconfig/<arch>/stable/policies/policies.json` (user-owned atomic swap + backup in `$LS_USER_STATE`).

## Profile Configuration

```toml
[firefox]
profile = "default-release"
prefs = "firefox/prefs.json"
search = "firefox/search.json"
containers = "firefox/containers.json"
# handlers = "firefox/handlers.json"
# chrome = "firefox/chrome"
# policies = "firefox/policies.json"
extensions = [
  "uBlock0@raymondhill.net",
  "{446900e4-71c2-419f-a6a7-df9c091e268b}",
]
```

- `extensions`: Validated AMO IDs (`name@domain` or `{uuid}` without `/`, `..`, `-`, control chars). Translated into `ExtensionSettings` entries using `installation_mode = "normal_installed"` and `https://addons.mozilla.org/firefox/downloads/latest/<id>/latest.xpi`.
- `search`: JSON schema matching Firefox `SearchEngines` policy keys (`default`, `default-private`, `remove`, `add`, `prevent-installs`).
- `prefs`: JSON object mapping Firefox preference names to JSON values (`bool`, `int`, `string`), merged directly into `prefs.js` while Firefox is closed. Previous values (or `"absent": true`) are recorded once in `$LS_USER_STATE/firefox.prev.json` and restored on `decal remove firefox`.
- `containers` / `handlers` / `chrome`: Backed up once under `$LS_USER_STATE/firefox-files/` before replacing (symlink-preserving atomic writes via `.decal-new`) and restored on `remove`.

## Stamp (`decal stamp firefox` / `lib/stamp.py firefox`)
- Reads `prefs.js` and keeps only curated non-ephemeral UI/privacy/network/sidebar/newtab/toolbar preference groups (stripping timestamps, telemetry, migration counters, and extension UUID maps).
- Reads `search.json.mozlz4` via a pure-Python `mozLz40\0` LZ4 block decompressor to export `default`, `default-private`, hidden built-ins (`remove`), and user-added engines (`add`) into `firefox/search.json`.
- Exports `containers.json` (when customized beyond Firefox's 4 stock containers or always when non-empty) and `<profile>/chrome/` CSS files (`userChrome.css`, `userContent.css`) if present.
- Reads `extensions.json` to capture `location == "app-profile"`, `type == "extension"`, `active == true` user-installed extensions (excluding default/system add-ons and langpacks).

## Review (`decal review`) & Safety
- `lib/review.py` inspects `[firefox]` (including tagged `[firefox.<tag>]` sections): lists configured extensions (checking `addons.mozilla.org/api/v5/addons/addon/...` when online, flagging unlisted/low-user add-ons), surfaces `policies` / custom `search` download URLs cleanly, and scans bundled `firefox/*` files.
- Mutating `prefs.js` / profile files refuses to run while Firefox is open (`flatpak ps` or `pgrep`), never loses user preferences on `remove`, and respects `--dry-run` with zero disk mutations.
