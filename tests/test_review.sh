#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export PYTHONPATH="$REPO"

P="$T_TMP/profile"
mkdir -p "$P"

# Helper to create a fake urllib mock script for Python
cat > "$T_TMP/mock_review.py" <<'EOF'
import sys, unittest.mock as mock, urllib.error, urllib.parse
import lib.review as review

def fake_urlopen(req, timeout=2.0):
    raw_url = req.full_url if hasattr(req, "full_url") else req
    url = urllib.parse.unquote(raw_url)
    # Flathub endpoints
    if "flathub.org/api/v2/summary/org.good.App" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"name": "Good App"}'
        m.__enter__.return_value = m
        return m
    if "flathub.org/api/v2/verification/org.good.App/status" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"verified": true}'
        m.__enter__.return_value = m
        return m
    if "flathub.org/api/v2/stats/org.good.App" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"installs_total": 50000}'
        m.__enter__.return_value = m
        return m

    if "flathub.org/api/v2/summary/org.sketchy.App" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"name": "Sketchy App"}'
        m.__enter__.return_value = m
        return m
    if "flathub.org/api/v2/verification/org.sketchy.App/status" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"verified": false}'
        m.__enter__.return_value = m
        return m
    if "flathub.org/api/v2/stats/org.sketchy.App" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"installs_total": 12}'
        m.__enter__.return_value = m
        return m

    if "flathub.org/api/v2/summary/org.missing.App" in url:
        raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)

    # GNOME Extensions endpoints
    if "extensions.gnome.org" in url and "good@example.com" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"name": "Good Ext", "downloads": 5000, "shell_version_map": {"46": {"version": 1}}}'
        m.__enter__.return_value = m
        return m
    if "extensions.gnome.org" in url and "incompatible@example.com" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"name": "Old Ext", "downloads": 5000, "shell_version_map": {"42": {"version": 1}}}'
        m.__enter__.return_value = m
        return m
    if "extensions.gnome.org" in url and "unpopular@example.com" in url:
        m = mock.MagicMock()
        m.status = 200
        m.read.return_value = b'{"name": "Unpopular Ext", "downloads": 5, "shell_version_map": {"46": {"version": 1}}}'
        m.__enter__.return_value = m
        return m
    if "extensions.gnome.org" in url and "missing@example.com" in url:
        raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)

    raise urllib.error.URLError("Network unreachable")

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    review.main()
EOF

# 1. Clean profile with good flatpak, good extension, core brew, known url, normal file
cat > "$P/profile.toml" <<'EOF'
[apps]
flatpaks = ["org.good.App"]
packages = ["curl"]
remove-packages = ["nano"]

[gnome-extensions]
enable = ["good@example.com"]

[terminal]
brew = ["ripgrep"]

[wallpaper]
image = "https://github.com/dmacpherson/decal/releases/download/v0.4.0/bg.jpg"
EOF

echo "normal text content" > "$P/notes.txt"

out=$(python3 "$T_TMP/mock_review.py" "$P" --shell-version 46)
assert_contains "$out" "Profile review: profile" "header printed"
assert_contains "$out" "org.good.App" "good app listed"
assert_contains "$out" "verified" "good app verified"
assert_contains "$out" "50.0k installs" "good app installs"
assert_contains "$out" "good@example.com" "good ext listed"
assert_contains "$out" "compatible" "good ext compatible"
assert_contains "$out" "core formula" "core brew formula identified"
assert_contains "$out" "install: curl" "native install listed"
assert_contains "$out" "remove:  nano" "native remove listed"
assert_contains "$out" "notes.txt" "profile file listed"
assert_contains "$out" "All 7 items clean" "no flags raised on clean profile"

# JSON output
json_out=$(python3 "$T_TMP/mock_review.py" "$P" --json --shell-version 46)
assert_contains "$json_out" '"total_flags": 0' "json clean total_flags"
assert_contains "$json_out" '"verified": true' "json verified flag"

# 2. Suspicious profile raising various flags
P_BAD="$T_TMP/bad_profile"
mkdir -p "$P_BAD"
cat > "$P_BAD/profile.toml" <<'EOF'
[apps]
flatpaks = ["org.sketchy.App", "org.missing.App"]

[gnome-extensions]
enable = ["incompatible@example.com", "unpopular@example.com", "missing@example.com"]

[terminal]
brew = ["baduser/badtap/customtool"]

[wallpaper]
image = "http://192.168.1.50/wallpaper.png"
desktop.image = "https://bit.ly/secret-theme"

[icons]
source = "https://untrusted-host-site.xyz/icons.tar.gz"
theme = "Test"
EOF

# Suspicious files:
# 1. Executable file
touch "$P_BAD/payload"
chmod +x "$P_BAD/payload"

# 2. Script with shebang
cat > "$P_BAD/runner.dat" <<'EOF'
#!/bin/bash
echo evil
EOF

# 3. Large file (simulate > 10MB using truncate)
truncate -s 11M "$P_BAD/huge.dat"

bad_out=$(python3 "$T_TMP/mock_review.py" "$P_BAD" --shell-version 46)

# Verify Flatpak flags
assert_contains "$bad_out" "unverified publisher" "sketchy flatpak unverified"
assert_contains "$bad_out" "few installs" "sketchy flatpak few installs"
assert_contains "$bad_out" "unlisted on Flathub" "missing flatpak unlisted"

# Verify GNOME extension flags
assert_contains "$bad_out" "not updated for GNOME 46" "incompatible extension flagged"
assert_contains "$bad_out" "few downloads" "unpopular extension few downloads"
assert_contains "$bad_out" "not on extensions.gnome.org" "missing extension flagged"

# Verify Homebrew third-party tap flag
assert_contains "$bad_out" "third-party tap (baduser/badtap)" "tap flagged"

# Verify URL flags
assert_contains "$bad_out" "insecure http://" "http flagged"
assert_contains "$bad_out" "bare IP address (192.168.1.50)" "bare IP flagged"
assert_contains "$bad_out" "URL shortener (bit.ly)" "shortener flagged"
assert_contains "$bad_out" "unrecognized host (untrusted-host-site.xyz)" "unknown host flagged"

# Verify File flags
assert_contains "$bad_out" "executable" "executable file flagged"
assert_contains "$bad_out" "script/binary" "shebang file flagged"
assert_contains "$bad_out" "large file (11.0 MB)" "large file flagged"

# Overall flags total
assert_contains "$bad_out" "Flags: 14 warnings found" "expected flag count"

# 3. CLI decal review command
# Create a local profile and review via ./decal review
cli_out=$("$REPO/decal" review "$P" --offline)
assert_contains "$cli_out" "Profile review: profile" "decal review prints review"
assert_contains "$cli_out" "ripgrep" "decal review lists profile items"

# decal review --json
cli_json=$("$REPO/decal" review "$P" --json --offline)
assert_contains "$cli_json" '"formula": "ripgrep"' "decal review --json works"

# 4. Review active profile when no profile argument provided
cli_active=$(DECAL_PROFILE="$P" "$REPO/decal" review --offline)
assert_contains "$cli_active" "Profile review: profile" "decal review default to active profile"

# 5. Test trust prompt 'r' option
export DECAL_TTY_IN="$T_TMP/tty_in"
export DECAL_TTY_OUT="$T_TMP/tty_out"
printf 'r\ny\n' > "$DECAL_TTY_IN"
: > "$DECAL_TTY_OUT"

sub_out=$(
  set -euo pipefail
  source "$REPO/lib/common.sh"
  LS_REPO="$REPO"
  STAGE_DIR="$P_BAD"
  source "$REPO/lib/stage.sh"
  trust "github:stranger/sketchy" apply 2>&1
)

prompt_out=$(cat "$DECAL_TTY_OUT")
assert_contains "$prompt_out" "r review what it installs · p preview commands" "prompt offers review option"
assert_contains "$sub_out" "third-party tap (baduser/badtap)" "review displayed upon entering r"

t_done
