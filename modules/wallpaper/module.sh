# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile (P_*)
MODULE_DESC="Login-screen background (blurred) + desktop wallpaper, from your profile"
MODULE_NEEDS_ROOT=1
UNIT=/etc/systemd/system/decal-gdm-background.service
HELPER=/usr/local/libexec/decal-gdm-background
DESK_IMG="$HOME/.local/share/backgrounds/decal-wallpaper.jpg"

_stock() { local p=/usr/share/gnome-shell/gnome-shell-theme.gresource
  [[ -e $(sys_path /usr/share/gnome-shell/gdm-theme.gresource) ]] && p=/usr/share/gnome-shell/gdm-theme.gresource
  readlink -m "$(sys_path "$p")"; }
_has_gdm() { have gdm || [[ -x $(sys_path /usr/sbin/gdm) || -x $(sys_path /usr/sbin/gdm3) ]]; }
_has_bg_schema() { gsettings list-keys org.gnome.desktop.background >/dev/null 2>&1; }
# _img login|desktop : local path of the image for that target (profile path or downloaded URL)
_img() {
  local v
  if [[ $1 == login ]]; then v=${P_login_image:-$P_image}; else v=${P_desktop_image:-$P_image}; fi
  [[ -n $v ]] || die "[wallpaper] needs 'image' (or '$1.image') in your profile"
  if [[ $v == https://* ]]; then ls_fetch "$v"; else echo "$v"; fi
}
module_fetch() {
  local v
  for v in "$P_image" "$P_login_image" "$P_desktop_image"; do if [[ $v == https://* ]]; then ls_fetch "$v" >/dev/null; fi; done
}

_login_add() {  # IMG
  local img=$1 stock mons tmp; stock=$(_stock)
  [[ -f $stock ]] || { warn "GNOME Shell theme not found at $stock: login background skipped"; return 0; }
  tmp=$(mktemp -d)
  mons=${DECAL_MONITORS_JSON:-$(python3 monitors.py)}   # override: headless / tests
  log "building login background for layout $mons"
  # our own mount covers the stock path once installed: read the real file underneath it
  step "building the login background"
  srun bash gdm-background stock-copy "$stock" "$tmp/stock.gresource"
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] build.sh $img $P_login_blur $P_login_brightness ..."; else
    bash build.sh "$img" "$P_login_blur" "$P_login_brightness" "$mons" "$tmp/stock.gresource" "$tmp/gnome-shell-theme.gresource"; fi
  srun mkdir -p "$LS_STATE/wallpaper"
  [[ $LS_DRY_RUN == 1 ]] || srun cp "$tmp/gnome-shell-theme.gresource" "$LS_STATE/wallpaper/"
  printf '%s\n' "$stock" | swrite "$LS_STATE/wallpaper/stock-path"
  if [[ $LS_DRY_RUN != 1 ]]; then sha256sum "$tmp/stock.gresource" | cut -d' ' -f1 | swrite "$LS_STATE/wallpaper/stock.sha256"; fi
  # system-wide layout: mutter reads it for users without their own (GDM's dynamic greeter
  # users included); the user's ~/.config/monitors.xml still wins in their session
  if [[ -r $HOME/.config/monitors.xml ]]; then etc_write wallpaper /etc/xdg/monitors.xml < "$HOME/.config/monitors.xml"; fi
  step "installing the login background"
  etc_write wallpaper "$HELPER" < gdm-background; srun chmod 0755 "$(sys_path "$HELPER")"
  have restorecon && srun restorecon -F "$(sys_path "$HELPER")"
  etc_write wallpaper "$UNIT" <<EOF
[Unit]
Description=decal: custom GDM login background
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HELPER mount
ExecStop=$HELPER umount

[Install]
WantedBy=graphical.target
EOF
  srun systemctl daemon-reload
  srun systemctl enable decal-gdm-background.service
  srun systemctl restart decal-gdm-background.service
  rm -rf "$tmp"
  info "login background applies at the next logout"
}

_desktop_add() {  # IMG
  step "setting the desktop wallpaper"
  local img=$1 prev="$LS_USER_STATE/wallpaper.prev"
  run mkdir -p "$(dirname "$DESK_IMG")" "$LS_USER_STATE"
  if (( P_desktop_blur == 0 && P_desktop_brightness == 100 )); then run cp "$img" "$DESK_IMG"
  else run bash desktop.sh "$img" "$P_desktop_blur" "$P_desktop_brightness" "$DESK_IMG"; fi
  if [[ ! -e $prev && $LS_DRY_RUN != 1 ]]; then
    { echo "picture-uri=$(gsettings get org.gnome.desktop.background picture-uri)"
      echo "picture-uri-dark=$(gsettings get org.gnome.desktop.background picture-uri-dark)"; } > "$prev"
  fi
  run gsettings set org.gnome.desktop.background picture-uri "file://$DESK_IMG"
  run gsettings set org.gnome.desktop.background picture-uri-dark "file://$DESK_IMG"
}

# the login background is built in a container, or with ImageMagick 7 on the host (run-image-job.sh)
_can_build() { have podman || have docker || { have magick && have glib-compile-resources; }; }
module_add() {
  # resolve (download) the images first: nothing changes if one can't be fetched
  local limg="" dimg=""
  if [[ $P_login_enable == true ]] && _has_gdm; then limg=$(_img login); fi
  if [[ $P_desktop_enable == true ]] && _has_bg_schema; then dimg=$(_img desktop); fi
  if [[ $P_login_enable != true ]]; then _login_remove
  elif ! _has_gdm; then warn "GDM not found: login background skipped"
  elif ! _can_build; then   # checked before any package hook goes in
    warn "login background skipped: it needs podman or docker, or ImageMagick 7 (magick) and glib-compile-resources"
  elif ! txn_hooks_add wallpaper "$HELPER umount" "$HELPER mount"; then
    warn "login background skipped: this system can't unmount it around package updates (it would break gnome-shell upgrades)"
  else _login_add "$limg"; fi
  if [[ $P_desktop_enable != true ]]; then _desktop_remove
  elif [[ -n $dimg ]]; then _desktop_add "$dimg"
  else warn "GNOME background settings not found: desktop wallpaper skipped"; fi
}

_login_remove() {
  local had_unit=0; [[ -e $(sys_path "$UNIT") ]] && had_unit=1
  if (( had_unit )); then srun systemctl disable --now decal-gdm-background.service || true; fi
  txn_hooks_remove wallpaper
  pkg_remove wallpaper   # the package the hooks needed (dnf5 actions plugin), if we installed it
  etc_restore wallpaper "$UNIT"; etc_restore wallpaper "$HELPER"
  if (( had_unit )); then srun systemctl daemon-reload; fi
  etc_restore wallpaper /etc/xdg/monitors.xml
  if [[ -d $LS_STATE/wallpaper ]]; then srun rm -rf "$LS_STATE/wallpaper"; fi
}
_desktop_remove() {
  local prev="$LS_USER_STATE/wallpaper.prev" k v
  if [[ -r $prev ]]; then
    while IFS='=' read -r k v; do run gsettings set org.gnome.desktop.background "$k" "$v"; done < "$prev"
    run rm -f "$prev"
  fi
  if [[ -e $DESK_IMG ]]; then run rm -f "$DESK_IMG"; fi
}
module_remove() { _login_remove; _desktop_remove; }

module_status() {
  local unit=0 fresh=0 desk=0
  systemctl is-enabled decal-gdm-background.service >/dev/null 2>&1 && unit=1
  # the boot helper (root) records whether the build still matches the stock theme
  case $(cat "$LS_STATE/wallpaper/state" 2>/dev/null) in
    stale) echo "stale (GNOME updated the stock theme; run: ./decal add wallpaper)"; return 0 ;;
    label-failed) echo "partial (SELinux relabel of the login theme failed; stock login screen in use)"; return 0 ;;
    mounted) fresh=1 ;;
  esac
  [[ $(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null) == "'file://$DESK_IMG'" ]] && desk=1
  if (( unit && fresh && desk )); then echo installed
  elif (( unit || desk )); then echo "partial (login: $unit, desktop: $desk)"
  else echo not-installed; fi
}
# stamp: the desktop picture, if you changed it (a distro slideshow .xml is the distro's)
module_stamp() {
  have dconf || return 0
  local u f; u=$(dconf read /org/gnome/desktop/background/picture-uri 2>/dev/null | tr -d "'")
  [[ -n $u && $u == file://* ]] || return 0
  f=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1][7:]))' "$u")
  [[ -r $f && $f != *.xml ]] || return 0
  stamp_note "wallpaper: your desktop picture"
  printf '[wallpaper]\nimage = "%s"\n' "$(stamp_copy "$f" "wallpaper/$(basename "$f")")"
}
