# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Terminal app (default Ptyxis) set as default + bash prompt/tools, per your profile's [terminal.features]"
# every brew command runs "sudo --reset-timestamp" unless told it can't use sudo, which would end
# decal's sudo session mid-run; Homebrew never needs sudo for formulae on Linux
export HOMEBREW_NO_SUDO=1
MODULE_NEEDS_ROOT=1   # installing a non-preinstalled terminal needs sudo
MODULE_DIR="${MODULE_DIR:-$PWD}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/decal/terminal"
XDG_TERMS="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"
HOOK="$HOME/.bashrc.d/50-decal-terminal.sh"
BLESH="$HOME/.local/share/blesh"
MARK_BEGIN="# >>> decal terminal >>>"; MARK_END="# <<< decal terminal <<<"
# shellcheck disable=SC2016  # expanded later, by bash at login
HOOK_LINE='[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/decal/terminal/bashrc.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/decal/terminal/bashrc.sh"'
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo
TOOL_FEATURES=(prompt fuzzy completions history jump ls cat)   # bashrc order (between ble load/attach)
declare -A FEATURE_BREW=([prompt]=starship [fuzzy]=fzf [completions]=carapace [history]=atuin [jump]=zoxide [ls]=eza [cat]=bat)

_preset() { if [[ -e ${PROFILE_DIR:-/nonexistent}/terminal/$1/$2 ]]; then echo "$PROFILE_DIR/terminal/$1/$2"; else echo "$MODULE_DIR/$1/$2"; fi; }
_init() {
  TERMINAL=$P_app LAYOUT=$P_layout THEME=$P_theme NERD_FONT=$P_nerd_font FONT=$P_font CURSOR=$P_cursor
  FONT_FAMILY="${FONT% *}"; FONT_SIZE="${FONT##* }"
  FONT_DIR="$HOME/.local/share/fonts/decal/${NERD_FONT}NerdFont"
  LAYOUT_FILE=$(_preset layouts "$LAYOUT.toml"); THEME_DIR=$(_preset themes "$THEME"); PALETTE="$THEME_DIR/colors.palette"
}
_on() { local v="P_features_${1//-/_}"; [[ ${!v} == true ]]; }

terminal_build() {
  _init
  [[ -r $LAYOUT_FILE ]] || die "layout not found: $LAYOUT_FILE"
  [[ -r $THEME_DIR/starship.toml ]] || die "theme not found: $THEME_DIR/starship.toml"
  printf 'palette = "theme"\n'; cat "$LAYOUT_FILE"; echo; cat "$THEME_DIR/starship.toml"
}
terminal_missing_roles() {
  _init
  local used defined r
  used=$(grep -oE '(fg|bg):[a-z_]+|\]\((bold )?[a-z_]+\)' "$LAYOUT_FILE" | sed -E 's/^(fg|bg)://; s/^\]\((bold )?//; s/\)$//' | sort -u)
  defined=$(sed -n '/^\[palettes.theme\]/,/^\[/p' "$THEME_DIR/starship.toml" | grep -oE '^[a-z_]+' | sort -u)
  for r in $used; do grep -qx "$r" <<<"$defined" || echo "$r"; done
}
_load_adapter() {
  local t=$1
  # shellcheck disable=SC2012  # plain adapter names, list only
  [[ -r $MODULE_DIR/terminals/$t.sh ]] || die "unknown TERMINAL '$t' (choose one of: $(cd "$MODULE_DIR/terminals" && ls | sed 's/\.sh$//' | tr '\n' ' '))"
  unset -f term_source term_configure term_unconfigure term_configured
  # shellcheck source=/dev/null
  source "$MODULE_DIR/terminals/$t.sh"
}
_copr_enable() {  # owner/name
  local owner=${1%/*} name=${1#*/} path="/etc/yum.repos.d/_copr-${1%/*}-${1#*/}.repo"
  # shellcheck disable=SC2016  # $releasever/$basearch are dnf variables, kept literal
  printf '[copr:copr.fedorainfracloud.org:%s:%s]\nname=Copr repo for %s\nbaseurl=https://download.copr.fedorainfracloud.org/results/%s/%s/fedora-$releasever-$basearch/\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://download.copr.fedorainfracloud.org/results/%s/%s/pubkey.gpg\nrepo_gpgcheck=0\nenabled=1\n' \
    "$owner" "$name" "$1" "$owner" "$name" "$owner" "$name" | etc_write terminal "$path"
  state_append "$LS_STATE/terminal/copr" "$path"
}
_term_install() {
  local kind a b; read -r kind a b <<<"$(term_source)"
  case $kind in
    preinstalled) ;;
    pkg) pkg_install terminal "$a" ;;
    flatpak)
      if ! flatpak info --system "$a" >/dev/null 2>&1; then
        srun flatpak remote-add --system --if-not-exists flathub "$FLATHUB"
        srun flatpak install --system --noninteractive -y flathub "$a"
        state_append "$LS_STATE/terminal/flatpaks" "$a"
      fi ;;
    copr) warn "$TERMINAL comes from the community COPR $a (not an official Fedora package)"; _copr_enable "$a"; pkg_install terminal "$b" ;;
    *) die "$TERMINAL is not available on $PLATFORM" ;;
  esac
}
_set_default_terminal() {
  local prev="$LS_USER_STATE/xdg-terminals.prev"
  if [[ $LS_DRY_RUN != 1 && ! -e $prev && ! -e $prev.absent ]]; then
    mkdir -p "$LS_USER_STATE"; if [[ -e $XDG_TERMS ]]; then cp "$XDG_TERMS" "$prev"; else : > "$prev.absent"; fi
  fi
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] default terminal -> $TERM_DESKTOP"; return 0; }
  mkdir -p "$(dirname "$XDG_TERMS")"
  { echo "$TERM_DESKTOP"; if [[ -r $prev ]]; then grep -vxF "$TERM_DESKTOP" "$prev" || true; fi; } > "$XDG_TERMS"
}
_restore_default_terminal() {
  local prev="$LS_USER_STATE/xdg-terminals.prev"
  if [[ -e $prev ]]; then run cp "$prev" "$XDG_TERMS"; run rm -f "$prev"
  elif [[ -e $prev.absent ]]; then run rm -f "$XDG_TERMS" "$prev.absent"; fi
}

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
_uupd_handles_brew() {
  have uupd || return 1
  [[ -e $(sys_path /etc/uupd/config.json) ]] || return 0
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(1 if c.get("modules",{}).get("brew",{}).get("disable") else 0)' \
    "$(sys_path /etc/uupd/config.json)"
}
_updater_add() {
  if _uupd_handles_brew; then log "updates: uupd upgrades brew with the system (nothing to add)"; return 0; fi
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] install user timer decal-brew-upgrade"; return 0; }
  local brew; brew=$(command -v brew)
  mkdir -p "$UNIT_DIR"
  printf '%s\n' "[Unit]" "Description=decal: upgrade Homebrew packages and ble.sh" "[Service]" "Type=oneshot" \
    "ExecStart=/bin/bash -c '$brew update && $brew upgrade; [ -f \"$BLESH/ble.sh\" ] && bash \"$BLESH/ble.sh\" --update || true'" \
    > "$UNIT_DIR/decal-brew-upgrade.service"
  printf '%s\n' "[Unit]" "Description=decal: daily Homebrew upgrade" "[Timer]" "OnCalendar=daily" "Persistent=true" \
    "RandomizedDelaySec=1h" "[Install]" "WantedBy=timers.target" > "$UNIT_DIR/decal-brew-upgrade.timer"
  systemctl --user daemon-reload
  systemctl --user enable --now decal-brew-upgrade.timer
}
_updater_remove() {
  [[ -e $UNIT_DIR/decal-brew-upgrade.timer ]] || return 0
  run systemctl --user disable --now decal-brew-upgrade.timer || true
  run rm -f "$UNIT_DIR/decal-brew-upgrade.service" "$UNIT_DIR/decal-brew-upgrade.timer"
  run systemctl --user daemon-reload
}
_updater_desc() {
  if _uupd_handles_brew; then echo "updates: uupd"
  elif [[ -e $UNIT_DIR/decal-brew-upgrade.timer ]]; then echo "updates: decal timer"
  else echo "updates: none"; fi
}

_gen_bashrc() {
  echo "# Generated by decal (terminal module) from your profile's [terminal.features]."
  echo "# Don't edit: change the profile and run ./decal add terminal"
  # shellcheck disable=SC2016
  echo '[[ $- == *i* ]] || return 0'
  if _on autosuggest; then cat "$MODULE_DIR/features/autosuggest-load.sh"; fi
  local f; for f in "${TOOL_FEATURES[@]}"; do if _on "$f"; then cat "$MODULE_DIR/features/$f.sh"; fi; done
  if _on autosuggest; then cat "$MODULE_DIR/features/autosuggest-attach.sh"; fi
}
_gen_brewfile() {
  local f b
  for f in "${TOOL_FEATURES[@]}"; do if _on "$f"; then echo "brew \"${FEATURE_BREW[$f]}\""; fi; done
  for b in "${P_brew[@]}"; do echo "brew \"$b\""; done
}
_blesh_add() {
  if [[ -f $BLESH/ble.sh ]]; then return 0; fi
  local src d; src=$(ls_fetch "$P_autosuggest_source" --asset "ble-*.tar.xz") || die "could not fetch ble.sh from $P_autosuggest_source"
  if [[ $LS_DRY_RUN == 1 ]]; then return 0; fi
  d=$(find "$src" -maxdepth 2 -name ble.sh -printf '%h\n' | head -1)
  [[ -n $d ]] || die "no ble.sh found in $P_autosuggest_source"
  mkdir -p "$(dirname "$BLESH")"; rm -rf "$BLESH"; cp -a "$d" "$BLESH"
  echo "$BLESH" > "$LS_USER_STATE/terminal.blesh"   # remove deletes it only if we put it there
}
_blesh_remove() { if [[ -e $LS_USER_STATE/terminal.blesh ]]; then run rm -rf "$BLESH"; run rm -f "$LS_USER_STATE/terminal.blesh"; fi; }
_font_add() {
  if [[ -d $FONT_DIR ]]; then return 0; fi
  local src; src=$(ls_fetch "$P_nerd_font_source" --asset "$NERD_FONT.tar.xz") || die "could not fetch the $NERD_FONT Nerd Font from $P_nerd_font_source"
  if [[ $LS_DRY_RUN == 1 ]]; then return 0; fi
  mkdir -p "$FONT_DIR"; find "$src" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec cp {} "$FONT_DIR/" \;
  [[ -n $(ls -A "$FONT_DIR") ]] || { rmdir "$FONT_DIR"; die "no font files in $P_nerd_font_source ($NERD_FONT.tar.xz)"; }
  fc-cache -f "$FONT_DIR" >/dev/null
  info "new font installed: close ALL terminal windows (or open a fresh instance) to see it"
}
_font_remove() {  # [KEEP] : remove our fonts (everything under fonts/decal), except KEEP
  local root d n=0; root=$(dirname "$FONT_DIR")
  for d in "$root"/*/; do
    [[ -d $d ]] || continue
    if [[ -n ${1:-} && ${d%/} == "$1" ]]; then continue; fi
    run rm -rf "${d%/}"; n=1
  done
  if (( n )) && have fc-cache; then run fc-cache -f >/dev/null 2>&1; fi
  return 0
}
module_fetch() {
  _init
  if _on autosuggest; then ls_fetch "$P_autosuggest_source" --asset "ble-*.tar.xz" >/dev/null; fi
  if _on nerd-font; then ls_fetch "$P_nerd_font_source" --asset "$NERD_FONT.tar.xz" >/dev/null; fi
}

module_add() {
  _init
  local missing old bf before
  missing=$(terminal_missing_roles); [[ -z $missing ]] || die "theme '$THEME' lacks roles used by layout '$LAYOUT': $missing"
  _load_adapter "$TERMINAL"
  run mkdir -p "$LS_USER_STATE" "$CFG"
  if [[ $LS_DRY_RUN != 1 ]]; then echo "$P_remove_brew" > "$LS_USER_STATE/terminal.remove-brew"; fi   # remove honours it without the profile
  # 1. Homebrew tools for the enabled features (+ extra formulae)
  bf=$(_gen_brewfile)
  if [[ -n $bf ]]; then
    have brew || die "Homebrew not found. Install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] brew bundle: $(tr '\n' ' ' <<<"$bf")"
    else
      before=$(brew list --formula -1 2>/dev/null | sort)
      printf '%s\n' "$bf" > "$CFG/Brewfile"; brew bundle --file "$CFG/Brewfile"
      comm -13 <(echo "$before") <(brew list --formula -1 2>/dev/null | sort) >> "$LS_USER_STATE/terminal.brew"
    fi
  fi
  # 2-3. downloads, only for enabled features (turning one off undoes it)
  if _on autosuggest; then _blesh_add; else _blesh_remove; fi
  if _on nerd-font; then _font_remove "$FONT_DIR"; _font_add; else _font_remove; fi
  # 4. generated prompt config + shell integration
  if [[ $LS_DRY_RUN != 1 ]]; then
    if _on prompt; then terminal_build > "$CFG/starship.toml"; else rm -f "$CFG/starship.toml"; fi
    _gen_bashrc > "$CFG/bashrc.sh"
  fi
  # 5. hook
  if grep -q '\.bashrc\.d' "$HOME/.bashrc" 2>/dev/null; then
    [[ $LS_DRY_RUN == 1 ]] || { mkdir -p "$(dirname "$HOOK")"; printf '# Added by decal (terminal module). Remove with: ./decal remove terminal\n%s\n' "$HOOK_LINE" > "$HOOK"; }
  elif ! grep -qF "$MARK_BEGIN" "$HOME/.bashrc" 2>/dev/null; then
    [[ $LS_DRY_RUN == 1 ]] || printf '%s\n%s\n%s\n' "$MARK_BEGIN" "$HOOK_LINE" "$MARK_END" >> "$HOME/.bashrc"
  fi
  if grep -q 'bazzite-cli/bling' "$HOME/.bashrc" 2>/dev/null; then warn "ujust bazzite-cli bling is also enabled in ~/.bashrc; disable it with 'ujust bazzite-cli' to avoid loading tools twice"; fi
  # 6. terminal app: unconfigure the previous choice, install + configure this one
  old=$(cat "$LS_USER_STATE/terminal.current" 2>/dev/null || true)
  if [[ -n $old && $old != "$TERMINAL" ]]; then _load_adapter "$old"; term_unconfigure; _load_adapter "$TERMINAL"; fi
  _term_install
  term_configure
  [[ $LS_DRY_RUN == 1 ]] || echo "$TERMINAL" > "$LS_USER_STATE/terminal.current"
  # 7. default terminal, updates
  if _on default-terminal; then _set_default_terminal; else _restore_default_terminal; fi
  if _on auto-update; then _updater_add; else _updater_remove; fi
}

module_remove() {
  _init
  local cur; cur=$(cat "$LS_USER_STATE/terminal.current" 2>/dev/null || true)
  if [[ -n $cur ]]; then _load_adapter "$cur"; term_unconfigure; run rm -f "$LS_USER_STATE/terminal.current"; fi
  _restore_default_terminal
  _updater_remove
  run rm -f "$HOOK"
  if grep -qF "$MARK_BEGIN" "$HOME/.bashrc" 2>/dev/null && [[ $LS_DRY_RUN != 1 ]]; then
    python3 - "$HOME/.bashrc" "$MARK_BEGIN" "$MARK_END" <<'EOF'
import sys
p, b, e = sys.argv[1:4]; out = []; skip = False
for l in open(p).read().split("\n"):
    if l == b: skip = True; continue
    if l == e and skip: skip = False; continue
    if not skip: out.append(l)
open(p, "w").write("\n".join(out))
EOF
  fi
  run rm -rf "$CFG"; _font_remove; _blesh_remove
  local id p
  if [[ -r $LS_STATE/terminal/flatpaks ]]; then
    while IFS= read -r id; do [[ -n $id ]] && srun flatpak uninstall --system --noninteractive -y "$id"; done < "$LS_STATE/terminal/flatpaks"
    srun rm -f "$LS_STATE/terminal/flatpaks"
  fi
  pkg_remove terminal
  if [[ -r $LS_STATE/terminal/copr ]]; then
    while IFS= read -r p; do [[ -n $p ]] && etc_restore terminal "$p"; done < "$LS_STATE/terminal/copr"
    srun rm -f "$LS_STATE/terminal/copr"
  fi
  local rb; rb=$(cat "$LS_USER_STATE/terminal.remove-brew" 2>/dev/null || true)
  if [[ ($rb == true || $P_remove_brew == true) && -s $LS_USER_STATE/terminal.brew ]]; then
    # shellcheck disable=SC2046
    run brew uninstall $(cat "$LS_USER_STATE/terminal.brew"); run rm -f "$LS_USER_STATE/terminal.brew"
  fi
  run rm -f "$LS_USER_STATE/terminal.remove-brew"
}

module_status() {
  _init
  local why=()
  _load_adapter "$TERMINAL"
  [[ -n $(terminal_missing_roles) ]] && why+=("theme lacks roles")
  { [[ -e $HOOK ]] || grep -qF "$MARK_BEGIN" "$HOME/.bashrc" 2>/dev/null; } || why+=("no shell hook")
  [[ -r $CFG/bashrc.sh && "$(_gen_bashrc)" == "$(cat "$CFG/bashrc.sh")" ]] || why+=("shell integration out of date")
  if _on prompt; then [[ -r $CFG/starship.toml && "$(terminal_build)" == "$(cat "$CFG/starship.toml")" ]] || why+=("prompt config out of date"); fi
  if _on nerd-font; then [[ -d $FONT_DIR ]] || why+=("font missing"); fi
  { [[ $(cat "$LS_USER_STATE/terminal.current" 2>/dev/null) == "$TERMINAL" ]] && term_configured; } || why+=("$TERMINAL not configured")
  if _on default-terminal; then [[ $(head -1 "$XDG_TERMS" 2>/dev/null) == "$TERM_DESKTOP" ]] || why+=("not the default terminal"); fi
  if _on auto-update; then [[ $(_updater_desc) != "updates: none" ]] || why+=("no updater"); fi
  if (( ${#why[@]} == 0 )); then echo "installed ($TERMINAL, $(_updater_desc))"
  elif [[ ! -e $HOOK && ! -d $CFG ]]; then echo not-installed
  else local IFS=","; echo "partial (${why[*]})" | sed "s/,/, /g"; fi
}
