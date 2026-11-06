# Profile review implementation plan (Part 2b)

Implementation plan for Part 2b of the roadmap: `decal review <profile>` and trust prompt review.

## Tasks

### Task 1: `lib/review.py` core analyzer and data collection
- Parse `profile.toml` in given profile directory (using Python stdlib).
- Collect:
  - Flatpaks (`[apps] flatpaks`)
  - GNOME extensions (`[gnome-extensions] enable`)
  - Homebrew formulas (`[terminal] brew`)
  - Distro packages (`[apps] packages`, `[apps] remove-packages`, `[tools] install`, `[vpn] install`)
  - Remote URLs from sources (`[wallpaper] file`, `[icons] source`, `[gtk-theme] source`, `[plymouth] source`, `[terminal] nerd-font-source`, `[terminal] autosuggest-source`, etc.)
  - Bundled files in profile directory (excluding `profile.toml`, `README*`, `.git`, `.decal-*`).

### Task 2: Flathub & GNOME extensions check logic
- Flathub verification and stats API:
  - Summary / existence: `https://flathub.org/api/v2/summary/<app_id>`
  - Verification: `https://flathub.org/api/v2/verification/<app_id>/status`
  - Stats: `https://flathub.org/api/v2/stats/<app_id>`
  - Flags: `unlisted` (404), `unverified`, `few installs` (< 100).
- GNOME extensions API:
  - Info: `https://extensions.gnome.org/extension-info/?uuid=<uuid>`
  - Downloads: flag if < 100.
  - Compatibility: check `shell_version_map` against target GNOME version (if provided).
  - Timeout: 2.0s per request, fail open (indicate `(check skipped)` if offline or error).

### Task 3: URL & Profile file security checks
- URL heuristics:
  - Flag if `http://` (insecure protocol).
  - Flag if host is an IPv4 or IPv6 address.
  - Flag if URL shortener (`bit.ly`, `tinyurl.com`, `t.co`, `is.gd`, `buff.ly`, `ow.ly`).
  - Flag if domain is unrecognized or suspicious.
- File checks:
  - Executable bit (`mode & 0o111`).
  - File extension indicating script or binary (`.sh`, `.bash`, `.py`, `.bin`, `.elf`, `.exe`).
  - Starts with shebang `#!`.
  - File size > 10 MB.

### Task 4: CLI command & output formatting
- `lib/review.py <profile_dir> [--json] [--shell-version V] [--offline]`
- CLI entry in `decal`:
  - `review) stage_profile "$1"; python3 "$LS_REPO/lib/review.py" "$STAGE_DIR" ...`
- Update `trust()` in `lib/stage.sh`:
  - Add `r` option to prompt: `p preview commands · r review profile · y %s it · n stop [r]:`
  - When `r` is entered, calls `python3 "$LS_REPO/lib/review.py" "$STAGE_DIR"`.

### Task 5: Hermetic test suite
- `tests/test_review.sh`:
  - Test profile parsing and grouping.
  - Test Flathub check with mocked urllib responses (verified, unverified, unlisted, low install count).
  - Test GNOME extensions check with mocked responses (compatible, incompatible shell version, unlisted, low download count).
  - Test Homebrew core vs third-party tap detection.
  - Test Distro packages listing (installs vs removals).
  - Test URL checks (http, IP, shortener).
  - Test bundled file checks (executable script, shebang, large file).
  - Test CLI `decal review <profile>` and `decal review <profile> --json`.
  - Test `trust()` prompt handling of `r`.

### Task 6: Documentation update
- Update `README.md` and `docs/design/2026-10-04-usb-feature-roadmap.md` marking Part 2b done.
