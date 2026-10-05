# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Software (Flathub + native) and default apps, from your profile's [apps]"
MODULE_NEEDS_ROOT=1
BRAVE_STATE="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Local State"
DEF_PREV="$LS_USER_STATE/apps-defaults.prev"
MANAGED="$LS_STATE/apps/managed"
REMOTE_REC="$LS_STATE/apps/remote"   # the Flatpak remote decal added (none when it was already there)
REMOVED_FP="$LS_STATE/apps/removed-flatpaks"
SHOW_MARK="# decal: shown by [apps] show (decal removes this copy when the app leaves the list)"
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
    origin=$(flatpak info --system --show-origin -- "$id" 2>/dev/null || echo "$P_remote")
    srun flatpak uninstall --system --noninteractive -y -- "$id"
    state_append "$REMOVED_FP" "$id $origin"
  done
  if (( ${#P_remove_packages[@]} )); then pkg_uninstall apps "${P_remove_packages[@]}"; fi
}
_unwanted_restore() {
  local id origin
  if [[ -r $REMOVED_FP ]]; then
    while read -r id origin; do if [[ -n $id ]]; then srun flatpak install --system --noninteractive -y -- "$origin" "$id"; fi; done < "$REMOVED_FP"
    srun rm -f "$REMOVED_FP"
  fi
  pkg_restore apps
}
_fp_present() { flatpak info --system -- "$1" >/dev/null 2>&1; }
_desktop_exists() {
  local d dirs; IFS=: read -ra dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-$(sys_path /usr/local/share):$(sys_path /usr/share)}:$(sys_path /var/lib/flatpak/exports/share):$HOME/.local/share/flatpak/exports/share"
  for d in "${dirs[@]}"; do [[ -e $d/applications/$1 ]] && return 0; done; return 1
}
# show: launchers the distro hides (Hidden=/NoDisplay=true) get your own copy without that, which GNOME prefers;
# decal only ever deletes copies carrying its mark
_show_dir() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/applications"; }
_show_ours() { [[ -e $1 ]] && head -1 "$1" | grep -qxF "$SHOW_MARK"; }
_show_src() {
  local d dirs; IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-$(sys_path /usr/local/share):$(sys_path /usr/share)}"
  if have brew; then dirs+=("$(brew --prefix)/share"); fi   # Homebrew's launchers aren't on GNOME's path at all
  for d in "${dirs[@]}"; do if [[ -r $d/applications/$1.desktop ]]; then echo "$d/applications/$1.desktop"; return 0; fi; done
  return 1
}
_shown() { local f; f="$(_show_dir)/$1.desktop"; [[ -r $f ]] && ! grep -qE '^(Hidden|NoDisplay)=true' "$f"; }
_show_add() {
  local id f src u; u=$(_show_dir)
  for f in "$u"/*.desktop; do   # decal's copies of launchers no longer listed
    if _show_ours "$f" && ! printf '%s\n' "${P_show[@]}" | grep -qxF "$(basename "$f" .desktop)"; then run rm -f "$f"; fi
  done
  for id in "${P_show[@]}"; do
    f="$u/$id.desktop"
    if [[ -e $f ]] && ! _show_ours "$f"; then warn "$id: you have your own $f; left alone"; continue; fi
    src=$(_show_src "$id") || { warn "$id: no launcher $id.desktop installed; nothing to show"; continue; }
    if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] show $id: copy of $src without Hidden/NoDisplay"; continue; fi
    mkdir -p "$u"; { echo "$SHOW_MARK"; grep -vE '^(Hidden|NoDisplay)=' "$src"; } > "$f"
  done
}
_show_remove() { local f; for f in "$(_show_dir)"/*.desktop; do if _show_ours "$f"; then run rm -f "$f"; fi; done; }
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
      if flatpak remote-info --system -- "$P_remote" "$app" >/dev/null 2>&1; then
        srun flatpak install --system --noninteractive -y -- "$P_remote" "$app"
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
import os, shutil, sys
p, drop = sys.argv[1], set(sys.argv[2:]); out = []; sec = ""
p = os.path.realpath(p)   # a link into a dotfiles folder: edit the real file, keep the link
try: lines = open(p).read().split("\n")
except FileNotFoundError: sys.exit(0)
for l in lines:
    if l.startswith("["): sec = l
    if sec == "[Default Applications]" and l.split("=", 1)[0] in drop: continue
    out.append(l)
open(p + ".decal-new", "w").write("\n".join(out)); shutil.copymode(p, p + ".decal-new"); os.replace(p + ".decal-new", p)
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
  # the remote is decal's only when flatpak listed its remotes (turned-off ones too) and it wasn't there
  local remotes
  if remotes=$(flatpak remotes --system --show-disabled --columns=name 2>/dev/null) && ! grep -qxF -- "$P_remote" <<<"$remotes"; then
    echo "$P_remote" | swrite "$REMOTE_REC"   # recorded first: an interrupted add still gets undone
  fi
  srun flatpak remote-add --system --if-not-exists -- "$P_remote" "$P_remote_url"
  local missing=() id
  for id in "${P_flatpaks[@]}"; do _fp_present "$id" || missing+=("$id"); done
  if (( ${#missing[@]} )); then
    # only what decal installs is decal's (an app you already had is never uninstalled by remove); recorded first,
    # so an install stopped halfway is still undone (remove skips the ones that never got in)
    for id in "${missing[@]}"; do state_append "$MANAGED" "$id"; done
    step "installing ${missing[*]} from Flathub"; srun flatpak install --system --noninteractive -y -- "$P_remote" "${missing[@]}"
  fi
  if (( ${#P_packages[@]} )); then pkg_install apps "${P_packages[@]}"; fi
  _unwanted_add
  _defaults_add
  _show_add
  if _brave_used && ! _brave_origin; then
    info "One-time step: open Brave > Settings > System > 'Brave Origin' > Proceed with Origin for free on Linux"
  fi
  return 0
}
module_remove() {
  _defaults_remove
  _show_remove
  local id present=() extra=()
  if [[ $P_purge_data == true ]]; then extra=(--delete-data); fi
  if [[ -r $MANAGED ]]; then
    while IFS= read -r id; do if [[ -n $id ]] && _fp_present "$id"; then present+=("$id"); fi; done < "$MANAGED"
  fi
  if (( ${#present[@]} )); then   # runtimes only ours needed go too
    srun flatpak uninstall --system --noninteractive -y "${extra[@]}" -- "${present[@]}"
    srun flatpak uninstall --system --unused --noninteractive -y
  fi
  if [[ -e $MANAGED ]]; then srun rm -f "$MANAGED"; fi
  if [[ -r $REMOTE_REC ]]; then   # without force: flatpak keeps it while anything still comes from it
    srun flatpak remote-delete --system -- "$(cat "$REMOTE_REC")" 2>/dev/null || info "$(cat "$REMOTE_REC") is still in use: kept"
    srun rm -f "$REMOTE_REC"
  fi
  _unwanted_restore
  pkg_remove apps
}
# remove --only TAG: P_flatpaks / P_show hold only what the tag added; the rest of the module stays
MODULE_CAN_DROP=1
module_drop() {
  local id f present=()
  for id in "${P_flatpaks[@]}"; do
    grep -qxF "$id" "$MANAGED" 2>/dev/null || { info "$id: not installed by decal; left alone"; continue; }
    if _fp_present "$id"; then present+=("$id"); fi
    if [[ $LS_DRY_RUN != 1 ]]; then state_drop "$MANAGED" "$id"; fi
  done
  if (( ${#present[@]} )); then
    step "uninstalling ${present[*]}"
    if [[ $P_purge_data == true ]]; then srun flatpak uninstall --system --noninteractive -y --delete-data -- "${present[@]}"
    else srun flatpak uninstall --system --noninteractive -y -- "${present[@]}"; fi
    srun flatpak uninstall --system --unused --noninteractive -y
  fi
  for id in "${P_show[@]}"; do f="$(_show_dir)/$id.desktop"; if _show_ours "$f"; then run rm -f "$f"; fi; done
}
module_status() {
  local id have_n=0 total=0 missing=() hidden=() base notes=()
  for id in "${P_flatpaks[@]}"; do total=$((total+1)); if _fp_present "$id"; then have_n=$((have_n+1)); else missing+=("$id"); fi; done
  for id in "${P_show[@]}"; do _shown "$id" || hidden+=("$id"); done
  if (( total == have_n )); then base=installed; elif (( have_n == 0 )); then base=not-installed; else base=partial; notes+=("missing: ${missing[*]}"); fi
  if (( ${#hidden[@]} )); then [[ $base != installed ]] || base=partial; notes+=("not shown: ${hidden[*]}"); fi
  notes+=("defaults: $(_defaults_ok && echo set || echo not set)")
  if _brave_used; then notes+=("Brave Origin: $(_brave_origin && echo yes || echo no)"); fi
  echo "$base ($(printf '%s; ' "${notes[@]}" | sed 's/; $//'))"
}
# stamp: what you changed after the OS was installed. Flatpaks: flatpak's own history (apps installed since, still
# here; the distro's apps you removed). Packages: what's layered on an Atomic image (rpm-ostree records exactly that;
# other systems: not stamped). Default apps from your mimeapps.list; launchers decal shows.
STAMP_LIVE=1
STAMP_OWNED_PKGS="moby-engine docker-compose docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin plymouth-plugin-script"
module_stamp() {
  local apps=() gone=() pkgs=() rmpkgs=() show=() id ch role d f best n out=()
  declare -A last=() ever=() roles=()
  if have flatpak; then
    local inst; inst=$(flatpak list --app --columns=application 2>/dev/null)
    while IFS=$'\t' read -r ch id; do
      [[ -n $id && $id != *.Locale && $id != *.Debug && $id != *.Sources ]] || continue   # an app's add-ons, not apps
      case $ch in *uninstall*) last[$id]=out ;; *install*) last[$id]=in; ever[$id]=1 ;; esac
    done < <(flatpak history --columns=change,application 2>/dev/null)
    for id in $(printf '%s\n' "${!last[@]}" | sort); do
      if [[ ${last[$id]} == in ]] && grep -qxF "$id" <<<"$inst"; then apps+=("$id")
      elif [[ ${last[$id]} == out && -z ${ever[$id]:-} ]] && ! grep -qxF "$id" <<<"$inst"; then gone+=("$id"); fi
    done
    if (( ${#last[@]} == 0 )) && [[ -n $inst ]]; then stamp_note "apps: flatpak has no install history here (journal trimmed?): flatpaks not stamped"; fi
  fi
  if have rpm-ostree; then
    while IFS= read -r id; do
      [[ -n $id && $id != decal-* && " $STAMP_OWNED_PKGS " != *" $id "* ]] && pkgs+=("$id")
    done < <(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin)["deployments"][0]
print("\n".join(d.get("requested-packages",[])))' 2>/dev/null)
    while IFS= read -r id; do [[ -n $id ]] && rmpkgs+=("$id"); done < <(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin)["deployments"][0]
print("\n".join(d.get("requested-base-removals",[])))' 2>/dev/null)
  fi
  # default apps: a role is yours when most of its types open with one app in your mimeapps.list
  f="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
  if [[ -r $f ]]; then
    while read -r role rest; do
      [[ -n $role && $role != \#* ]] || continue
      best=$(for m in $rest; do awk -F= -v m="$m" '/^\[/{s=$0} s=="[Default Applications]" && $1==m {split($2,a,";"); print a[1]}' "$f"; done | sort | uniq -c | sort -rn | head -1)
      n=${best%% *}; n=$(echo "$best" | awk '{print $1}'); d=$(echo "$best" | awk '{print $2}')
      if [[ -n $d ]] && (( n * 2 >= $(wc -w <<<"$rest") )); then roles[$role]=${d%.desktop}; fi
    done < "$MODULE_DIR/roles.list"
  fi
  for f in "$(_show_dir)"/*.desktop; do if _show_ours "$f"; then show+=("$(basename "$f" .desktop)"); fi; done
  (( ${#apps[@]} + ${#gone[@]} + ${#pkgs[@]} + ${#rmpkgs[@]} + ${#roles[@]} + ${#show[@]} )) || return 0
  stamp_note "apps: ${#apps[@]} flatpaks you installed${gone[*]:+, ${#gone[@]} removed}${pkgs[*]:+, ${#pkgs[@]} layered packages}, ${#roles[@]} default apps"
  echo "[apps]"
  if (( ${#apps[@]} )); then echo "flatpaks = $(toml_list "${apps[@]}")"; fi
  if (( ${#gone[@]} )); then echo "remove-flatpaks = $(toml_list "${gone[@]}")"; fi
  if (( ${#pkgs[@]} )); then echo "packages = $(toml_list "${pkgs[@]}")"; fi
  if (( ${#rmpkgs[@]} )); then echo "remove-packages = $(toml_list "${rmpkgs[@]}")"; fi
  if (( ${#show[@]} )); then echo "show = $(toml_list "${show[@]}")"; fi
  if (( ${#roles[@]} )); then
    echo "[apps.defaults]"
    for role in $(printf '%s\n' "${!roles[@]}" | sort); do echo "$role = \"${roles[$role]}\""; done
  fi
}
