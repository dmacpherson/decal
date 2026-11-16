#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export DECAL_PLATFORM=fedora

# Mock Flatpak XDG Firefox profile + profiles.ini
FX_BASE="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
FX_PROF="$FX_BASE/abc12345.default-release"
mkdir -p "$FX_PROF"
cat > "$FX_BASE/profiles.ini" <<'EOF'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default-release
IsRelative=1
Path=abc12345.default-release

[InstallTEST]
Default=abc12345.default-release
Locked=1
EOF

# Symlinked prefs.js (dotfiles scenario) & pre-existing user prefs
cat > "$T_TMP/real-prefs.js" <<'EOF'
// Mozilla User Preferences

user_pref("browser.startup.homepage", "https://existing.example");
user_pref("browser.tabs.warnOnClose", false);
user_pref("user.custom.untouched", 42);
EOF
ln -s "$T_TMP/real-prefs.js" "$FX_PROF/prefs.js"
printf '{"version":4,"identities":[{"name":"Personal"}]}\n' > "$FX_PROF/containers.json"

# Stub flatpak (system org.mozilla.firefox present, not currently running) and pgrep (not running)
stub flatpak 'case "$*" in
  "ps --columns=application") echo "" ;;
  "info --system org.mozilla.firefox") exit 0 ;;
  "info --user org.mozilla.firefox") exit 1 ;;
  "--default-arch") echo "x86_64" ;;
esac; exit 1'
stub pgrep 'exit 1'

# Ensure /etc/firefox triggers native target + Flatpak system target exists in $DECAL_ROOT
mkdir -p "$DECAL_ROOT/etc/firefox" "$DECAL_ROOT/var/lib/flatpak/app/org.mozilla.firefox"

P="$T_TMP/profile"
export PROFILE_DIR="$P"
mkdir -p "$P/firefox/chrome"
cat > "$P/firefox/prefs.json" <<'EOF'
{
  "browser.startup.homepage": "https://start.example.org",
  "sidebar.verticalTabs": true,
  "toolkit.legacyUserProfileCustomizations.stylesheets": true
}
EOF
cat > "$P/firefox/search.json" <<'EOF'
{
  "default": "DuckDuckGo",
  "remove": ["Bing", "eBay"],
  "add": [
    {
      "Name": "Kagi",
      "URLTemplate": "https://kagi.com/search?q={searchTerms}",
      "Method": "GET",
      "Alias": "@k"
    }
  ]
}
EOF
cat > "$P/firefox/containers.json" <<'EOF'
{"version": 4, "identities": [{"name": "Work"}, {"name": "Shopping"}]}
EOF
printf '/* hide tab close */\n' > "$P/firefox/chrome/userChrome.css"

cat > "$P/profile.toml" <<'EOF'
[firefox]
profile = "default-release"
prefs = "firefox/prefs.json"
search = "firefox/search.json"
containers = "firefox/containers.json"
chrome = "firefox/chrome"
extensions = ["uBlock0@raymondhill.net", "{446900e4-71c2-419f-a6a7-df9c091e268b}"]
EOF

run_mod() { mod_run firefox "module_$1"; }

# 0. Status before add is not-installed; --dry-run touches nothing
assert_eq "$(run_mod status)" "not-installed" "status before add is not-installed"
LS_DRY_RUN=1 mod_run firefox module_add >/dev/null 2>&1
assert_contains "$(cat "$FX_PROF/prefs.js")" "https://existing.example" "dry-run leaves prefs.js untouched"
assert_nofile "$DECAL_USER_STATE/firefox.prev.json" "dry-run creates no prev file"
assert_nofile "$DECAL_ROOT/etc/firefox/policies/policies.json" "dry-run creates no native policy"
assert_nofile "$DECAL_ROOT/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json" "dry-run creates no flatpak policy"

# 1. Running Firefox refuses mutating prefs
stub pgrep 'exit 0'
out=$(run_mod add 2>&1)
assert_contains "$out" "close Firefox" "running Firefox warns before touching prefs.js"
assert_contains "$(cat "$FX_PROF/prefs.js")" "https://existing.example" "running Firefox keeps prefs.js untouched"
stub pgrep 'exit 1'

# 2. Clean add applies prefs, containers, chrome, search, and extensions to both native and Flatpak policies
run_mod add >/dev/null 2>&1
assert_eq "$(test -L "$FX_PROF/prefs.js" && echo yes || echo no)" "yes" "prefs.js symlink preserved"
assert_contains "$(cat "$FX_PROF/prefs.js")" '"https://start.example.org"' "homepage updated"
assert_contains "$(cat "$FX_PROF/prefs.js")" '"sidebar.verticalTabs", true' "verticalTabs added"
assert_contains "$(cat "$FX_PROF/prefs.js")" '"user.custom.untouched", 42' "unmanaged pref preserved"
assert_contains "$(cat "$FX_PROF/containers.json")" '"Work"' "containers updated"
assert_file "$FX_PROF/chrome/userChrome.css" "userChrome.css installed"

NAT_POL="$DECAL_ROOT/etc/firefox/policies/policies.json"
FP_POL="$DECAL_ROOT/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json"
assert_file "$NAT_POL" "native policies.json written"
assert_file "$FP_POL" "flatpak systemconfig policies.json written"
assert_contains "$(cat "$NAT_POL")" "uBlock0@raymondhill.net" "uBlock extension policy set"
assert_contains "$(cat "$NAT_POL")" "%7B446900e4-71c2-419f-a6a7-df9c091e268b%7D" "UUID extension policy encoded safely"
assert_contains "$(cat "$NAT_POL")" '"Default": "DuckDuckGo"' "search default policy set"
assert_contains "$(cat "$NAT_POL")" '"Name": "Kagi"' "custom search engine policy set"

# 3. Status reports installed, and catches tampering / int-vs-bool type mismatch
assert_eq "$(run_mod status)" "installed" "status after add reports installed"
sed -i 's/"sidebar.verticalTabs", true/"sidebar.verticalTabs", 1/' "$T_TMP/real-prefs.js"
assert_contains "$(run_mod status)" "partial (profile settings not applied)" "status detects bool vs int mismatch"
run_mod add >/dev/null 2>&1
assert_eq "$(run_mod status)" "installed" "re-add repairs tampered pref"

# 4. Tags & drop (remove --only dev takes away only dev's extension)
cat >> "$P/profile.toml" <<'EOF'

[firefox.dev]
extensions = ["jid1-MnnxcxisBPnSXQ@jetpack"]
EOF
DECAL_TAGS=dev run_mod add >/dev/null 2>&1
assert_contains "$(cat "$NAT_POL")" "jid1-MnnxcxisBPnSXQ@jetpack" "tag extension added"
DECAL_DROP=dev mod_run firefox module_drop >/dev/null 2>&1
assert_not_contains "$(cat "$NAT_POL")" "jid1-MnnxcxisBPnSXQ@jetpack" "drop removes tag extension"
assert_contains "$(cat "$NAT_POL")" "uBlock0@raymondhill.net" "drop keeps base extension"

# 5. Dry-run remove leaves everything intact
LS_DRY_RUN=1 mod_run firefox module_remove >/dev/null 2>&1
assert_file "$NAT_POL" "dry-run remove keeps policies.json"
assert_contains "$(cat "$FX_PROF/prefs.js")" "sidebar.verticalTabs" "dry-run remove keeps prefs.js"

# 6. Full remove restores exact prior state cleanly
run_mod remove >/dev/null 2>&1
assert_contains "$(cat "$FX_PROF/prefs.js")" '"https://existing.example"' "homepage restored"
assert_not_contains "$(cat "$FX_PROF/prefs.js")" "sidebar.verticalTabs" "added pref removed"
assert_contains "$(cat "$FX_PROF/prefs.js")" '"user.custom.untouched", 42' "unmanaged pref untouched after remove"
assert_contains "$(cat "$FX_PROF/containers.json")" '"Personal"' "prior containers restored"
assert_nofile "$FX_PROF/chrome/userChrome.css" "installed userChrome.css removed"
assert_nofile "$NAT_POL" "native policies.json removed"
assert_nofile "$FP_POL" "flatpak policies.json removed"
assert_nofile "$DECAL_USER_STATE/firefox.prev.json" "prev record cleared"

# 7. Security: reject bad extension ID
P_BAD="$T_TMP/badprof"; mkdir -p "$P_BAD"
cat > "$P_BAD/profile.toml" <<'EOF'
[firefox]
extensions = ["../bad-id"]
EOF
bad_rc=0
PROFILE_DIR="$P_BAD" mod_run firefox module_add >/dev/null 2>&1 || bad_rc=$?
assert_eq "$(( bad_rc != 0 ))" "1" "malicious extension id rejected"

t_done
