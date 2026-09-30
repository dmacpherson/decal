#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_CONFIG_HOME="$T_TMP/home/.config"; mkdir -p "$HOME/.bashrc.d" "$XDG_CONFIG_HOME"
printf 'if [ -d ~/.bashrc.d ]; then for rc in ~/.bashrc.d/*; do . "$rc"; done; fi\n' > "$HOME/.bashrc"
stub brew 'echo "brew-env NO_SUDO=${HOMEBREW_NO_SUDO:-}" >> "$STUBS/calls"; case $1 in list) exit 0;; esac; exit 0'; stub fc-cache; stub ptyxis; stub systemctl; stub curl 'exit 7'   # tests never touch the network
stub gsettings 'case $1 in get) case $3 in default-profile-uuid) echo "'"'"'abc'"'"'";; palette) echo "'"'"'gnome'"'"'";; *) echo "'"'"'x'"'"'";; esac;; list-keys) exit 0;; esac'
mod() { mod_run terminal "$@"; }
# carapace must use its ble.sh integration when ble.sh is loaded (plain "bash" breaks with "read: `': not a valid identifier")
assert_contains "$(cat "$REPO/modules/terminal/features/completions.sh")" "_carapace bash-ble" "carapace uses bash-ble under ble.sh"
# role contract
assert_eq "$(mod terminal_missing_roles)" "" "cyberpunk defines every role tokyo-sharp uses"
built=$(mod terminal_build)
assert_contains "$built" 'palette = "theme"' "palette selector"; assert_contains "$built" "[palettes.theme]" "theme appended"
# combined output renders like the approved single-file config (fixtures/approved-starship.toml)
printf '%s\n' "$built" > "$T_TMP/a.toml"; cp "$REPO/tests/fixtures/approved-starship.toml" "$T_TMP/old.toml"
p() { STARSHIP_CONFIG="$1" starship prompt --status=1 --cmd-duration=3500 2>/dev/null | sed 's/[0-9][0-9]:[0-9][0-9]/HH:MM/'; }
assert_eq "$(p "$T_TMP/a.toml")" "$(p "$T_TMP/old.toml")" "identical to approved prompt"
# add (ptyxis): hook, config, ptyxis settings, default terminal
mkdir -p "$HOME/.local/share/blesh" "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; : > "$HOME/.local/share/blesh/ble.sh"   # pretend present (user's own ble.sh)
mod module_add 2>/dev/null; assert_eq "$?" "0" "add succeeds when xdg-terminals.list did not exist"
mod module_add 2>/dev/null; assert_eq "$?" "0" "re-add succeeds"
assert_file "$HOME/.bashrc.d/50-decal-terminal.sh" "hook"
assert_file "$XDG_CONFIG_HOME/decal/terminal/starship.toml" "config"
assert_contains "$(calls)" "brew bundle --file" "brew bundle"
assert_not_contains "$(calls)" "brew-env NO_SUDO=
" "brew never runs without HOMEBREW_NO_SUDO (it would end decal's sudo session)"
assert_contains "$(calls)" "brew-env NO_SUDO=1" "brew runs with HOMEBREW_NO_SUDO=1"
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis cursor-shape underline" "cursor"
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ palette decal-cyberpunk" "palette"
assert_eq "$(head -1 "$XDG_CONFIG_HOME/xdg-terminals.list")" "org.gnome.Ptyxis.desktop" "default terminal"
assert_eq "$(cat "$DECAL_USER_STATE/terminal.current")" "ptyxis" "current recorded"
assert_not_contains "$(calls)" "dnf install" "ptyxis preinstalled: nothing installed"
if command -v uupd >/dev/null; then assert_nofile "$XDG_CONFIG_HOME/systemd/user/decal-brew-upgrade.timer" "uupd handles brew: no timer"
else assert_file "$XDG_CONFIG_HOME/systemd/user/decal-brew-upgrade.timer" "no uupd: timer installed"
     assert_contains "$(calls)" "systemctl --user enable --now decal-brew-upgrade.timer" "timer enabled"; fi
mod module_remove 2>/dev/null
assert_nofile "$HOME/.bashrc.d/50-decal-terminal.sh" "hook removed"
assert_nofile "$XDG_CONFIG_HOME/decal/terminal" "config removed"
assert_nofile "$HOME/.local/share/fonts/decal/FiraCodeNerdFont" "font removed"
assert_file "$HOME/.local/share/blesh" "ble.sh we did not download is kept"
assert_nofile "$XDG_CONFIG_HOME/xdg-terminals.list" "xdg-terminals.list back to absent"
assert_nofile "$XDG_CONFIG_HOME/systemd/user/decal-brew-upgrade.timer" "timer removed"
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ palette 'gnome'" "ptyxis palette restored"
# marked-block mode when .bashrc doesn't source .bashrc.d
printf '# plain bashrc\n' > "$HOME/.bashrc"; mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add 2>/dev/null
assert_contains "$(cat "$HOME/.bashrc")" "# >>> decal terminal >>>" "block appended"
mod module_remove 2>/dev/null; assert_eq "$(cat "$HOME/.bashrc")" "# plain bashrc" "block removed exactly"
# fresh Ptyxis (never launched): no default profile yet -> add still succeeds, palette skipped with a warning
stub gsettings 'case $1 in get) case $3 in default-profile-uuid) echo "'"'"''"'"'";; profile-uuids) echo "@as []";; *) echo "'"'"'x'"'"'";; esac;; list-keys) exit 0;; esac'
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"
out=$(mod module_add 2>&1); rc=$?
assert_eq "$rc" "0" "fresh ptyxis: add succeeds"; assert_contains "$out" "no Ptyxis profile yet" "fresh ptyxis: warns"
mod module_remove 2>/dev/null
# unknown terminal fails clearly
sed -i 's/^app = "ptyxis"/app = "nope"/' "$PROFILE_DIR/profile.toml"
out=$(mod module_add 2>&1); assert_contains "$out" "unknown TERMINAL 'nope'" "unknown terminal"
sed -i 's/^app = "nope"/app = "ptyxis"/' "$PROFILE_DIR/profile.toml"
# feature toggles: generated files hold only enabled features; turning one off undoes its side effect
printf '# plain\nif [ -d ~/.bashrc.d ]; then for rc in ~/.bashrc.d/*; do . "$rc"; done; fi\n' > "$HOME/.bashrc"
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"
mod module_add 2>/dev/null
CFGD="$XDG_CONFIG_HOME/decal/terminal"
assert_contains "$(cat "$CFGD/Brewfile")" 'brew "eza"' "ls feature -> eza in Brewfile"
assert_contains "$(cat "$CFGD/Brewfile")" 'brew "fastfetch"' "extra brew from profile"
assert_contains "$(cat "$CFGD/bashrc.sh")" "alias ls='eza" "ls feature -> alias"
echo "$HOME/.local/share/blesh" > "$DECAL_USER_STATE/terminal.blesh"   # pretend we downloaded ble.sh
sed -i 's/^app = "ptyxis"/&\nfeatures.ls = false\nfeatures.autosuggest = false\nfeatures.default-terminal = false/' "$PROFILE_DIR/profile.toml"
mod module_add 2>/dev/null; assert_eq "$?" "0" "add with features off"
assert_not_contains "$(cat "$CFGD/Brewfile")" 'brew "eza"' "ls off -> no eza"
assert_not_contains "$(cat "$CFGD/bashrc.sh")" "eza" "ls off -> no alias"
assert_not_contains "$(cat "$CFGD/bashrc.sh")" "blesh/ble.sh" "autosuggest off -> ble.sh not loaded"
assert_nofile "$HOME/.local/share/blesh" "autosuggest off -> our ble.sh removed"
assert_nofile "$XDG_CONFIG_HOME/xdg-terminals.list" "default-terminal off -> restored (was absent)"
assert_contains "$(cat "$CFGD/bashrc.sh")" "starship init bash" "other features still there"
mod module_remove 2>/dev/null
# switching fonts removes the old one; remove works from what add recorded even after the section is deleted
FD="$HOME/.local/share/fonts/decal"; mkdir -p "$FD/FiraCodeNerdFont" "$FD/HackNerdFont"
sed -i 's/^app = "ptyxis"$/&\nnerd-font = "Hack"\nremove-brew = true/' "$PROFILE_DIR/profile.toml"
mod module_add >/dev/null 2>&1
assert_nofile "$FD/FiraCodeNerdFont" "old nerd font removed when switching"; assert_file "$FD/HackNerdFont" "new nerd font kept"
echo fastfetch >> "$DECAL_USER_STATE/terminal.brew"
python3 - "$PROFILE_DIR/profile.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[terminal(\.[a-z]+)?\]\n.*?(?=^\[(?!terminal)|\Z)","",s); open(p,'w').write(s)
EOF
: > "$STUBS/calls"; mod module_remove >/dev/null 2>&1
assert_nofile "$FD/HackNerdFont" "remove without the section still removes the installed font"
assert_contains "$(calls)" "brew uninstall fastfetch" "remove-brew recorded at add time is honoured"
t_done
