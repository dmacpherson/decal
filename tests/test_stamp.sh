#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
stub gh 'exit 1'; unset DISPLAY WAYLAND_DISPLAY
# decal stamp: the runner (modules' stamps, the profile's own sections, saving, -dr, -gh) with fixture modules,
# then lib/stamp.py's readers against an isolated dconf, Brave files and the apps module with stubbed tools
M="$T_TMP/mods"; mkdir -p "$M"
mk() {  # mk NAME SCHEMA BODY : a fixture module
  mkdir -p "$M/$1"; echo "$2" > "$M/$1/schema.json"
  printf 'MODULE_DESC="stamp fixture %s"\nmodule_add() { :; }\nmodule_remove() { :; }\n%s\n' "$1" "$3" > "$M/$1/module.sh"
}
mk live '{"keys": {"word": {"type": "string", "default": "x"}, "pic": {"type": "path", "default": ""}}}' '
module_status() { echo installed; }
STAMP_LIVE=1
module_stamp() { echo me > "$T_TMP/pic.png"; stamp_note "live: a word and a picture"
  printf "[live]\nword = \"captured\"\npic = \"%s\"\n" "$(stamp_copy "$T_TMP/pic.png" live/pic.png)"; }'
mk mine '{"keys": {"file": {"type": "path"}, "size": {"type": "int", "default": 1}}, "required": ["file"]}' '
module_status() { echo installed; }
module_stamp() { echo live > "$T_TMP/live.txt"; printf "[mine]\nfile = \"%s\"\n" "$(stamp_copy "$T_TMP/live.txt" mine/live.txt)"; }'
mk skipped '{"keys": {}}' 'module_status() { echo installed; }
STAMP_SKIP=1
module_stamp() { echo "[skipped]"; }'
mk broken '{"keys": {}}' 'module_status() { echo installed; }
module_stamp() { echo "not toml at all"; return 3; }'
mk quiet '{"keys": {}}' 'module_status() { echo not-installed; }'
export T_TMP DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora USER=tester
P="$T_TMP/prof"; mkdir -p "$P/files"; echo data > "$P/files/mine.txt"
printf '[mine]\nfile = "files/mine.txt"\n[mine.dev]\nsize = 5\n' > "$P/profile.toml"
export DECAL_PROFILE="$P" PROFILE_DIR="$P"
S="$REPO/decal"
mkdir -p "$DECAL_USER_STATE/applied"; echo x > "$DECAL_USER_STATE/applied/mine"   # decal applied [mine]
x() { rm -rf "$T_TMP/x"; mkdir -p "$T_TMP/x"; tar -xzf "$1" -C "$T_TMP/x"; }

out=$("$S" stamp -dr 2>&1); assert_eq "$?" "0" "-dr rc"
assert_contains "$out" "live: a word and a picture" "-dr: what's in it"
assert_contains "$out" 'word = "captured"' "-dr: shows the profile"
assert_contains "$out" "stamp broken: " "a module whose stamp fails: warned, left out"
assert_not_contains "$out" "[skipped]" "STAMP_SKIP: never stamped"
assert_nofile "$HOME/decal-tester.tar.gz" "-dr: nothing saved"
out=$("$S" --dry-run stamp 2>&1); assert_contains "$out" "dry run: nothing saved" "--dry-run before the command works too"

"$S" stamp >/dev/null 2>&1; assert_eq "$?" "0" "stamp rc"
assert_file "$HOME/decal-tester.tar.gz" "default: ~/decal-USER.tar.gz"
x "$HOME/decal-tester.tar.gz"
assert_contains "$(cat "$T_TMP/x/profile.toml")" "[mine.dev]" "a module decal set up: your profile's section, tags kept"
assert_eq "$(cat "$T_TMP/x/files/mine.txt")" "data" "...with the files it points to"
assert_not_contains "$(cat "$T_TMP/x/profile.toml")" "mine/live.txt" "...not the live capture"
assert_eq "$(cat "$T_TMP/x/live/pic.png")" "me" "a live module's files"
assert_contains "$(cat "$T_TMP/x/README.md")" "decal-tester.tar.gz" "README: how to apply it"
assert_eq "$(DECAL_TAGS=all python3 "$REPO/lib/profile.py" check --profile "$T_TMP/x" --modules "$M" 2>&1; echo $?)" "0" "the stamp is a valid profile"
"$S" stamp >/dev/null 2>&1; assert_file "$HOME/decal-tester.tar.gz.old" "stamping again keeps the previous one as .old"
rm "$DECAL_USER_STATE/applied/mine"
"$S" stamp "$T_TMP/out/my.tgz" >/dev/null 2>&1; x "$T_TMP/out/my.tgz"
assert_contains "$(cat "$T_TMP/x/profile.toml")" 'file = "mine/live.txt"' "not applied by decal: the live capture"
"$S" stamp "$T_TMP/folder" >/dev/null 2>&1; assert_file "$T_TMP/folder/profile.toml" "a folder path: written as a folder"
"$S" stamp "$T_TMP/folder" >/dev/null 2>&1; assert_eq "$?" "0" "...and replaced by the next stamp"
mkdir -p "$T_TMP/notmine"; echo keep > "$T_TMP/notmine/f"
out=$("$S" stamp "$T_TMP/notmine" 2>&1); assert_eq "$?" "1" "a folder that isn't a stamp: refused"; assert_eq "$(cat "$T_TMP/notmine/f")" "keep" "...untouched"
# a module printing something that isn't a valid profile: nothing saved
cp "$M/live/module.sh" "$T_TMP/live.bak"; echo 'module_stamp() { printf "[live]\nnope = 1\n"; }' >> "$M/live/module.sh"; rm -f "$HOME/decal-tester.tar.gz"*
out=$("$S" stamp 2>&1); assert_eq "$?" "1" "an invalid stamp: fails"; assert_nofile "$HOME/decal-tester.tar.gz" "...and saves nothing"
cp "$T_TMP/live.bak" "$M/live/module.sh"

# decal stamp MODULE...: just those
"$S" stamp live "$T_TMP/only.tgz" >/dev/null 2>&1; x "$T_TMP/only.tgz"
assert_contains "$(cat "$T_TMP/x/profile.toml")" "[live]" "stamp MODULE: that module"; assert_not_contains "$(cat "$T_TMP/x/profile.toml")" "[mine]" "...and no other"
# -gh: a fake GitHub (localhost); the repo is created private, each stamp a commit; the token never on a command line
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
out=$(GITHUB_TOKEN=s3cret "$S" stamp -gh 2>&1); assert_eq "$?" "0" "-gh rc"
assert_contains "$out" "created private repo tester/decal-tester" "repo created, private"
assert_contains "$out" "github:tester/decal-tester" "prints the one-liner for the next machine"
J="$G/tester_decal-tester.json"
assert_contains "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["files"]))' "$J")" "'profile.toml'" "the stamp is in the repo"
assert_contains "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"]["README.md"])' "$J")" "github:tester/decal-tester" "README: apply from GitHub"
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$J")" "True" "private"
GITHUB_TOKEN=s3cret "$S" stamp --github >/dev/null 2>&1
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commits"])' "$J")" "3" "stamping again: one more commit"
GITHUB_TOKEN=s3cret "$S" stamp -gh tester/elsewhere --public >/dev/null 2>&1
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$G/tester_elsewhere.json")" "False" "-gh OWNER/NAME --public"
assert_file "$HOME/decal-tester.tar.gz" "-gh saves the file too"
out=$(GITHUB_TOKEN=wrong setsid -w "$S" stamp -gh 2>&1 < /dev/null); assert_eq "$?" "1" "a bad token: fails"
assert_contains "$out" "the token needs permission" "...and says what the token needs"
assert_contains "$out" "GitHub didn't accept the token" "...before doing anything"
assert_not_contains "$(ps -eo args)" "s3cret" "token not on any command line"
# no key: stamp -gh signs in with Decal Profile Write (a repo that doesn't exist yet is fine), the key used for this run only
echo ok > "$G/device_script"; : > "$G/device_log"; printf '1\n' > "$T_TMP/keys"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_GITHUB="$DECAL_GITHUB_API" DECAL_GITHUB_APP_WRITE=Iv-write:decal-write \
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$S" stamp -gh tester/signed-in 2>&1)
assert_eq "$?" "0" "stamp -gh without a key: signed in"
assert_contains "$(cat "$G/device_log")" "code client_id=Iv-write" "with the write app"
assert_file "$G/tester_signed-in.json" "the stamp is on GitHub"
assert_contains "$(cat "$T_TMP/screen")" "so decal can save to tester/signed-in" "says what the key is for"
# a key that's already set but doesn't work: checked before the work, explained, then sign in instead
echo ok > "$G/device_script"; : > "$G/device_log"; printf '1\n' > "$T_TMP/keys"
out=$(env -u GH_TOKEN GITHUB_TOKEN=wrong DECAL_GITHUB="$DECAL_GITHUB_API" DECAL_GITHUB_APP_WRITE=Iv-write:decal-write \
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$S" stamp -gh tester/second 2>&1)
assert_eq "$?" "0" "a key that doesn't work: signed in instead"
assert_contains "$out" "GitHub didn't accept that key" "...after saying what's wrong with it"
assert_file "$G/tester_second.json" "...and the stamp is on GitHub"
kill "$GHPID" 2>/dev/null

# lib/stamp.py dconf: only keys you changed, differing from the distro's and the schema's defaults, in the
# areas worth carrying (isolated dconf: a user db plus a compiled "distro" db)
mkdir -p "$T_TMP/cfg" "$T_TMP/db/distro.d"
printf '[org/gnome/desktop/interface]\nclock-format='"'"'24h'"'"'\n' > "$T_TMP/db/distro.d/00-distro"
dconf compile "$T_TMP/db/distro" "$T_TMP/db/distro.d"
printf 'user-db:user\nfile-db:%s\n' "$T_TMP/db/distro" > "$T_TMP/dprofile"
export XDG_CONFIG_HOME="$T_TMP/cfg" DCONF_PROFILE="$T_TMP/dprofile"
body() {
  dconf write /org/gnome/desktop/interface/accent-color "'pink'"            # yours
  dconf write /org/gnome/desktop/interface/clock-format "'24h'"             # = the distro's
  dconf write /org/gnome/desktop/interface/enable-animations "true"         # = the schema's
  dconf write /org/gnome/desktop/interface/cursor-theme "'Mine'"            # the cursor module's
  dconf write /org/gnome/desktop/wm/preferences/button-layout "'close:'"    # yours, a sub-area
  dconf write /org/gnome/shell/command-history "['ls']"                    # history
  dconf write /org/gnome/desktop/background/picture-uri "'file:///x.jpg'"  # the wallpaper module's
  dconf write /org/example/other/key "'x'"                                  # not an area decal carries
  python3 "$REPO/lib/stamp.py" dconf --out "$T_TMP/s.ini"
}
export -f body; export REPO
n=$(dbus-run-session -- bash -c body 2>/dev/null)
assert_eq "$n" "2" "two settings differ from default"
I=$(cat "$T_TMP/s.ini")
assert_contains "$I" "accent-color='pink'" "yours: in"; assert_contains "$I" "button-layout='close:'" "a sub-area: in"
assert_not_contains "$I" "clock-format" "the distro's value: out"; assert_not_contains "$I" "enable-animations" "the schema default: out"
assert_not_contains "$I" "cursor-theme" "another module's key: out"; assert_not_contains "$I" "command-history" "history: out"
assert_not_contains "$I" "picture-uri" "wallpaper: out"; assert_not_contains "$I" "org/example" "other areas: out"

# lib/stamp.py section: tags and files of a profile section, files outside the profile under files/
mkdir -p "$T_TMP/sp/pics" "$T_TMP/out2"; echo a > "$T_TMP/sp/pics/a.png"; echo b > "$T_TMP/elsewhere.png"
printf '[live]\nword = "w"\npic = "pics/a.png"\n[live.dev]\npic = "%s"\n' "$T_TMP/elsewhere.png" > "$T_TMP/sp/profile.toml"
sec=$(python3 "$REPO/lib/stamp.py" section live --profile "$T_TMP/sp" --modules "$M" --to "$T_TMP/out2")
assert_eq "$sec" '[live]
word = "w"
pic = "pics/a.png"
[live.dev]
pic = "files/elsewhere.png"' "section: as written, tags included, paths into the stamp"
assert_eq "$(cat "$T_TMP/out2/pics/a.png")$(cat "$T_TMP/out2/files/elsewhere.png")" "ab" "...files copied"

# Brave: known settings without bookkeeping, Origin, Web Store extensions (not the built-in ones)
B="$T_TMP/brave"; mkdir -p "$B"
cat > "$B/Preferences" <<'EOF'
{"brave": {"new_tab_page": {"show_clock": true, "shows_count": 4}, "stats": {"x": 1}},
 "session": {"restore_on_startup": 5}, "window_placement": {"x": 3},
 "extensions": {"settings": {
   "nngceckbapebfimnlniiiahkandclblb": {"from_webstore": true, "location": 1},
   "mhjfbmdgcfjbbpaeojofohoefgiehjai": {"from_webstore": false, "location": 5},
   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {"from_webstore": true, "location": 1, "was_installed_by_default": true}}}}
EOF
echo '{"brave": {"origin": {"free_tier_accepted": true, "purchase_validated": false}}}' > "$B/Local State"
out=$(python3 "$REPO/lib/stamp.py" brave --prefs "$B/Preferences" --local-state "$B/Local State" --to "$T_TMP/bs" 2>/dev/null)
assert_contains "$out" 'extensions = ["nngceckbapebfimnlniiiahkandclblb"]' "brave: only extensions you added from the Web Store"
assert_eq "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$T_TMP/bs/brave/preferences.json")" \
  '{"brave": {"new_tab_page": {"show_clock": true}}, "session": {"restore_on_startup": 5}}' "brave: known settings only, no counters or state"
assert_eq "$(cat "$T_TMP/bs/brave/local-state.json" | tr -d ' \n')" '{"brave":{"origin":{"free_tier_accepted":true}}}' "brave: Origin"

# apps: flatpak history (installed since, still here; the distro's you removed), layered packages, default apps
export DECAL_MODULES_DIR="$REPO/modules"
stub flatpak 'case "$*" in
  "list --app --columns=application") printf "com.discordapp.Discord\norg.gnome.Calculator\n";;
  "history --columns=change,application") printf "deploy install\tcom.discordapp.Discord\ndeploy install\tdev.gone.App\nuninstall\tdev.gone.App\nuninstall\torg.mozilla.firefox\nuninstall\torg.mozilla.firefox.Locale\ndeploy update\torg.gnome.Calculator\n";;
esac'
stub rpm-ostree 'echo "{\"deployments\": [{\"requested-packages\": [\"htop\", \"moby-engine\"], \"requested-local-packages\": [\"decal-plymouth-1\"], \"requested-base-removals\": [\"firefox\"]}]}"'
mkdir -p "$XDG_CONFIG_HOME"; printf '[Default Applications]\nx-scheme-handler/http=com.brave.Browser.desktop\nx-scheme-handler/https=com.brave.Browser.desktop\ntext/html=com.brave.Browser.desktop;firefox.desktop\napplication/pdf=org.gnome.Papers.desktop\n' > "$XDG_CONFIG_HOME/mimeapps.list"
mkdir -p "$T_TMP/as"; : > "$T_TMP/an"
out=$(STAMP_DIR="$T_TMP/as" STAMP_NOTES="$T_TMP/an" mod_run apps module_stamp 2>&1)
assert_contains "$out" 'flatpaks = ["com.discordapp.Discord"]' "apps: installed since the OS install, still here"
assert_contains "$out" 'remove-flatpaks = ["org.mozilla.firefox"]' "apps: the distro's you removed (not add-ons, not ones you installed and removed)"
assert_contains "$out" 'packages = ["htop"]' "apps: layered packages (not ones other modules own, not decal's)"
assert_contains "$out" 'remove-packages = ["firefox"]' "apps: base packages removed"
assert_contains "$out" 'browser = "com.brave.Browser"' "apps: default browser"; assert_contains "$out" 'pdf = "org.gnome.Papers"' "apps: default pdf viewer"
t_done
