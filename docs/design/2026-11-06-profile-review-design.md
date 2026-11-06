# Profile review (Part 2b)

A "What this profile will do" inspection screen and command (`decal review PROFILE`), giving a complete, grouped preview of everything a profile will install, download, or execute, with flags wherever a trust signal is weak.

## Goal

When inspecting any profile—or before applying an untrusted profile (from someone else's GitHub, a shared URL, or an untrusted USB stick)—the user can see at a glance:
- **Flatpaks**: Name, ID, verified status on Flathub, total installs. Flagged if not on Flathub, unverified publisher, or very few installs (< 100).
- **GNOME extensions**: UUID, name, download count on extensions.gnome.org, and compatibility with the system's GNOME version. Flagged if not on extensions.gnome.org (e.g. git URL), or incompatible with the current GNOME version.
- **Homebrew formulas**: Grouped into core formulas vs third-party taps. Flagged if using a third-party tap (`user/tap/formula`).
- **Native packages**: Listed by distro package name (installs vs removals).
- **Remote downloads & URLs**: Wallpaper, icons, fonts, Plymouth splash, or tool installers. Flagged if using insecure `http://`, raw IP addresses, URL shorteners, or unknown hosts.
- **Bundled files**: All extra files in the profile directory. Flagged if executable, scripts/binaries, or unusually large (> 10 MB).

Honest limit: This catches common risks and mistakes; the "not yours" trust check remains the primary protection. Information is presented clearly; it never blocks an action if the user explicitly confirms (`--yes` or typing `y`).

## CLI Interface

```bash
decal review [PROFILE]          # reviews PROFILE (or active profile if omitted)
decal review [PROFILE] --json   # machine-readable JSON summary
```

When `trust()` asks about an untrusted profile in `lib/stage.sh`:
```
p preview commands · r review profile · y apply it · n stop [r]:
```
Pressing `r` prints the review summary before prompting again.

## Output Format

The output is clean, readable, grouped by category:

```
Profile review: dmacpherson/work (18 items)

Flatpaks (Flathub):
  ✓ com.brave.Browser          Brave Browser (verified · 2.4M installs)
  ! com.unverified.app         Unverified App (unverified · 12 installs) [few installs, unverified]
  ? com.unknown.random         not found on Flathub [unlisted]

GNOME extensions:
  ✓ dash-to-dock@micxgx...     Dash to Dock (12.4M downloads · compatible GNOME 46)
  ! obscure@example.com        Obscure Ext (42 downloads) [few downloads]

Homebrew formulas:
  ✓ starship, fzf, ripgrep     core formulas
  ! evil/tap/custom            third-party tap: evil/tap

Native packages:
  + dnf: ripgrep, bat
  - dnf remove: nano

Remote downloads:
  ✓ https://github.com/.../releases/... (GitHub)
  ! http://192.168.1.10/theme.tar.gz [insecure http, bare IP]

Files in profile:
  ✓ wallpapers/autumn.jpg      image (2.4 MB)
  ! scripts/setup.sh           executable script (4.2 KB) [executable]

Flags: 4 warnings found across 18 items.
```

## Architecture

1. `lib/review.py`: Pure Python module (Python 3 stdlib only).
   - `inspect_profile(profile_dir, current_gnome_version=None, offline=False)`:
     Reads `profile.toml`, parses all module settings, scans profile files.
   - Evaluates trust signals for each item.
   - Outputs human-readable terminal format or `--json`.
2. Stubs & Offline handling:
   - When offline or if network API calls fail/timeout (2s timeout), falls back gracefully with a note `(network check unavailable)`.
   - In tests, HTTP requests are stubbed via standard unittest/fixture mocking.
3. `decal review`:
   - Added to command switch in `decal`.
4. `trust()` integration in `lib/stage.sh`:
   - Prompts with `[r]` default: offers review in addition to preview.
