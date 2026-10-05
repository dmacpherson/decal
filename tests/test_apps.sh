#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_CONFIG_HOME="$T_TMP/home/.config"
export XDG_DATA_DIRS="$T_TMP/share" XDG_DATA_HOME="$T_TMP/home/.local/share"; mkdir -p "$T_TMP/share/applications" "$XDG_CONFIG_HOME"
for d in com.brave.Browser org.gnome.TextEditor; do : > "$T_TMP/share/applications/$d.desktop"; done
stub rpm 'exit 0'; stub dnf   # never reach the real package manager
# Brave (default) installed; Discord (listed) not; Loupe (a default we add below) is on Flathub but not installed
stub flatpak 'case "$*" in "info --system -- com.brave.Browser") exit 0;; "info --system -- "*) exit 1;; "remote-info --system -- flathub org.gnome.Loupe") exit 0;; "remote-info "*) exit 1;; esac; exit 0'
printf 'x-scheme-handler/http=org.mozilla.firefox.desktop\ntext/html=org.mozilla.firefox.desktop\n' > "$STUBS/mime.db"
stub xdg-mime 'db="$STUBS/mime.db"; case $1 in query) grep "^$3=" "$db" | cut -d= -f2;; default) d=$2; shift 2; for m; do grep -v "^$m=" "$db" > "$db.t"; mv "$db.t" "$db"; echo "$m=$d" >> "$db"; done;; esac'
stub xdg-settings
printf '[Default Applications]\ntext/markdown=org.gnome.TextEditor.desktop\napplication/x-unrelated=keep.desktop\n' > "$XDG_CONFIG_HOME/mimeapps.list"
mkdir -p "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
echo '{"brave":{"origin":{"free_tier_accepted":false}}}' > "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Local State"
sed -i 's/^text-editor = "org.gnome.TextEditor"$/&\nimages = "org.gnome.Loupe"\nmusic = "org.example.NotOnFlathub"/' "$PROFILE_DIR/profile.toml"   # into [apps.defaults]
run_mod() { mod_run apps "module_$1"; }
assert_eq "$(run_mod status)" "not-installed (defaults: not set; Brave Origin: no)" "only listed flatpaks count; Discord missing"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add rc"
assert_contains "$(calls)" "flatpak remote-add --system --if-not-exists -- flathub https://dl.flathub.org/repo/flathub.flatpakrepo" "remote from profile defaults"
assert_contains "$(calls)" "flatpak install --system --noninteractive -y -- flathub com.discordapp.Discord" "listed flatpak installed"
assert_contains "$(calls)" "flatpak install --system --noninteractive -y -- flathub org.gnome.Loupe" "missing default app installed from Flathub"
assert_not_contains "$(calls)" "flathub com.brave.Browser" "installed default not reinstalled"
assert_contains "$out" "org.example.NotOnFlathub is not installed and not on flathub" "unavailable default skipped with warning"
assert_contains "$(cat "$STUBS/mime.db")" "x-scheme-handler/https=com.brave.Browser.desktop" "brave is browser"
assert_contains "$(cat "$STUBS/mime.db")" "image/png=org.gnome.Loupe.desktop" "images role set"
assert_contains "$(calls)" "xdg-settings set default-web-browser com.brave.Browser.desktop" "xdg-settings"
assert_contains "$out" "Brave Origin" "origin reminder when Brave is used and not converted"
assert_eq "$(sort "$DECAL_STATE/apps/managed" | tr '\n' ' ')" "com.discordapp.Discord org.gnome.Loupe " "managed = listed + auto-installed"
# unwanted software: contradictions rejected, removals recorded and undone
sed -i 's/^flatpaks = \["com.discordapp.Discord"\]$/&\nremove-flatpaks = ["com.discordapp.Discord"]/' "$PROFILE_DIR/profile.toml"
out=$(run_mod add 2>&1); assert_eq "$?" "1" "contradiction rc"; assert_contains "$out" "both in flatpaks and remove-flatpaks" "contradiction message"
sed -i 's/^remove-flatpaks = \["com.discordapp.Discord"\]$/remove-flatpaks = ["org.mozilla.firefox"]\nremove-packages = ["firefox"]/' "$PROFILE_DIR/profile.toml"
stub flatpak 'case "$*" in "info --system -- com.brave.Browser"|"info --system -- org.mozilla.firefox") exit 0;; "info --system --show-origin -- org.mozilla.firefox") echo flathub;; "info --system -- "*) exit 1;; "remote-info --system -- flathub org.gnome.Loupe") exit 0;; "remote-info "*) exit 1;; esac; exit 0'
stub rpm 'case "$*" in "-q --quiet firefox") exit 0;; "-e --test firefox") exit 0;; esac; exit 0'
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "flatpak uninstall --system --noninteractive -y -- org.mozilla.firefox" "unwanted flatpak removed"
assert_not_contains "$(calls)" "--delete-data org.mozilla.firefox" "never deletes app data"
assert_contains "$(calls)" "dnf remove -y --setopt=clean_requirements_on_remove=False -- firefox" "unwanted native package removed"
assert_eq "$(cat "$DECAL_STATE/apps/removed-flatpaks")" "org.mozilla.firefox flathub" "removal recorded with its remote"
# remove works from the record even after the [apps] section is deleted from the profile
python3 - "$PROFILE_DIR/profile.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r'\[apps\].*?(?=\n\[gnome-settings\])', '', s, flags=re.S); open(p,'w').write(s)
EOF
stub flatpak 'case "$*" in "info --system -- "*) exit 0;; esac; exit 0'   # now everything is installed
: > "$STUBS/calls"; run_mod remove 2>/dev/null
assert_contains "$(calls)" "flatpak uninstall --system --noninteractive -y -- com.discordapp.Discord org.gnome.Loupe" "removes exactly the managed flatpaks"
assert_not_contains "$(calls)" "com.brave.Browser" "never removes an app it didn't install"
assert_contains "$(calls)" "flatpak uninstall --system --unused --noninteractive -y" "unused runtimes"
assert_contains "$(cat "$STUBS/mime.db")" "x-scheme-handler/http=org.mozilla.firefox.desktop" "firefox restored"
assert_not_contains "$(cat "$XDG_CONFIG_HOME/mimeapps.list")" "text/markdown=" "unset mime removed"
assert_contains "$(cat "$XDG_CONFIG_HOME/mimeapps.list")" "application/x-unrelated=keep.desktop" "other lines kept"
assert_nofile "$DECAL_STATE/apps/managed" "record cleared"
assert_contains "$(calls)" "flatpak install --system --noninteractive -y -- flathub org.mozilla.firefox" "undo reinstalls the removed flatpak"
assert_contains "$(calls)" "dnf install -y -- firefox" "undo reinstalls the removed package"
assert_nofile "$DECAL_STATE/apps/removed-flatpaks" "removal record cleared"
# launchers the distro hides (Hidden/NoDisplay) shown again by [apps] show: your own copy, marked as decal's
A="$T_TMP/share/applications"; U="$XDG_DATA_HOME/applications"; mkdir -p "$U"
printf '[Desktop Entry]\nName=btop++\nExec=btop\nTerminal=true\nHidden=true\nNoDisplay=true\n' > "$A/btop.desktop"
printf '[Desktop Entry]\nName=Htop\nExec=htop\nNoDisplay=true\n' > "$A/htop.desktop"
printf '[Desktop Entry]\nName=Mine\nHidden=true\n' > "$A/mine.desktop"; printf '[Desktop Entry]\nName=My own\n' > "$U/mine.desktop"
printf '\n[apps]\nshow = ["btop", "htop", "mine", "nowhere"]\n' >> "$PROFILE_DIR/profile.toml"
out=$(run_mod add 2>&1)
assert_contains "$(cat "$U/btop.desktop")" "Exec=btop" "hidden launcher shown as your own copy"
assert_not_contains "$(cat "$U/btop.desktop")" "Hidden=" "without Hidden"; assert_not_contains "$(cat "$U/btop.desktop")" "NoDisplay=" "or NoDisplay"
assert_eq "$(cat "$U/mine.desktop")" $'[Desktop Entry]\nName=My own' "a launcher of your own is left alone"
assert_contains "$out" "nowhere" "a launcher that doesn't exist: warned"
assert_eq "$(run_mod status)" "partial (not shown: nowhere; defaults: set)" "status names what isn't shown"
sed -i 's/^show = .*/show = ["btop", "mine"]/' "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1
assert_nofile "$U/htop.desktop" "taken off the list: decal's copy removed"
assert_eq "$(run_mod status)" "installed (defaults: set)" "all listed launchers shown"
run_mod remove >/dev/null 2>&1
assert_nofile "$U/btop.desktop" "remove deletes decal's copies"; assert_file "$U/mine.desktop" "but never yours"
# tags: remove --only dev takes away just what [apps.dev] added; Discord and the rest stay
sed -i 's/^show = \["btop", "mine"\]$/&\nflatpaks = ["com.discordapp.Discord"]/' "$PROFILE_DIR/profile.toml"
printf '\n[apps.dev]\nflatpaks = ["dev.zed.Zed", "com.discordapp.Discord"]\nshow = ["htop"]\n' >> "$PROFILE_DIR/profile.toml"
stub flatpak 'case "$*" in "info --system -- com.brave.Browser") exit 0;; "info --system -- "*) exit 1;; esac; exit 0'   # decal installs Zed and Discord
DECAL_TAGS=dev run_mod add >/dev/null 2>&1
stub flatpak 'case "$*" in "info --system -- dev.zed.Zed"|"info --system -- com.discordapp.Discord"|"info --system -- com.brave.Browser") exit 0;; "info --system -- "*) exit 1;; esac; exit 0'   # now there
assert_contains "$(cat "$DECAL_STATE/apps/managed")" "dev.zed.Zed" "with --tags dev: dev's flatpak installed and recorded"
assert_file "$U/htop.desktop" "and dev's launcher shown"
: > "$STUBS/calls"; DECAL_DROP=dev run_mod drop >/dev/null 2>&1
assert_contains "$(calls)" "flatpak uninstall --system --noninteractive -y -- dev.zed.Zed" "drop: dev's flatpak uninstalled"
assert_not_contains "$(calls)" "com.discordapp.Discord" "a flatpak that is in [apps] too is kept"
assert_not_contains "$(cat "$DECAL_STATE/apps/managed")" "dev.zed.Zed" "and no longer recorded"
assert_contains "$(cat "$DECAL_STATE/apps/managed")" "com.discordapp.Discord" "the rest still recorded"
assert_nofile "$U/htop.desktop" "dev's launcher copy removed"; assert_file "$U/btop.desktop" "the untagged one kept"
# a flatpak you already had is never decal's: listing it doesn't make remove uninstall it (audit batch 2)
rm -rf "$DECAL_STATE"; : > "$STUBS/calls"
stub flatpak 'case "$*" in "info --system -- com.discordapp.Discord"|"info --system -- com.brave.Browser") exit 0;; "info --system -- "*) exit 1;; "remotes --system --columns=name") echo flathub;; esac; exit 0'
printf '[apps]\nflatpaks = ["com.discordapp.Discord"]\n' > "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_not_contains "$(calls)" "uninstall --system --noninteractive -y -- com.discordapp.Discord" "an app you already had stays"
assert_not_contains "$(calls)" "uninstall --system --unused" "nothing of ours removed: no runtime clean-up either"
assert_not_contains "$(calls)" "remote-add" "Flathub already there: not added"
# a Flathub remote decal added is taken away again (without force: it stays while anything uses it)
rm -rf "$DECAL_STATE"; : > "$STUBS/calls"
stub flatpak 'case "$*" in "info --system -- "*) exit 1;; "remotes --system --columns=name") ;; esac; exit 0'
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "flatpak remote-delete --system -- flathub" "the remote decal added: removed"
t_done
