# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Login-screen logo (hidden, or an image from your profile)"
MODULE_NEEDS_ROOT=1
_logo_dst() { echo "$LS_STATE/branding/logo.${P_login_logo##*.}"; }
_want() { if [[ -n $P_login_logo ]]; then echo "'$(_logo_dst)'"; else echo "''"; fi; }
module_add() {
  if [[ -n $P_login_logo ]]; then srun mkdir -p "$LS_STATE/branding"; srun cp "$P_login_logo" "$(_logo_dst)"; fi
  gdm_set branding org/gnome/login-screen logo "$(_want)"
}
module_remove() {
  gdm_restore branding
  if [[ -d $LS_STATE/branding ]]; then srun rm -rf "$LS_STATE/branding"; fi
}
module_status() {
  if [[ $(gdm_mode) == none ]]; then echo "n/a (no GDM)"; return 0; fi
  if gdm_has branding logo "$(_want)"; then echo installed; else echo not-installed; fi
}
