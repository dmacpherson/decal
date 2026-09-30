# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile (P_*)
MODULE_DESC="Boot splash + LUKS password prompt (plymouth theme)"
MODULE_NEEDS_ROOT=1
CONF=/etc/plymouth/plymouthd.conf
_alt_path() { echo "/usr/share/plymouth/themes/$P_theme/$P_theme.plymouth"; }
ALT_REC="$LS_STATE/plymouth/alternative"   # the alternative this module registered (Debian/Ubuntu)
_alt_remove() {
  [[ -e $ALT_REC ]] || return 0
  local a; a=$(cat "$ALT_REC"); [[ -n $a ]] || a=$(_alt_path)   # older records were empty
  srun update-alternatives --remove default.plymouth "$a" || true; srun rm -f "$ALT_REC"
}
_themes_root() {
  local a=(--path "$P_path"); [[ -n $P_ref ]] && a+=(--ref "$P_ref")
  ls_fetch "$P_source" "${a[@]}" || die "could not fetch plymouth themes from $P_source"
}
module_fetch() { _themes_root >/dev/null; }

module_add() {
  local src; src="$(_themes_root)/$P_theme"
  [[ $LS_DRY_RUN == 1 || -d $src ]] || die "plymouth theme '$P_theme' not found in $P_source${P_path:+ ($P_path)}"
  pkg_install plymouth plymouth plymouth-script-plugin
  # Adopt a hand-made install: remember the pristine config, not the hand-edited one.
  if [[ -r $(sys_path /usr/etc/plymouth/plymouthd.conf) ]] && grep -qx "Theme=$P_theme" "$(sys_path "$CONF")" 2>/dev/null; then
    etc_seed_backup plymouth "$CONF" < "$(sys_path /usr/etc/plymouth/plymouthd.conf)"
    # the hand install also switched on local initramfs regeneration; stock had it off
    if [[ $PLATFORM == fedora-atomic ]]; then initramfs_seed_prior disabled; fi
  fi
  printf '[Daemon]\nTheme=%s\n' "$P_theme" | etc_write plymouth "$CONF"
  if [[ $LS_DRY_RUN == 1 && ! -d $src ]]; then log "[dry-run] install plymouth theme $P_theme from $P_source"
  else FILES_REPLACES="plymouth-theme-$P_theme" files_install plymouth "$src" "/usr/share/plymouth/themes/$P_theme"; fi
  if [[ $PLATFORM == debian ]] && have update-alternatives && [[ $LS_DRY_RUN != 1 ]] \
     && [[ "$(plymouth-set-default-theme 2>/dev/null)" != "$P_theme" ]]; then
    if [[ -e $ALT_REC && $(cat "$ALT_REC") != "$(_alt_path)" ]]; then _alt_remove; fi
    srun update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$(_alt_path)" 200
    srun update-alternatives --set default.plymouth "$(_alt_path)"
    _alt_path | swrite "$ALT_REC"
  fi
  initramfs_require plymouth
  grep -qwE 'splash|rhgb' "$(sys_path /proc/cmdline)" 2>/dev/null || warn "kernel cmdline has no 'splash'/'rhgb': the splash will not show until you add 'splash'"
  if [[ $PLATFORM == arch ]] && ! grep -qE '^HOOKS=.*\bplymouth\b' "$(sys_path /etc/mkinitcpio.conf)" 2>/dev/null; then
    warn "add 'plymouth' to HOOKS in /etc/mkinitcpio.conf (after 'systemd' or 'udev', before 'sd-encrypt'/'encrypt'), then run: sudo mkinitcpio -P"
  fi
}

module_remove() {
  _alt_remove
  etc_restore plymouth "$CONF"
  files_remove plymouth
  initramfs_release plymouth
  pkg_remove plymouth
}

module_status() {
  local files=0 conf=0
  files_installed plymouth && files=1
  grep -qx "Theme=$P_theme" "$(sys_path "$CONF")" 2>/dev/null && conf=1
  if (( files && conf )); then
    if [[ $PLATFORM == fedora-atomic ]] && ! rpm -q --quiet "decal-plymouth"; then echo "installed (reboot pending)"; else echo "installed"; fi
  elif (( ! files )) && [[ -d $(sys_path "/usr/share/plymouth/themes/$P_theme") ]]; then echo "not-installed (theme present but unmanaged; run add to adopt)"
  elif (( files || conf )); then echo "partial (theme files: $files, config: $conf)"
  else echo "not-installed"; fi
}
