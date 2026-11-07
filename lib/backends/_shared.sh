# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
# Backend-independent bookkeeping. Backends provide:
#   _pkg_name LOGICAL -> distro name ('' = provided elsewhere)
#   _pkg_present NAME ; _pkg_add NAMES... ; _pkg_del NAMES... ; _initramfs_rebuild ; _pkg_known NAME (optional)
_pkg_name() { if [[ -v "PKG_MAP[$1]" ]]; then printf '%s' "${PKG_MAP[$1]}"; else printf '%s' "$1"; fi; }

# pkg_known NAME : the distro has a package by that name (modules ask this, never the package manager itself)
pkg_known() { declare -F _pkg_known >/dev/null && _pkg_known "$1"; }

pkg_install() {
  local owner=$1 l n missing=(); shift
  for l in "$@"; do n=$(_pkg_name "$l"); [[ -z $n ]] && continue; _pkg_present "$n" || missing+=("$n"); done
  (( ${#missing[@]} )) || return 0
  # backends that can list packages also record the dependencies this install pulled in
  local before="" after=""
  if declare -F _pkg_snapshot >/dev/null; then before=$(_pkg_snapshot | sort -u); fi
  step "installing ${missing[*]}"
  _pkg_add "${missing[@]}"
  if [[ -n $before && $LS_DRY_RUN != 1 ]]; then
    after=$(_pkg_snapshot | sort -u)
    local deps; deps=$(comm -13 <(echo "$before") <(echo "$after") | grep -vxF -f <(printf '%s\n' "${missing[@]}") || true)
    if [[ -n $deps ]]; then
      local dcur=""; [[ -r $LS_STATE/pkgs/$owner.deps ]] && dcur=$(cat "$LS_STATE/pkgs/$owner.deps")
      { [[ -n $dcur ]] && printf '%s\n' "$dcur"; printf '%s\n' "$deps"; } | sort -u | swrite "$LS_STATE/pkgs/$owner.deps"
    fi
  fi
  local f="$LS_STATE/pkgs/$owner" cur=""
  [[ -r $f ]] && cur=$(cat "$f")
  { [[ -n $cur ]] && printf '%s\n' "$cur"; printf '%s\n' "${missing[@]}"; } | sort -u | swrite "$f"
}
pkg_remove() {
  local owner=$1 f="$LS_STATE/pkgs/$1" p others="" del=()
  [[ -r $f ]] || return 0
  local o; for o in "$LS_STATE"/pkgs/*; do [[ $o == "$f" || ! -r $o ]] || others+=$'\n'"$(cat "$o")"; done
  while IFS= read -r p; do
    [[ -z $p ]] && continue
    grep -qxF "$p" <<<"$others" && continue
    _pkg_present "$p" && del+=("$p")
  done < "$f"
  (( ${#del[@]} )) && _pkg_del "${del[@]}"
  srun rm -f "$f"
  # our recorded deps: remove only those the package manager now considers unneeded
  local df="$LS_STATE/pkgs/$owner.deps"
  if [[ -r $df ]]; then
    if declare -F _pkg_unneeded >/dev/null; then
      local gone; gone=$(grep -xF -f "$df" <(_pkg_unneeded) || true)
      # shellcheck disable=SC2086  # newline list of package names
      if [[ -n $gone ]]; then _pkg_del $gone; fi
    fi
    srun rm -f "$df"
  fi
}

files_install() {
  local owner=$1 src=$2 dest=$3 list=() rel
  # a new destination (e.g. another theme): take the previous files away first
  if [[ -r $LS_STATE/files/$owner.list && $(head -1 "$LS_STATE/files/$owner.list") != "$dest" ]]; then files_remove "$owner"; fi
  while IFS= read -r -d '' rel; do list+=("$dest/${rel#./}"); done < <(cd "$src" && find . -type f -print0 | sort -z)
  srun mkdir -p "$(sys_path "$dest")"
  srun cp -a "$src/." "$(sys_path "$dest")/"
  printf '%s\n' "$dest" "${list[@]}" | swrite "$LS_STATE/files/$owner.list"
}
files_remove() {
  local f="$LS_STATE/files/$1.list" dest p
  [[ -r $f ]] || return 0
  { read -r dest; while IFS= read -r p; do srun rm -f "$(sys_path "$p")"; done; } < "$f"
  [[ -d $(sys_path "$dest") ]] && srun find "$(sys_path "$dest")" -depth -type d -empty -delete
  srun rm -f "$f"
}
files_installed() {
  local f="$LS_STATE/files/$1.list" p
  [[ -r $f ]] || return 1
  while IFS= read -r p; do [[ -e $(sys_path "$p") ]] || return 1; done < <(tail -n +2 "$f")
  return 0
}

_initramfs_regen() {
  if [[ ${DECAL_SKIP_INITRAMFS:-0} == 1 ]]; then log "initramfs rebuild skipped (DECAL_SKIP_INITRAMFS=1)"; return 0; fi
  _initramfs_rebuild "$@"; need_reboot
}
# initramfs_dirty : something the initramfs holds changed this run (config, theme files, packages)
initramfs_dirty() { if [[ -n ${LS_RUNTMP:-} ]]; then : > "$LS_RUNTMP/initramfs-dirty"; fi; return 0; }
_initramfs_clean() { if [[ -n ${LS_RUNTMP:-} ]]; then rm -f "$LS_RUNTMP/initramfs-dirty"; fi; return 0; }
# initramfs_require OWNER : make sure the initramfs is (re)built for OWNER; rebuilds only when needed:
# a new owner, a change marked with initramfs_dirty, or a backend that isn't set up (_initramfs_stale)
initramfs_require() {
  local m="$LS_STATE/initramfs/$1"
  if declare -F _initramfs_prior_record >/dev/null; then _initramfs_prior_record; fi   # remember the pre-tool setup once
  if [[ ! -e $m ]]; then : | swrite "$m"; initramfs_dirty; fi
  if [[ -e ${LS_RUNTMP:-/nonexistent}/initramfs-dirty ]] || { declare -F _initramfs_stale >/dev/null && _initramfs_stale; }; then
    step "rebuilding the boot image (initramfs)"
    _initramfs_regen require "$1"; _initramfs_clean
  else log "initramfs already up to date"; fi
}
# initramfs_seed_prior enabled|disabled : declare what the setup was before this tool (e.g. when adopting a hand install)
initramfs_seed_prior() { if declare -F _initramfs_seed_prior >/dev/null; then _initramfs_seed_prior "$1"; fi; return 0; }
initramfs_release() { local m="$LS_STATE/initramfs/$1"; [[ -e $m ]] || return 0; srun rm -f "$m"; _initramfs_regen release "$1"; }

# txn_hooks_remove OWNER : undo txn_hooks_add (every backend's files; silent if none)
txn_hooks_remove() {
  local o=$1
  etc_restore "$o" "/etc/dnf/libdnf5-plugins/actions.d/decal-$o.actions"
  etc_restore "$o" "/etc/apt/apt.conf.d/80decal-$o"
  etc_restore "$o" "/etc/pacman.d/hooks/80-decal-$o-pre.hook"
  etc_restore "$o" "/etc/pacman.d/hooks/80-decal-$o-post.hook"
}
_pacman_hook() {  # WHEN CMD
  printf '[Trigger]\nOperation = Install\nOperation = Upgrade\nOperation = Remove\nType = Path\nTarget = *\n\n[Action]\nDescription = decal: %s\nWhen = %s\nExec = %s\n' "$2" "$1" "$2"
}

# pkg_uninstall OWNER NAME... : remove named native packages that are present; refuse any cascade
pkg_uninstall() {
  local owner=$1 n present=() extra rec f cur=""; shift
  for n in "$@"; do if _pkg_present "$n"; then present+=("$n"); fi; done
  (( ${#present[@]} )) || return 0
  extra=$(_pkg_del_check "${present[@]}") || die "won't remove ${present[*]}: ${extra:-the package manager refused}"
  [[ -z $extra ]] || die "removing ${present[*]} would also remove: $extra (add them to remove-packages too if that's what you want)"
  rec=$(_pkg_uninstall_names "${present[@]}") || die "removing ${present[*]} failed (nothing recorded)"
  f="$LS_STATE/pkgs/$owner.removed"; [[ -r $f ]] && cur=$(cat "$f")
  { [[ -n $cur ]] && printf '%s\n' "$cur"; printf '%s\n' "$rec"; } | sed '/^$/d' | sort -u | swrite "$f"
}
# pkg_restore OWNER : put back what pkg_uninstall removed
pkg_restore() {
  local f="$LS_STATE/pkgs/$1.removed" recs=()
  [[ -r $f ]] || return 0
  mapfile -t recs < <(grep -v '^$' "$f")
  if (( ${#recs[@]} )); then _pkg_restore_names "${recs[@]}"; fi
  srun rm -f "$f"
}
# defaults for mutable backends: remove/reinstall by name, record bare names.
# _pkg_rm removes exactly the named packages (unlike _pkg_del, no autoremove/purge): it's what _pkg_del_check simulated.
_pkg_uninstall_names() { _pkg_rm "$@" >&2 || return 1; printf '%s\n' "$@"; }
_pkg_restore_names() { _pkg_add "$@"; }

# --- vendor package repositories (apt, dnf, rpm-ostree): keys pinned by fingerprint, recorded so remove takes exactly them
# _key_fpr FILE : the fingerprint of FILE's one primary key; fails on none or several (a second key would be trusted too)
_key_fpr() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null \
    | awk -F: '/^pub:/ {n++; want=1; next} want && /^fpr:/ {fpr=$10; want=0} END {if (n != 1) exit 1; print fpr}'
}
_ARMOR='-----BEGIN PGP PUBLIC KEY BLOCK-----'
# repo_add NAME --key URL FPR [--key URL FPR]... [--apt LINE] [--dnf BASEURL] [--repo-gpgcheck]
#   apt: the (first) key to /usr/share/keyrings/NAME-archive-keyring.asc|.gpg (armored|binary: apt goes by the
#   extension), LINE to /etc/apt/sources.list.d/NAME.list (KEYRING in LINE stands for the key's path).
#   dnf, rpm-ostree: each key to /etc/pki/rpm-gpg/decal-NAME-FPR.asc, /etc/yum.repos.d/NAME.repo using only those
#   (gpgkey=file://: never fetched again from the internet). A changed key list rewrites a repo decal added.
# Each key must have its pinned fingerprint, or nothing is written. A NAME repository decal didn't add (by hand, or
# the vendor's own package) is used as is. Arch: nothing to do.
repo_add() {
  local name=$1 apt="" dnf="" rgc=0 urls=() fprs=(); shift
  while (( $# )); do
    case $1 in
      --key) urls+=("$2"); fprs+=("$3"); shift 3 ;;
      --apt) apt=$2; shift 2 ;;
      --dnf) dnf=$2; shift 2 ;;
      --repo-gpgcheck) rgc=1; shift ;;
      *) die "repo_add: unknown option $1" ;;
    esac
  done
  local rec="$LS_STATE/repos/$name" src kps=() body="" i
  case $PLATFORM in
    debian) [[ -n $apt ]] || return 0; src=/etc/apt/sources.list.d/$name.list ;;
    fedora|fedora-atomic) [[ -n $dnf ]] || return 0; src=/etc/yum.repos.d/$name.repo ;;
    *) return 0 ;;
  esac
  if [[ ! -e $rec ]] && [[ -e $(sys_path "$src") || -e $(sys_path "/etc/apt/sources.list.d/$name.sources") ]]; then
    info "using the $name package repository already set up on this system"; return 0
  fi
  if [[ $PLATFORM == debian ]]; then
    [[ ! -e $rec ]] || return 0
  else
    for i in "${!fprs[@]}"; do kps+=("/etc/pki/rpm-gpg/decal-$name-${fprs[$i]}.asc"); done
    body=$(printf '[%s]\nname=%s (added by decal)\nbaseurl=%s\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=%s\ngpgkey=%s' \
      "$name" "$name" "$dnf" "$rgc" "$(printf 'file://%s\n' "${kps[@]}" | paste -sd' ')")
    if [[ -e $rec && $(cat "$(sys_path "$src")" 2>/dev/null) == "$body" ]]; then return 0; fi
  fi
  step "adding the $name package repository"
  local dl=() k
  for i in "${!urls[@]}"; do
    k=$(ls_fetch "${urls[$i]}") || die "could not download the $name signing key from ${urls[$i]}: nothing added"
    if [[ $LS_DRY_RUN != 1 ]]; then
      if ! have gpg; then pkg_install "repo-$name" gnupg; fi
      [[ $(_key_fpr "$k") == "${fprs[$i]}" ]] \
        || die "the signing key from ${urls[$i]} isn't the one with $name's fingerprint ${fprs[$i]}: nothing added"
      if [[ $PLATFORM != debian ]] && ! grep -qF -- "$_ARMOR" "$k"; then
        die "the signing key from ${urls[$i]} isn't an armored key: nothing added"
      fi
    fi
    dl+=("$k")
  done
  if [[ -e $rec ]]; then _repo_files_rm "$name"; fi   # a changed key list: the old files go first
  if [[ $PLATFORM == debian ]]; then
    local ext=gpg; if [[ $LS_DRY_RUN == 1 ]] || grep -qF -- "$_ARMOR" "${dl[0]}"; then ext=asc; fi
    kps=("/usr/share/keyrings/$name-archive-keyring.$ext"); body=${apt//KEYRING/${kps[0]}}
  fi
  printf '%s\n' "${kps[@]}" "$src" | swrite "$rec"   # the record first: an interrupted add can still be undone
  for i in "${!kps[@]}"; do
    if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] write $(sys_path "${kps[$i]}") ($name's signing key)"
    else swrite "$(sys_path "${kps[$i]}")" < "${dl[$i]}"; fi
  done
  printf '%s\n' "$body" | swrite "$(sys_path "$src")"
  if [[ $PLATFORM == debian ]]; then rm -f "${LS_RUNTMP:-/nonexistent}/apt-updated"; fi   # the backend refreshes its lists before the next install
}
_repo_files_rm() {   # NAME : the files repo_add recorded for NAME, and the record
  local rec="$LS_STATE/repos/$1" p
  [[ -r $rec ]] || return 0
  while IFS= read -r p; do if [[ -n $p ]]; then srun rm -f "$(sys_path "$p")"; fi; done < "$rec"
  srun rm -f "$rec"
}
# repo_remove NAME : everything repo_add put in place for NAME (the gnupg it installed too)
repo_remove() { _repo_files_rm "$1"; pkg_remove "repo-$1"; }
