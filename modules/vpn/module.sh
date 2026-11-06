# shellcheck shell=bash disable=SC2034,SC2154,SC1090  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="VPN tools, any of: Tailscale, NetBird, Proton VPN (with their tray icons), WireGuard, OpenVPN, OpenConnect"
MODULE_NEEDS_ROOT=1
# One file per service here, each defining NAME_add, NAME_remove, NAME_status (prints nothing when complete,
# "skipped: …" when it can't apply on this system, else what's missing) and NAME_stamp (succeeds when it's in use).
# Signing in, auth keys and connections are never decal's: you sign in on each machine.
SERVICES=(tailscale netbird protonvpn wireguard openvpn openconnect)
ST="$LS_STATE/vpn"
REC="$ST/services"   # the services decal set up here, one per line
# shellcheck source=/dev/null
source "$MODULE_DIR/nm.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/tailscale.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/netbird.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/protonvpn.sh"

_wanted() { local s; for s in "${P_install[@]}"; do if [[ $s == "$1" ]]; then return 0; fi; done; return 1; }
_mark() { rec_has "$REC" "$1" || state_append "$REC" "$1"; }   # before a service's first change: remove can undo it
_take_off() { "$1_remove"; state_drop "$REC" "$1"; }
_join() { local out="" x; for x; do out+="${out:+, }$x"; done; printf '%s' "$out"; }
_os_release() { ( . "$(sys_path /etc/os-release)" 2>/dev/null; eval "printf '%s' \"\${$1:-}\"" ); }   # VAR: decal's own names only

# system services: enabled by their link (works before a Fedora Atomic reboot too, like docker), started when the unit
# is on the running system; recorded only when decal turned them on, so remove never turns off one you had on
_wants() { sys_path "/etc/systemd/system/multi-user.target.wants/$1"; }
_svc_enabled() { [[ -L $(_wants "$1") || -e $(_wants "$1") ]] || systemctl is-enabled --quiet "$1" 2>/dev/null; }
_svc_on() {
  _svc_enabled "$1" && return 0
  step "turning on $1"
  state_append "$ST/enabled" "$1"
  srun mkdir -p "$(dirname "$(_wants "$1")")"; srun ln -s "/usr/lib/systemd/system/$1" "$(_wants "$1")"
  if [[ -e $(sys_path "/usr/lib/systemd/system/$1") ]]; then
    srun systemctl daemon-reload; srun systemctl start "$1" || warn "$1 didn't start: see systemctl status $1"
  fi
}
_svc_off() {
  rec_has "$ST/enabled" "$1" || return 0
  if [[ -e $(sys_path "/usr/lib/systemd/system/$1") ]]; then srun systemctl stop "$1" 2>/dev/null || true; fi
  srun rm -f "$(_wants "$1")"; srun systemctl daemon-reload 2>/dev/null || true
  state_drop "$ST/enabled" "$1"
}

module_add() {
  local s
  for s in "${SERVICES[@]}"; do
    if _wanted "$s"; then "${s}_add"; elif rec_has "$REC" "$s"; then _take_off "$s"; fi
  done
}
module_remove() {
  local i
  for (( i = ${#SERVICES[@]} - 1; i >= 0; i-- )); do
    if rec_has "$REC" "${SERVICES[$i]}"; then _take_off "${SERVICES[$i]}"; fi
  done
  if [[ -e $REC ]]; then srun rm -f "$REC"; fi
}
# remove --only TAG: P_install holds only the services the tag added
MODULE_CAN_DROP=1
module_drop() { local s; for s in "${P_install[@]}"; do if rec_has "$REC" "$s"; then _take_off "$s"; fi; done; }
module_status() {
  local s why ok=() todo=() missing=0
  for s in "${P_install[@]}"; do
    why=$("${s}_status")
    case $why in
      "") ok+=("$s") ;;
      skipped*) ok+=("$s: ${why#skipped: }") ;;
      "not installed") todo+=("$s: not installed"); missing=$(( missing + 1 )) ;;
      *) todo+=("$s: $why") ;;
    esac
  done
  if (( ${#P_install[@]} == 0 || missing == ${#P_install[@]} )); then echo not-installed
  elif (( ${#todo[@]} )); then echo "partial ($(_join "${todo[@]}" "${ok[@]}"))"
  else echo "installed ($(_join "${ok[@]}"))"; fi
}
