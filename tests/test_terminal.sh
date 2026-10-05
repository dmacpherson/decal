#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_CONFIG_HOME="$T_TMP/home/.config"; mkdir -p "$HOME/.bashrc.d" "$XDG_CONFIG_HOME"
printf 'if [ -d ~/.bashrc.d ]; then for rc in ~/.bashrc.d/*; do . "$rc"; done; fi\n' > "$HOME/.bashrc"
stub brew 'echo "brew-env NO_SUDO=${HOMEBREW_NO_SUDO:-}" >> "$STUBS/calls"; case $1 in list) exit 0;; esac; exit 0'; stub fc-cache; stub ptyxis; stub systemctl; stub curl 'exit 7'   # tests never touch the network; the font is faked before each add (fetch.py downloads with Python, not curl)
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
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ opacity 1" "opacity (default: opaque)"
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
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ opacity 'x'" "ptyxis opacity restored"
# a backup made by an older decal (no opacity in it) gets the current opacity added, so remove restores it too
mkdir -p "$DECAL_USER_STATE"; echo "profile:palette='gnome'" > "$DECAL_USER_STATE/terminal-ptyxis.prev"
sed -i 's/^app = "ptyxis"$/&\nopacity = 0.75/' "$PROFILE_DIR/profile.toml"
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add 2>/dev/null
assert_contains "$(cat "$DECAL_USER_STATE/terminal-ptyxis.prev")" "profile:opacity='x'" "older backup gains the opacity"
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ opacity 0.75" "opacity from the profile"
mod module_remove 2>/dev/null; sed -i '/^opacity = 0.75$/d' "$PROFILE_DIR/profile.toml"
# marked-block mode when .bashrc doesn't source .bashrc.d
printf '# plain bashrc\n' > "$HOME/.bashrc"; mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add 2>/dev/null
assert_contains "$(cat "$HOME/.bashrc")" "# >>> decal terminal >>>" "block appended"
i_rc=$(stat -c %i "$HOME/.bashrc")
mod module_remove 2>/dev/null; assert_eq "$(cat "$HOME/.bashrc")" "# plain bashrc" "block removed exactly"
assert_not_contains "$(stat -c %i "$HOME/.bashrc")" "$i_rc" "~/.bashrc replaced whole (never half-written)"
# a ~/.bashrc that links into a dotfiles folder: the hook comes out of the real file and the link stays (review)
mkdir -p "$HOME/dot"; printf '# plain bashrc\n' > "$HOME/dot/bashrc"; rm -f "$HOME/.bashrc"; ln -s dot/bashrc "$HOME/.bashrc"
mod module_add 2>/dev/null; mod module_remove 2>/dev/null
assert_eq "$(readlink "$HOME/.bashrc")" "dot/bashrc" "a linked ~/.bashrc stays a link"
assert_eq "$(cat "$HOME/dot/bashrc")" "# plain bashrc" "the hook comes out of the real file"
rm -f "$HOME/.bashrc"; printf '# plain bashrc\n' > "$HOME/.bashrc"
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
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add 2>/dev/null; assert_eq "$?" "0" "add with features off"
assert_not_contains "$(cat "$CFGD/Brewfile")" 'brew "eza"' "ls off -> no eza"
assert_not_contains "$(cat "$CFGD/bashrc.sh")" "eza" "ls off -> no alias"
assert_not_contains "$(cat "$CFGD/bashrc.sh")" "blesh/ble.sh" "autosuggest off -> ble.sh not loaded"
assert_nofile "$HOME/.local/share/blesh" "autosuggest off -> our ble.sh removed"
assert_nofile "$XDG_CONFIG_HOME/xdg-terminals.list" "default-terminal off -> restored (was absent)"
assert_contains "$(cat "$CFGD/bashrc.sh")" "starship init bash" "other features still there"
mod module_remove 2>/dev/null
# motd = false: Universal Blue's welcome message off (ujust toggle-user-motd's file); only on images that have it
sed -i 's/^app = "ptyxis"$/&\nmotd = false/' "$PROFILE_DIR/profile.toml"
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add >/dev/null 2>&1; assert_nofile "$HOME/.config/no-show-user-motd" "no Universal Blue motd: nothing done"
mkdir -p "$DECAL_ROOT/etc/profile.d"; : > "$DECAL_ROOT/etc/profile.d/user-motd.sh"
assert_contains "$(mod module_status 2>/dev/null)" "welcome message still shown" "status: motd still on"
mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add >/dev/null 2>&1; assert_file "$HOME/.config/no-show-user-motd" "motd = false: welcome message turned off"
mod module_remove >/dev/null 2>&1; assert_nofile "$HOME/.config/no-show-user-motd" "remove turns it back on"
: > "$HOME/.config/no-show-user-motd"; mkdir -p "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; mod module_add >/dev/null 2>&1; mod module_remove >/dev/null 2>&1
assert_file "$HOME/.config/no-show-user-motd" "turned off by you before decal: left off"
rm -f "$HOME/.config/no-show-user-motd"; sed -i '/^motd = false$/d' "$PROFILE_DIR/profile.toml"
# switching fonts removes the old one; remove works from what add recorded even after the section is deleted
FD="$HOME/.local/share/fonts/decal"; mkdir -p "$FD/FiraCodeNerdFont" "$FD/HackNerdFont"
sed -i 's/^app = "ptyxis"$/&\nnerd-font = "Hack"\nremove-brew = true/' "$PROFILE_DIR/profile.toml"
mod module_add >/dev/null 2>&1
assert_nofile "$FD/FiraCodeNerdFont" "old nerd font removed when switching"; assert_file "$FD/HackNerdFont" "new nerd font kept"
echo fastfetch >> "$DECAL_USER_STATE/terminal.brew"
# tags: remove --only dev uninstalls the brew tools [terminal.dev] added (those decal installed), nothing else
printf '\n[terminal.dev]\nbrew = ["gh", "fastfetch", "mine"]\n' >> "$PROFILE_DIR/profile.toml"; echo gh >> "$DECAL_USER_STATE/terminal.brew"
: > "$STUBS/calls"; out=$(DECAL_DROP=dev mod module_drop 2>&1)
assert_contains "$(calls)" "brew uninstall gh" "drop: dev's brew tool uninstalled"
assert_not_contains "$(calls)" "uninstall fastfetch" "one in [terminal] too is kept"
assert_contains "$out" "mine: not installed by decal; left alone" "one decal didn't install is left alone"
assert_eq "$(cat "$DECAL_USER_STATE/terminal.brew")" "fastfetch" "and the record updated"
python3 - "$PROFILE_DIR/profile.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[terminal(\.[a-z]+)?\]\n.*?(?=^\[(?!terminal)|\Z)","",s); open(p,'w').write(s)
EOF
: > "$STUBS/calls"; mod module_remove >/dev/null 2>&1
assert_nofile "$FD/HackNerdFont" "remove without the section still removes the installed font"
assert_contains "$(calls)" "brew uninstall fastfetch" "remove-brew recorded at add time is honoured"
# no Homebrew (most distros): decal installs it into a prefix it hands you, so the installer never needs sudo, then uses it
mkdir -p "$HOME/.local/share/blesh" "$FD/FiraCodeNerdFont"; : > "$HOME/.local/share/blesh/ble.sh"   # downloads present
rm -f "$STUBS/brew"; : > "$STUBS/calls"; stub rpm 'exit 1'; stub dnf
export DECAL_BREW_PREFIX="$T_TMP/linuxbrew/.linuxbrew"
mod_run_pre() { ls_fetch() { printf '%s\n' "echo \"installer NONINTERACTIVE=\${NONINTERACTIVE:-}\" >> $STUBS/calls" \
  "mkdir -p $DECAL_BREW_PREFIX/bin; cp $T_TMP/fakebrew $DECAL_BREW_PREFIX/bin/brew" > "$T_TMP/inst.sh"; echo "$T_TMP/inst.sh"; }; }
printf '%s\n' '#!/usr/bin/env bash' "echo \"brew \$*\" >> $STUBS/calls" '[ "$1" = shellenv ] && echo "export PATH=\"'"$DECAL_BREW_PREFIX"'/bin:\$PATH\""; exit 0' > "$T_TMP/fakebrew"; chmod +x "$T_TMP/fakebrew"
mod module_add >/dev/null 2>&1; assert_eq "$?" "0" "add succeeds without Homebrew"
assert_contains "$(calls)" "dnf install -y -- git" "git installed for Homebrew"
assert_contains "$(calls)" "installer NONINTERACTIVE=1" "Homebrew installer run non-interactively"
assert_contains "$(calls)" "brew bundle --file" "the new brew installs the tools"
assert_file "$DECAL_USER_STATE/terminal.homebrew" "recorded that decal installed Homebrew"
assert_contains "$(cat "$XDG_CONFIG_HOME/decal/terminal/bashrc.sh")" "/home/linuxbrew/.linuxbrew/bin/brew shellenv" "new shells find Homebrew"
: > "$STUBS/calls"; mod module_add >/dev/null 2>&1
assert_not_contains "$(calls)" "installer" "installed but not on PATH: not installed again"
unset -f mod_run_pre; unset DECAL_BREW_PREFIX
# defence in depth: an adapter or preset name that isn't a plain name is refused even if handed in directly
out=$( (cd "$REPO/modules/terminal"; source "$REPO/lib/common.sh"; MODULE_DIR=$PWD; source ./module.sh; _load_adapter "../../../tmp/evil") 2>&1); assert_eq "$?" "1" "adapter ../: refused"
assert_contains "$out" "unknown TERMINAL" "...as an unknown terminal"
out=$( (cd "$REPO/modules/terminal"; source "$REPO/lib/common.sh"; MODULE_DIR=$PWD; source ./module.sh; _preset themes "../../x") 2>&1); assert_eq "$?" "1" "preset ../: refused"
out=$( (cd "$REPO/modules/terminal"; source "$REPO/lib/common.sh"; MODULE_DIR=$PWD; source ./module.sh; P_brew=('jq"; system("id"); "'); P_features_prompt=false; for f in fuzzy completions history jump ls cat; do eval "P_features_$f=false"; done; _gen_brewfile) 2>&1); assert_eq "$?" "1" "a formula that isn't a name: refused"
# a terminal app this distro can't install (ghostty on Debian): skipped before anything changes (audit batch 2)
sed -i 's/^app = "ptyxis"$/app = "ghostty"/' "$PROFILE_DIR/profile.toml"; grep -q '^app = "ghostty"' "$PROFILE_DIR/profile.toml" || printf '\n[terminal]\napp = "ghostty"\n' >> "$PROFILE_DIR/profile.toml"
rm -rf "$XDG_CONFIG_HOME/decal/terminal"; : > "$STUBS/calls"
out=$(DECAL_PLATFORM=debian mod module_add 2>&1); assert_eq "$?" "0" "unavailable terminal: not a failure"
assert_contains "$out" "ghostty isn't available on debian" "...says why"; assert_nofile "$XDG_CONFIG_HOME/decal/terminal/Brewfile" "...and nothing was set up first"
# Homebrew decal installed is kept on remove (it may hold your own tools), and remove says so and how to take it off
mkdir -p "$DECAL_USER_STATE"; : > "$DECAL_USER_STATE/terminal.homebrew"
out=$(mod module_remove 2>&1); assert_contains "$out" "Homebrew (installed by decal) is kept" "remove: says Homebrew stays"
assert_contains "$out" "uninstall.sh" "...and how to remove it"; assert_nofile "$DECAL_USER_STATE/terminal.homebrew" "...the record cleared"
# the Homebrew installer failing halfway: decal has already noted that it installed (some of) Homebrew
export DECAL_BREW_PREFIX="$T_TMP/lb2/.linuxbrew"; rm -f "$DECAL_USER_STATE/terminal.homebrew" "$STUBS/brew"
mod_run_pre() { ls_fetch() { printf 'exit 1\n' > "$T_TMP/inst.sh"; echo "$T_TMP/inst.sh"; }; }
mod module_add >/dev/null 2>&1; assert_file "$DECAL_USER_STATE/terminal.homebrew" "an interrupted Homebrew install is still noted"
unset -f mod_run_pre; unset DECAL_BREW_PREFIX
t_done
