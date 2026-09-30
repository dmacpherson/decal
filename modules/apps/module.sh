# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Software (Flathub + native) and default apps, from your profile's [apps]"
MODULE_NEEDS_ROOT=1
BRAVE_STATE="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Local State"
DEF_PREV="$LS_USER_STATE/apps-defaults.prev"
MANAGED="$LS_STATE/apps/managed"
REMOVED_FP="$LS_STATE/apps/removed-flatpaks"
_contradictions() {
  local id
  for id in "${P_remove_flatpaks[@]}"; do
    if printf '%s\n' "${P_flatpaks[@]}" | grep -qxF "$id"; then die "$id is both in flatpaks and remove-flatpaks"; fi
    if (( ${#P_defaults[@]} )) && printf '%s\n' "${P_defaults[@]}" | grep -qxF "$id"; then die "$id is a default app and in remove-flatpaks"; fi
  done
  for id in "${P_remove_packages[@]}"; do
    if printf '%s\n' "${P_packages[@]}" | grep -qxF "$id"; then die "$id is both in packages and remove-packages"; fi
  done
}
_unwanted_add() {
  local id origin
  for id in "${P_remove_flatpaks[@]}"; do
    _fp_present "$id" || continue
    origin=$(flatpak info --system --show-origin "$id" 2>/dev/null || echo "$P_remote")
    srun flatpak uninstall --system --noninteractive -y "$id"
    state_append "$REMOVED_FP" "$id $origin"
  done
  if (( ${#P_remove_packages[@]} )); then pkg_uninstall apps "${P_remove_packages[@]}"; fi
}
_unwanted_restore() {
  local id origin
  if [[ -r $REMOVED_FP ]]; then
    while read -r id origin; do if [[ -n $id ]]; then srun flatpak install --system --noninteractive -y "$origin" "$id"; fi; done < "$REMOVED_FP"
    srun rm -f "$REMOVED_FP"
  fi
  pkg_restore apps
}
_fp_present() { flatpak info --system "$1" >/dev/null 2>&1; }
_desktop_exists() {
  local d dirs; IFS=: read -ra dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-$(sys_path /usr/local/share):$(sys_path /usr/share)}:$(sys_path /var/lib/flatpak/exports/share):$HOME/.local/share/flatpak/exports/share"
  for d in "${dirs[@]}"; do [[ -e $d/applications/$1 ]] && return 0; done; return 1
}
_role_mimes() { awk -v r="$1" '$1==r {$1=""; print}' "$MODULE_DIR/roles.list"; }
_roles() { if (( ${#P_defaults[@]} )); then printf '%s\n' "${!P_defaults[@]}" | sort; fi; }
_brave_used() { { printf '%s\n' "${P_flatpaks[@]}"; if (( ${#P_defaults[@]} )); then printf '%s\n' "${P_defaults[@]}"; fi; } | grep -qx com.brave.Browser; }
_brave_origin() {
  python3 -c 'import json,sys; o=json.load(open(sys.argv[1])).get("brave",{}).get("origin",{}); sys.exit(0 if o.get("free_tier_accepted") or o.get("purchase_validated") else 1)' "$BRAVE_STATE" 2>/dev/null
}

_defaults_add() {
  have xdg-mime || { warn "xdg-mime not found: default apps skipped"; return 0; }
  run mkdir -p "$LS_USER_STATE"
  local role app desk mimes m
  for role in $(_roles); do
    app=${P_defaults[$role]}; desk="$app.desktop"; mimes=$(_role_mimes "$role")
    if [[ -z $mimes ]]; then warn "unknown role '$role' (roles: $(grep -vE '^\s*(#|$)' "$MODULE_DIR/roles.list" | awk '{print $1}' | tr '\n' ' '))"; continue; fi
    if ! _desktop_exists "$desk"; then
      if flatpak remote-info --system "$P_remote" "$app" >/dev/null 2>&1; then
        srun flatpak install --system --noninteractive -y "$P_remote" "$app"
        state_append "$MANAGED" "$app"
      else
        warn "$role: $app is not installed and not on $P_remote; skipped"; continue
      fi
    fi
    if [[ $LS_DRY_RUN != 1 ]]; then
      for m in $mimes; do grep -q "^$m=" "$DEF_PREV" 2>/dev/null || echo "$m=$(xdg-mime query default "$m" 2>/dev/null)" >> "$DEF_PREV"; done
    fi
    # shellcheck disable=SC2086  # mimes is a word list
    run xdg-mime default "$desk" $mimes
    if [[ $role == browser ]] && have xdg-settings; then run xdg-settings set default-web-browser "$desk"; fi
  done
}
_defaults_remove() {
  [[ -r $DEF_PREV ]] || return 0
  local m d unset=()
  while IFS='=' read -r m d; do if [[ -n $d ]]; then run xdg-mime default "$d" "$m"; else unset+=("$m"); fi; done < "$DEF_PREV"
  if (( ${#unset[@]} )) && [[ $LS_DRY_RUN != 1 ]]; then
    python3 - "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" "${unset[@]}" <<'EOF'
import sys
p, drop = sys.argv[1], set(sys.argv[2:]); out = []; sec = ""
try: lines = open(p).read().split("\n")
except FileNotFoundError: sys.exit(0)
for l in lines:
    if l.startswith("["): sec = l
    if sec == "[Default Applications]" and l.split("=", 1)[0] in drop: continue
    out.append(l)
open(p, "w").write("\n".join(out))
EOF
  fi
  run rm -f "$DEF_PREV"
}
_defaults_ok() {
  local role m
  for role in $(_roles); do
    _desktop_exists "${P_defaults[$role]}.desktop" || continue
    for m in $(_role_mimes "$role"); do [[ $(xdg-mime query default "$m" 2>/dev/null) == "${P_defaults[$role]}.desktop" ]] || return 1; done
  done
}

module_add() {
  _contradictions
  pkg_install apps flatpak
  srun flatpak remote-add --system --if-not-exists "$P_remote" "$P_remote_url"
  local missing=() id
  for id in "${P_flatpaks[@]}"; do _fp_present "$id" || missing+=("$id"); state_append "$MANAGED" "$id"; done
  if (( ${#missing[@]} )); then step "installing ${missing[*]} from Flathub"; srun flatpak install --system --noninteractive -y "$P_remote" "${missing[@]}"; fi
  if (( ${#P_packages[@]} )); then pkg_install apps "${P_packages[@]}"; fi
  _unwanted_add
  _defaults_add
  if _brave_used && ! _brave_origin; then
    info "One-time step: open Brave > Settings > System > 'Brave Origin' > Proceed with Origin for free on Linux"
  fi
  return 0
}
module_remove() {
  _defaults_remove
  local id present=() extra=()
  if [[ $P_purge_data == true ]]; then extra=(--delete-data); fi
  if [[ -r $MANAGED ]]; then
    while IFS= read -r id; do if [[ -n $id ]] && _fp_present "$id"; then present+=("$id"); fi; done < "$MANAGED"
  fi
  if (( ${#present[@]} )); then srun flatpak uninstall --system --noninteractive -y "${extra[@]}" "${present[@]}"; fi
  if have flatpak && [[ -r $MANAGED ]]; then srun flatpak uninstall --system --unused --noninteractive -y; fi
  if [[ -e $MANAGED ]]; then srun rm -f "$MANAGED"; fi
  _unwanted_restore
  pkg_remove apps
}
module_status() {
  local id have_n=0 total=0 missing=() base extra
  for id in "${P_flatpaks[@]}"; do total=$((total+1)); if _fp_present "$id"; then have_n=$((have_n+1)); else missing+=("$id"); fi; done
  if (( total == have_n )); then base=installed; elif (( have_n == 0 )); then base=not-installed; else base="partial (missing: ${missing[*]}"; fi
  extra="defaults: $(_defaults_ok && echo set || echo not set)"
  if _brave_used; then extra+="; Brave Origin: $(_brave_origin && echo yes || echo no)"; fi
  if [[ $base == partial* ]]; then echo "$base; $extra)"; else echo "$base ($extra)"; fi
}
