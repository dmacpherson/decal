# shellcheck shell=bash disable=SC2034,SC2153,SC2154  # sourced by decal: LS_REPO, MODULES_DIR, PROFILE_DIR and friends come from it
# decal usb: put decal on a USB stick (or in a folder)
# usb_bin : a folder with the launchers (Decal-x86_64, Decal-aarch64): this decal's usb/bin, else this channel's
# release's (install.sh fetches and checks it), kept in the cache
usb_bin() {
  local d=${DECAL_USB_BIN:-$LS_REPO/usb/bin} c="${XDG_CACHE_HOME:-$HOME/.cache}/decal/usb-bin" t top
  if [[ -f $d/Decal-x86_64 ]]; then echo "$d"; return 0; fi
  if [[ -f $c/Decal-x86_64 ]]; then echo "$c"; return 0; fi
  info "getting the stick launchers (this copy of decal doesn't have them)"
  t=$(mktemp -d "$LS_RUNTMP/rel.XXXXXX")
  top=$(DECAL_HOME=$LS_REPO bash "$LS_REPO/install.sh" --fetch-to "$t") || die "couldn't download the stick launchers"
  [[ -f $top/usb/bin/Decal-x86_64 ]] || die "the latest release has no stick launchers yet"
  mkdir -p "$c"; cp "$top/usb/bin/"* "$c/"; echo "$c"
}
# do_usb [--from SRC] [--how saved-key|sign-in|copy|latest] [--decal newest|copy|online] [--arm]
#        [--to MOUNTPOINT|DEVICE|folder[:PATH]] [--yes] : put decal on a USB stick (or in a folder)
do_usb() {
  local prof="" how="" dmode=newest arm=0 to="" yes=0 target files key="" kind src ver bin how_text a res
  while (( $# )); do
    case $1 in
      --from) val "$1" "${2:-}" "a profile (a folder, a link or owner/name)"; prof=$2; shift ;;
      --how) val "$1" "${2:-}" "saved-key, sign-in, copy or latest"; how=$2; shift ;;
      --decal) val "$1" "${2:-}" "newest, copy or online"; dmode=$2; shift ;;
      --to) val "$1" "${2:-}" "a mount point, a device, or folder[:PATH]"; to=$2; shift ;;
      --arm) arm=1 ;; --yes|-y) yes=1 ;;
      *) die "usb: unknown option $1" ;;
    esac; shift
  done
  if [[ ${DECAL_YES:-} == 1 ]]; then yes=1; fi   # --yes is decal's own option (it reaches here as DECAL_YES)
  [[ $dmode =~ ^(newest|copy|online)$ ]] || die "usb: --decal newest, copy or online"
  # where
  case $to in
    folder) target="$HOME/decal-usb" ;;
    folder:*) target=${to#folder:}; target=${target/#\~/$HOME} ;;
    /dev/*) target=$(python3 "$LS_REPO/lib/usb.py" mount "$to") || exit 1 ;;
    "") (( ! yes )) || die "usb: --yes needs --to (which drive to write: a mount point, a device, or folder)"
        mapfile -t a < <(python3 "$LS_REPO/lib/usb.py" drives | awk -F'\t' '$3 != "" {print $3}')
        (( ${#a[@]} == 1 )) || die "usb: which drive? --to a mount point, a device, or folder (decal usb in a terminal asks)"
        target=${a[0]} ;;
    *) [[ -d $to ]] || die "usb: $to isn't a folder or a mounted drive"; target=$to ;;
  esac
  # which profile (the active one by default)
  if [[ -z $prof ]]; then
    prof=$(env -u DECAL_PROFILE DECAL_PROFILE_HOME="$PROFILE_HOME" python3 "$LS_REPO/lib/profiles.py" active 2>/dev/null || true)
    [[ -n $prof ]] || die "usb: which profile? --from SOURCE (there's no active profile)"
  fi
  stage_profile "$prof"; kind=$STAGE_KIND; src=$STAGE_SRC
  if [[ $kind == github ]]; then
    if [[ -z $how ]]; then if python3 "$LS_REPO/lib/source.py" public "$src"; then how=latest; else how=saved-key; fi; fi
  else
    [[ -z $how || $how == copy ]] || die "usb: $src isn't on GitHub: the stick gets a copy (--how copy)"
    how=copy
  fi
  [[ $how =~ ^(saved-key|sign-in|copy|latest)$ ]] || die "usb: --how saved-key, sign-in, copy or latest"
  # the key: always a fresh read key, never GITHUB_TOKEN / GH_TOKEN / gh
  if [[ $how == saved-key ]]; then
    if [[ -n ${DECAL_STICK_KEY:-} ]]; then key=$DECAL_STICK_KEY
    else
      have_tty || die "usb: a saved key needs a terminal to sign in (or DECAL_STICK_KEY)"
      info "the stick gets its own read-only key (your gh login or GITHUB_TOKEN are never put on a stick)"
      key=$(env -u GITHUB_TOKEN -u GH_TOKEN python3 "$LS_REPO/lib/auth.py" get "${src#github:}" --need read) || die "no key: nothing written"
    fi
  fi
  if [[ -n $key ]] && ! GITHUB_TOKEN=$key python3 "$LS_REPO/lib/auth.py" stick-ok 2>/dev/null; then
    die "that key can write to your repos: it's not put on a stick (use Sign in with GitHub, or a read-only token)"
  fi
  bin=$(usb_bin) || exit 1
  ver=$(cat "$LS_REPO/VERSION" 2>/dev/null || echo "dev-$(git -C "$LS_REPO" rev-parse --short HEAD 2>/dev/null || echo local)")
  files="$LS_RUNTMP/stick"; rm -rf "$files"; mkdir -p "$files/.Decal"
  cp "$bin/Decal-x86_64" "$files/Decal"
  if (( arm )); then cp "$bin/Decal-aarch64" "$files/.Decal/Decal-ARM"; fi
  cp "$LS_REPO/usb/start.sh" "$files/.Decal/start.sh"
  case $how in
    copy) copy_profile "$STAGE_DIR" "$files/.Decal/profile"; : > "$files/.Decal/profile/.decal-stamp"
          how_text="a copy of $src" ;;
    saved-key) ( umask 077; printf '%s\n' "$key" > "$files/.Decal/key" ); how_text="$src (with a read-only key)" ;;
    sign-in) how_text="$src (signs in each time)" ;;
    latest) how_text="$src (public: always the latest)" ;;
  esac
  if [[ $dmode != online ]]; then   # this decal's own files (installed or a checkout), without .git, tests or docs
    tar -czf "$files/.Decal/decal.tar.gz" -C "$(dirname "$LS_REPO")" --exclude=.git --exclude=tests --exclude=docs \
      --exclude=__pycache__ --exclude=.superpowers --transform "s,^$(basename "$LS_REPO"),decal," "$(basename "$LS_REPO")"
    (cd "$files/.Decal" && sha256sum decal.tar.gz > decal.tar.gz.sha256)
  fi
  { echo "# Made by decal $ver on $(date +%F). Run decal usb to change it."
    if [[ $how == copy ]]; then echo "profile=copy"; else echo "profile=$src"; fi
    case $how in saved-key) echo "key=saved" ;; sign-in) echo "key=ask" ;; *) echo "key=none" ;; esac
    echo "decal=$dmode"; echo "version=$ver"; } > "$files/.Decal/stick.conf"
  sed -e "s|{profile}|$how_text|" -e "s|{version}|$ver ($dmode)|" -e "s|{made}|$(date +%F)|" "$LS_REPO/usb/README.txt" > "$files/.Decal/README.txt"
  local fs; fs=$(findmnt -no FSTYPE --target "$target" 2>/dev/null || true)
  if [[ $fs == vfat || $fs == msdos ]]; then
    printf '\nThis stick is FAT32: Linux mounts it so nothing on it can be started by double-clicking. Start decal\nfrom a terminal instead:  bash .Decal/start.sh   (or reformat the stick as exFAT; Ventoy sticks are exFAT).\n' >> "$files/.Decal/README.txt"
  fi
  info "on $target:"; (cd "$files" && find Decal .Decal -type f | sort | sed 's/^/    /') >&2
  if (( ! yes )); then
    have_tty || die "usb: nothing written: add --yes to write without asking"
    tty_ask "Write these to $target? [Y/n] "; [[ ${REPLY:-y} == [Yy]* ]] || die "nothing written"
  fi
  res=$(python3 "$LS_REPO/lib/usb.py" write "$target" "$files") || exit 1   # usb.py says why
  info "done: double-click Decal on any Linux PC (Ctrl+H shows the .Decal folder)"
  if (( arm )); then info "ARM machines: double-click .Decal/Decal-ARM"; fi
  if [[ $fs == vfat || $fs == msdos ]]; then warn "this stick is FAT32: double-clicking Decal won't work on it; start it with: bash .Decal/start.sh (or use an exFAT stick)"; fi
  if [[ $res == upgraded ]]; then warn "the old hand-made setup was replaced: revoke its token on GitHub (Settings → Developer settings → tokens)"; fi
  if [[ $target == "$HOME"/* || $to == folder* ]]; then info "copy Decal and .Decal/ together; zipping or some cloud drives drop the 'can run' bit Decal needs"; fi
}
