#!/usr/bin/env bash
# decal installer, no git needed:
#   curl -fsSL https://dmacpherson.github.io/decal/install | bash                     # install / update, open the menu
#   curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- PROFILE [--tags dev]   # ...then apply PROFILE
#   curl -fsSL https://dmacpherson.github.io/decal/install | bash -s -- stamp [ARGS]           # ...then stamp this machine
# Downloads decal to ~/.local/share/decal/app and links ~/.local/bin/decal. Run it again (or `decal update`) for the
# newest version; decal also updates itself before add/apply/remove. PROFILE is anything `decal apply` takes: a
# folder, a .tar.gz/.zip, owner/repo or a GitHub link, an https link to an archive, a git URL (private GitHub repos:
# GITHUB_TOKEN, `gh auth login`, or decal signs you in).
# DECAL_VERSION: latest (default: the newest release, checksum verified) | vX.Y.Z | a branch, e.g. main (newest commit).
# Remembered, so updates stay on it. Already installed and current: nothing is downloaded (DECAL_REINSTALL=1 does
# anyway). Options for decal itself: install.sh --update | --check (newer version? print it).
set -euo pipefail

say() { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# _get URL [OUT] : download (stdout without OUT); curl or wget
_get() {
  if have curl; then curl -fsSL --connect-timeout 10 --retry 2 ${2:+-o "$2"} "$1"
  elif have wget; then wget -q --timeout=20 -O "${2:--}" "$1"
  else die "curl or wget is needed"; fi
}
_json() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
_sha256() { if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; else python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; fi; }

# _resolve VERSION -> "TAG URL CHECKSUM-URL" (no checksum for a branch: GitHub makes that archive on the fly)
_resolve() {
  local v=$1 api="https://api.github.com/repos/$REPO" dl="https://github.com/$REPO" tag sha
  case $v in
    latest) tag=$(_get "$api/releases/latest" | _json tag_name) || return 1
            echo "$tag $dl/releases/download/$tag/decal.tar.gz $dl/releases/download/$tag/decal.tar.gz.sha256" ;;
    v[0-9]*) echo "$v $dl/releases/download/$v/decal.tar.gz $dl/releases/download/$v/decal.tar.gz.sha256" ;;
    *) sha=$(_get "$api/commits/$v" | _json sha) || return 1
       echo "$v@${sha:0:12} $dl/archive/$sha.tar.gz -" ;;
  esac
}

# _install TAG URL SUMURL CHANNEL HOME BIN : download, check, unpack, swap in, link
_install() {
  local tag=$1 url=$2 sumurl=$3 version=$4 home=$5 bin=$6
  TMP_DL=$(mktemp -d); trap 'rm -rf "$TMP_DL"' EXIT   # global: the trap runs after the script's last line
  local tmp=$TMP_DL
  say "downloading decal $tag"
  _get "$url" "$tmp/decal.tar.gz" || die "download failed: $url"
  if [[ $sumurl != - ]]; then
    _get "$sumurl" "$tmp/sum" || die "checksum download failed: $sumurl"
    [[ $(_sha256 "$tmp/decal.tar.gz") == "$(cut -d' ' -f1 < "$tmp/sum")" ]] || die "checksum mismatch: the download is damaged or not decal's (nothing was changed)"
  fi
  mkdir -p "$tmp/x"; tar -xzf "$tmp/decal.tar.gz" -C "$tmp/x" || die "could not unpack the download"
  local top; top=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -1)
  [[ -n $top && -f $top/decal ]] || die "the download doesn't contain decal"
  echo "$tag" > "$top/VERSION"; echo "$version" > "$top/.channel"; echo "$bin" > "$top/.bin"
  : > "$top/.installed"   # installed by this script: decal updates itself (a git checkout never does)
  # swap in: the old copy stays until the new one is in place; never a folder that isn't an install of this script
  if [[ -e $home && ! -e $home/.installed ]] && [[ -n $(ls -A "$home" 2>/dev/null) ]]; then
    die "$home exists and isn't a decal install: not replacing it (set DECAL_HOME to install elsewhere)"
  fi
  mkdir -p "$(dirname "$home")"; rm -rf "$home.old"
  if [[ -e $home ]]; then mv "$home" "$home.old"; fi
  mv "$top" "$home"; rm -rf "$home.old"
  mkdir -p "$bin"; ln -sfn "$home/decal" "$bin/decal"
}

main() {
  REPO=${DECAL_REPO:-dmacpherson/decal}
  # its own folder inside decal's data folder (~/.local/share/decal holds what modules keep, e.g. icons): replaced whole
  local home=${DECAL_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/decal/app}
  local bin=${DECAL_BIN:-$(cat "$home/.bin" 2>/dev/null || echo "$HOME/.local/bin")}   # where the last install linked it
  local mode=install; case ${1:-} in --update) mode=update; shift ;; --check) mode=check; shift ;; esac
  if (( ${DECAL_FAKE_EUID:-$EUID} == 0 )) && [[ ${DECAL_ALLOW_ROOT:-0} != 1 ]]; then die "run as your normal user, not root (decal uses sudo itself when it needs to)"; fi
  local t; for t in tar python3; do have "$t" || die "$t is needed: install it with your package manager, then run this again"; done
  local version=${DECAL_VERSION:-$(cat "$home/.channel" 2>/dev/null || echo latest)}
  local cur; cur=$(cat "$home/VERSION" 2>/dev/null || true)
  local tag url sumurl
  read -r tag url sumurl < <(_resolve "$version" || true) || true
  [[ -n ${tag:-} ]] || die "could not reach GitHub to find decal $version"
  if [[ $mode == check ]]; then [[ $tag != "$cur" ]] && { echo "$tag"; return 0; }; return 1; fi
  if [[ $tag == "$cur" && -x $home/decal && ${DECAL_REINSTALL:-0} != 1 ]]; then
    # already there: nothing to download (DECAL_REINSTALL=1 fetches it again anyway)
    if [[ $mode == update ]]; then say "decal $tag is up to date"; return 0; fi
    say "decal $tag is already installed and up to date"
    mkdir -p "$bin"; ln -sfn "$home/decal" "$bin/decal"
  else
    _install "$tag" "$url" "$sumurl" "$version" "$home" "$bin"
    if [[ -n $cur && $cur != "$tag" ]]; then say "decal updated: $cur -> $tag"; else say "decal $tag installed in $home"; fi
  fi
  case ":$PATH:" in *":$bin:"*) ;; *) say "add $bin to your PATH to run 'decal' directly (for now: $bin/decal)" ;; esac
  [[ $mode == install ]] || return 0
  # piped into bash, stdin is the script: decal gets the terminal. No profile given: the menu (when there's a
  # terminal and DECAL_NO_MENU isn't set); a profile: applied straight away
  local tty=0; if { : < /dev/tty; } 2>/dev/null && [[ -t 1 ]]; then tty=1; fi
  if (( $# == 0 )); then
    if (( tty )) && [[ -z ${DECAL_NO_MENU:-} ]]; then exec "$home/decal" --no-update ui < /dev/tty; fi
    return 0
  fi
  # `stamp [...]`: install, then stamp this machine; anything else is a profile to apply
  local cmd=(apply --yes); if [[ $1 == stamp ]]; then cmd=(stamp); shift; fi   # --yes: the person typed the source
  if [[ ! -t 0 ]] && (( tty )); then exec "$home/decal" --no-update "${cmd[@]}" "$@" < /dev/tty; fi
  exec "$home/decal" --no-update "${cmd[@]}" "$@"
}

main "$@"   # last line: a cut-off download runs nothing
