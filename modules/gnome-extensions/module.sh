# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile (P_*)
MODULE_DESC="GNOME extensions (install from extensions.gnome.org, enable, settings, panel logo)"
VENDORED_MAIN="#deddda"              # main fill of the vendored SVG; recoloured to P_logo_color
ICON_DIR="$HOME/.local/share/decal/icons"
_logo_path() { echo "$ICON_DIR/gnome-logo-${P_logo_color#\#}.svg"; }
_uuids() { if (( ${#P_enable[@]} )); then printf '%s\n' "${P_enable[@]}"; fi; }
_dt() { python3 "$LS_REPO/lib/dconf_tool.py" "$@"; }
_settings() {  # _settings CMD [args] : run dconf_tool on the profile's extension settings (if any)
  [[ -n $P_file ]] || return 0
  _dt "$1" --base /org/gnome/shell/extensions/ --ini "$P_file" --extensions \
    --prev "$LS_USER_STATE/gnome-extensions.prev.json" --subst "@HOME@=$HOME" --subst "@LOGO_PATH@=$(_logo_path)" --subst "@TERMINAL_CMD@=$(terminal_cmd)" "${@:2}"
}
_shell_major() { gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1; }

_install_from_ego() {  # UUID -> 0 installed, 1 unavailable
  local uuid=$1 major url tmp; major=$(_shell_major)
  url=$(curl -fsS "$P_source/extension-info/?uuid=$uuid&shell_version=$major" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["download_url"])' 2>/dev/null) || return 1
  tmp=$(mktemp --suffix=.zip)
  curl -fsSL "$P_source$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  gnome-extensions install --force "$tmp"; rm -f "$tmp"
}

module_add() {
  have gnome-extensions || die "gnome-extensions not found (GNOME Shell required)"
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] would install missing: $(for u in $(_uuids); do gnome-extensions info "$u" >/dev/null 2>&1 || printf '%s ' "$u"; done)"; return 0; fi
  mkdir -p "$LS_USER_STATE" "$ICON_DIR"
  local u new=0
  for u in $(_uuids); do
    gnome-extensions info "$u" >/dev/null 2>&1 && continue
    if _install_from_ego "$u"; then echo "$u" >> "$LS_USER_STATE/gnome-extensions.installed"; new=1
    else warn "$u is not available on $P_source for GNOME $(_shell_major); skipped"; fi
  done
  # panel logo (colour in the filename: GNOME caches icons by path)
  sed "s/fill:$VENDORED_MAIN/fill:$P_logo_color/g" icons/gnome-logo.svg > "$(_logo_path)"
  # enabled-extensions: merge ours in; take ours out of disabled-extensions
  local ini; ini=$(mktemp)
  printf '[org/gnome/shell]\nenabled-extensions=%s\n' "$(_uuids | python3 -c 'import sys; print([l.strip() for l in sys.stdin if l.strip()])')" > "$ini"
  _dt apply --base / --ini "$ini" --prev "$LS_USER_STATE/gnome-extensions-enabled.prev.json" --merge /org/gnome/shell/enabled-extensions
  rm -f "$ini"
  local dis; dis=$(gsettings get org.gnome.shell disabled-extensions)
  for u in $(_uuids); do
    if [[ $dis == *"'$u'"* ]]; then echo "$u" >> "$LS_USER_STATE/gnome-extensions.undisabled"; fi
  done
  if [[ -s $LS_USER_STATE/gnome-extensions.undisabled ]]; then
    gsettings set org.gnome.shell disabled-extensions "$(python3 -c '
import ast,sys; cur=ast.literal_eval(sys.argv[1] if sys.argv[1] != "@as []" else "[]"); drop=set(open(sys.argv[2]).read().split())
print([x for x in cur if x not in drop])' "$dis" "$LS_USER_STATE/gnome-extensions.undisabled")"
  fi
  step "applying extension settings"
  _settings apply
  (( new )) && info "new extensions activate after you log out and back in"
  return 0
}

module_remove() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] would restore extension settings and uninstall: $(cat "$LS_USER_STATE/gnome-extensions.installed" 2>/dev/null | tr '\n' ' ')"; return 0; }
  _dt remove --base /org/gnome/shell/extensions/ --prev "$LS_USER_STATE/gnome-extensions.prev.json"
  _dt remove --base / --prev "$LS_USER_STATE/gnome-extensions-enabled.prev.json"
  if [[ -s $LS_USER_STATE/gnome-extensions.undisabled ]]; then
    local cur; cur=$(gsettings get org.gnome.shell disabled-extensions)
    gsettings set org.gnome.shell disabled-extensions "$(python3 -c '
import ast,sys; cur=ast.literal_eval(sys.argv[1] if sys.argv[1] != "@as []" else "[]"); add=open(sys.argv[2]).read().split()
print(cur+[x for x in add if x not in cur])' "$cur" "$LS_USER_STATE/gnome-extensions.undisabled")"
    rm -f "$LS_USER_STATE/gnome-extensions.undisabled"
  fi
  local u
  if [[ -r $LS_USER_STATE/gnome-extensions.installed ]]; then
    while IFS= read -r u; do [[ -n $u ]] && gnome-extensions uninstall "$u" || true; done < "$LS_USER_STATE/gnome-extensions.installed"
    rm -f "$LS_USER_STATE/gnome-extensions.installed"
  fi
  rm -f "$ICON_DIR"/gnome-logo-*.svg
}

module_status() {
  local u missing=() s
  for u in $(_uuids); do gnome-extensions info "$u" >/dev/null 2>&1 || missing+=("$u"); done
  if [[ -n $P_file ]]; then s=$(_settings status | tail -1); else s=installed; fi
  if [[ $s == not-installed ]]; then echo "not-installed"
  elif (( ${#missing[@]} )) || [[ $s != installed ]]; then echo "partial (${#missing[@]} not installed; settings: $s)"
  else echo "installed"; fi
}
module_capture() { python3 "$LS_REPO/lib/dconf_tool.py" capture --base /org/gnome/shell/extensions/; }
