# shellcheck shell=bash disable=SC2154  # sourced from common.sh
# Login-screen (GDM) dconf keys on any distro: a system-db:gdm keyfile (Fedora, Arch, Bazzite)
# or /etc/gdm3/greeter.dconf-defaults (Debian, Ubuntu). Backed up/restored per owner.
GDM_DEB_FILE=/etc/gdm3/greeter.dconf-defaults
gdm_mode() {
  # dconf reads /etc/dconf/profile first, then the distro's /usr/share/dconf/profile
  if grep -qs 'system-db:gdm' "$(sys_path /etc/dconf/profile/gdm)" "$(sys_path /usr/share/dconf/profile/gdm)"; then echo dconf
  elif [[ -e $(sys_path "$GDM_DEB_FILE") ]]; then echo debian
  else echo none; fi
}
gdm_keyfile() { echo "/etc/dconf/db/gdm.d/95-decal-$1"; }
# rebuild only the gdm database: "dconf update" also makes every running session re-read all of its
# settings, and GNOME Shell 50 can crash on that (stale app-folder handlers), logging the user out
_gdm_compile() { srun dconf compile "$(sys_path /etc/dconf/db/gdm)" "$(sys_path /etc/dconf/db/gdm.d)"; }
# gdm_set OWNER SECTION KEY VALUE [KEY VALUE...] : VALUE is a GVariant literal ('text', 24, true)
gdm_set() {
  local owner=$1 section=$2 t i k; shift 2
  case $(gdm_mode) in
    dconf)
      { echo "[$section]"; while (( $# )); do echo "$1=$2"; shift 2; done; } | etc_write "$owner" "$(gdm_keyfile "$owner")"
      _gdm_compile ;;
    debian)
      # the file is shared by several owners: record each key's previous value once, then set it
      local rec; rec=$(_gdm_rec "$owner"); t=$(mktemp -d); cp "$(sys_path "$GDM_DEB_FILE")" "$t/cur"
      cat "$rec" 2>/dev/null > "$t/rec" || true
      for (( i = 1; i < $#; i += 2 )); do
        k=${!i}
        if ! grep -q "^$section	$k	" "$t/rec"; then
          printf '%s\t%s\t%s\n' "$section" "$k" "$(python3 "$LS_LIB/ini_set.py" --get "$t/cur" "$section" "$k" || echo "$GDM_ABSENT")" >> "$t/rec"
        fi
      done
      python3 "$LS_LIB/ini_set.py" "$t/cur" "$section" "$@" > "$t/new"
      swrite "$rec" < "$t/rec"; swrite "$(sys_path "$GDM_DEB_FILE")" < "$t/new"; rm -rf "$t" ;;
    none) warn "no GDM dconf profile found: login-screen setting skipped" ;;
  esac
}
GDM_ABSENT=$'\x01absent'
_gdm_rec() { echo "$LS_STATE/gdm/$1.keys"; }   # Debian: section<TAB>key<TAB>previous value (or GDM_ABSENT)
_gdm_deb_restore() {
  local rec sec k v t; rec=$(_gdm_rec "$1")
  [[ -r $rec ]] || return 0
  t=$(mktemp -d); cp "$(sys_path "$GDM_DEB_FILE")" "$t/f"
  while IFS=$'\t' read -r sec k v; do
    if [[ $v == "$GDM_ABSENT" ]]; then python3 "$LS_LIB/ini_set.py" --unset "$t/f" "$sec" "$k" > "$t/n"
    else python3 "$LS_LIB/ini_set.py" "$t/f" "$sec" "$k" "$v" > "$t/n"; fi
    mv "$t/n" "$t/f"
  done < "$rec"
  swrite "$(sys_path "$GDM_DEB_FILE")" < "$t/f"; srun rm -f "$rec"; rm -rf "$t"
}
# gdm_restore OWNER : undo gdm_set for OWNER (silent no-op if never set)
gdm_restore() {
  local owner=$1
  if [[ -r $(_gdm_rec "$owner") && -e $(sys_path "$GDM_DEB_FILE") ]]; then _gdm_deb_restore "$owner"; fi
  [[ -e $LS_STATE/backups/$owner ]] || return 0
  etc_restore "$owner" "$(gdm_keyfile "$owner")"; etc_restore "$owner" "$GDM_DEB_FILE"   # (older runs backed up the whole Debian file)
  if [[ $(gdm_mode) == dconf ]]; then _gdm_compile; fi
}
# gdm_has OWNER KEY VALUE : true if OWNER's setting KEY=VALUE is in place
gdm_has() {
  local f
  case $(gdm_mode) in dconf) f=$(gdm_keyfile "$1") ;; debian) f=$GDM_DEB_FILE ;; *) return 1 ;; esac
  grep -qxF "$2=$3" "$(sys_path "$f")" 2>/dev/null
}
