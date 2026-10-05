# shellcheck shell=bash disable=SC2034,SC2153,SC2154  # sourced by decal: LS_REPO, MODULES_DIR, PROFILE_DIR and friends come from it
# profiles from any source: GitHub keys, downloading and checking (stage_profile), making one active, and whose it is
find_profile_root() {  # DIR -> folder holding profile.toml (DIR or its single sub-folder)
  if [[ -f $1/profile.toml ]]; then echo "$1"; return 0; fi
  local subs=("$1"/*/)
  if [[ ${#subs[@]} -eq 1 && -f ${subs[0]}profile.toml ]]; then echo "${subs[0]%/}"; return 0; fi
  return 1
}
# gh_tarball OWNER/REPO REF OUT : a GitHub repo as a .tar.gz without git. Private repos need a key: GITHUB_TOKEN,
# GH_TOKEN or a `gh auth login`; without one, in a terminal, it asks (sign in with GitHub, or a token you make)
gh_token() {   # from a USB stick (a borrowed PC): only the stick's own key (start.sh sets GITHUB_TOKEN), never GH_TOKEN or gh
  if [[ -n ${DECAL_STICK:-} ]]; then printf '%s' "${GITHUB_TOKEN:-}"; return 0; fi
  local t=${GITHUB_TOKEN:-${GH_TOKEN:-}}; if [[ -z $t ]] && have gh; then t=$(gh auth token 2>/dev/null || true); fi; printf '%s' "$t"
}
# gh_write_token : a key to write to GitHub with: from a USB stick (a borrowed PC) never the PC's GITHUB_TOKEN, GH_TOKEN
# or gh login, only this menu session's key (DECAL_WRITE_KEY) or a fresh sign-in; elsewhere, the usual order
gh_write_token() { if [[ -n ${DECAL_STICK:-} ]]; then printf '%s' "${DECAL_WRITE_KEY:-}"; else gh_token; fi; }
# gh_auth REPO read|write [--may-create] : ask on the terminal for a key (lib/auth.py: sign in with a code or QR,
# or paste a token); exported as GITHUB_TOKEN for the rest of this run, never saved. No terminal or cancelled: fails
gh_auth() {
  have_tty || return 1
  local t; t=$(python3 "$LS_REPO/lib/auth.py" get "$1" --need "$2" "${@:3}") || return 1
  [[ -n $t ]] || return 1
  export GITHUB_TOKEN=$t
}
# gh_write_key REPO : a key that can save to REPO (NAME on your account, or OWNER/NAME) in GH_KEY, the full OWNER/NAME
# in GH_REPO; GH_SIGNED=1 when it came from signing in just now. A key that's already there is checked first.
gh_write_key() {
  local why="" rc=0 who
  GH_KEY=$(gh_write_token); GH_SIGNED=0
  if [[ -n $GH_KEY ]]; then   # can it save to the repo? (offline: let the push say)
    why=$(GITHUB_TOKEN=$GH_KEY python3 "$LS_REPO/lib/auth.py" check "$1" --need write --may-create 2>&1) || rc=$?
    if (( rc >= 10 && rc <= 12 )); then warn "$why"; GH_KEY=""; else why=""; fi
  fi
  if [[ -z $GH_KEY ]]; then
    if ! gh_auth "$1" write --may-create; then
      [[ -z $why ]] || die "GitHub didn't accept the token, and there's no terminal to sign in on (the token needs permission to create repos and write their contents)"
      die "no GitHub key: sign in when asked, set GITHUB_TOKEN, or log in with gh auth login"
    fi
    GH_KEY=$GITHUB_TOKEN; GH_SIGNED=1
  fi
  GH_REPO=$1
  if [[ $1 != */* ]]; then
    who=$(GITHUB_TOKEN=$GH_KEY python3 "$LS_REPO/lib/github.py" whoami) || die "GitHub didn't accept the token (the token needs permission to create repos and write their contents)"
    GH_REPO="$who/$1"
  fi
}
gh_tarball() {
  local tok rc asked=0
  tok=$(gh_token)
  while :; do
    # the key reaches source.py in its environment: never on a command line, never in a file
    rc=0; GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/source.py" github "$1" "$3" --ref "${2:-}" || rc=$?
    (( rc == 0 )) && return 0
    if (( rc == 4 && asked == 0 )); then
      asked=1
      if gh_auth "$1" read; then tok=$GITHUB_TOKEN; continue; fi
    fi
    case $rc in
      4) die "github:$1 not found or not allowed (private? set GITHUB_TOKEN, or log in with gh auth login)" ;;
      3) die "couldn't reach GitHub to get github:$1: check the internet connection" ;;
      *) die "could not download github:$1 (see above)" ;;
    esac
  done
}
# stage_profile SOURCE : SOURCE as a validated folder holding profile.toml, in STAGE_DIR (a folder source as is;
# anything else downloaded/unpacked into a temp folder); STAGE_KIND and STAGE_SRC (canonical) set too. Not run in
# a subshell: a sign-in it needs lasts the whole run.
stage_profile() {
  local r note tmp rc
  r=$(python3 "$LS_REPO/lib/source.py" resolve "$1") || exit 1   # the reason is already on stderr
  IFS=$'\t' read -r STAGE_KIND STAGE_SRC note <<<"$r"
  if [[ -n $note ]]; then info "$note"; fi
  case $STAGE_KIND in
    dir)
      [[ -f $STAGE_SRC/profile.toml ]] || die "$STAGE_SRC has no profile.toml"
      STAGE_DIR=$(cd "$STAGE_SRC" && pwd -P); STAGE_SRC=$STAGE_DIR ;;
    archive)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      python3 "$LS_REPO/lib/source.py" unpack "$STAGE_SRC" "$tmp/x" || die "could not unpack $STAGE_SRC"
      STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC contains no profile.toml" ;;
    github)
      [[ $STAGE_SRC =~ ^github:([^@]+)(@(.+))?$ ]] || die "not a GitHub source: $STAGE_SRC"
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      gh_tarball "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$tmp/p.tar.gz"
      python3 "$LS_REPO/lib/source.py" unpack "$tmp/p.tar.gz" "$tmp/x" || die "could not unpack $STAGE_SRC"
      STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC has no profile.toml" ;;
    url)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX"); rc=0
      python3 "$LS_REPO/lib/source.py" fetch "$STAGE_SRC" "$tmp/x" >/dev/null || rc=$?
      if (( rc == 0 )); then
        STAGE_DIR=$(find_profile_root "$tmp/x") || die "$STAGE_SRC: the archive has no profile.toml"
      elif (( rc == 3 )) && have git && git clone -q "$STAGE_SRC" "$tmp/p" 2>/dev/null && [[ -f $tmp/p/profile.toml ]]; then
        STAGE_KIND=git; STAGE_DIR=$tmp/p
      else
        (( rc != 3 )) || die "$STAGE_SRC isn't a decal profile (not an archive with a profile.toml, nor a git repo with one)"
        exit 1   # source.py said why
      fi ;;
    git)
      tmp=$(mktemp -d "$LS_RUNTMP/profile.XXXXXX")
      git clone -q "${STAGE_SRC#git+}" "$tmp/p" || die "git clone failed: ${STAGE_SRC#git+}"
      links_inside "$tmp/p" "$STAGE_SRC"
      [[ -f $tmp/p/profile.toml ]] || die "${STAGE_SRC#git+} has no profile.toml"
      STAGE_DIR=$tmp/p ;;
  esac
  python3 "$LS_REPO/lib/profile.py" check --profile "$STAGE_DIR" --modules "$MODULES_DIR" \
    || die "$STAGE_SRC: the profile is invalid (the active profile was not changed)"
}
# links_inside DIR SOURCE : a checkout's links all stay inside it (a theme or path could otherwise lead anywhere)
links_inside() {
  local l
  while IFS= read -r -d '' l; do
    [[ $(realpath -m -- "$l") == "$(realpath -m -- "$1")" ]] || inside "$1" "$l" || die "$2: a link that leads outside it: ${l#"$1"/} (not used)"
  done < <(find "$1" -path "$1/.git" -prune -o -type l -print0)
}
# set_profile SOURCE : make SOURCE the active profile at $PROFILE_HOME (dry-run: only staged)
set_profile() { stage_profile "$1"; activate_staged; }
# activate_staged : the profile stage_profile got (STAGE_*) becomes the active one. A replaced real folder is kept as
# a dated backup, except a newer download of the same GitHub repo or link.
activate_staged() {
  local t=$PROFILE_HOME
  _aside() {  # move the active profile out of the way (a symlink is just dropped)
    local b
    if [[ -L $t ]]; then rm -f "$t"
    elif [[ -e $t ]]; then b="$t.old-$(date +%Y%m%d-%H%M%S)"; [[ ! -e $b ]] || b+="-$$"; mv "$t" "$b"; info "previous profile kept at $b"; fi
    mkdir -p "$(dirname "$t")"
  }
  _beside() {  # the new profile beside the active one first (same filesystem: the swap is then renames, never a copy)
    mkdir -p "$(dirname "$t")"; rm -rf "$t.decal-new" "$t.decal-old"
    cp -a "$STAGE_DIR" "$t.decal-new" || { rm -rf "$t.decal-new"; die "couldn't put the profile in place (the active one is untouched)"; }
  }
  if [[ ${LS_DRY_RUN:-0} == 1 ]]; then PROFILE_DIR=$STAGE_DIR; return 0; fi
  case $STAGE_KIND in
    dir)
      if [[ -e $t && $(readlink -f "$t") == "$STAGE_DIR" ]]; then PROFILE_DIR=$t; info "$STAGE_DIR is already the active profile"; return 0; fi
      _aside; ln -s "$STAGE_DIR" "$t" ;;
    git)
      if [[ -d $t/.git && ! -L $t && $(git -C "$t" remote get-url origin 2>/dev/null) == "${STAGE_SRC#git+}" ]]; then
        git -C "$t" pull -q --ff-only || die "git pull failed in $t"
        links_inside "$t" "$STAGE_SRC"
      else _beside; _aside; mv "$t.decal-new" "$t"; fi ;;
    *)   # archive, github, url: an unpacked copy
      echo "$STAGE_SRC" > "$STAGE_DIR/.decal-source"
      _beside
      if [[ $STAGE_KIND != archive && -d $t && ! -L $t && $(cat "$t/.decal-source" 2>/dev/null) == "$STAGE_SRC" ]]; then
        mv "$t" "$t.decal-old"   # a newer download of the same source: no backup, gone once the new one is in
      else _aside; fi
      mv "$t.decal-new" "$t"; rm -rf "$t.decal-old" ;;
  esac
  PROFILE_DIR=$t
  info "active profile: $t -> $(readlink -f "$t")"
}
# trust SOURCE : a profile that isn't yours (lib/source.py yours): say whose it is, offer a preview, ask.
# --yes / DECAL_YES=1 skips the question; no terminal: stops with how to go on.
# asked SOURCE : you said yes to SOURCE (or --yes): not asked about again (it still isn't "yours" until applied)
asked() {   # git+URL is remembered as URL too (what the checkout's origin says)
  mkdir -p "$LS_USER_STATE"; rec_add "$LS_USER_STATE/asked" "$1"
  if [[ $1 == git+* ]]; then rec_add "$LS_USER_STATE/asked" "${1#git+}"; fi
}
trust() {   # trust SOURCE [VERB [AGAIN]] : VERB is what "y" does (apply/use/add it); AGAIN: the command to suggest
  local src=$1 verb=${2:-apply} login="" tok a fd done=applied again=${3:-}
  case $verb in use) done=used ;; add) done=added ;; esac
  again=${again:-decal --yes $verb $src}
  if [[ ${DECAL_YES:-} == 1 ]]; then asked "$src"; return 0; fi   # asked not to ask (the installer: you typed the source)
  if grep -qxF -- "$src" "$LS_USER_STATE/asked" 2>/dev/null; then return 0; fi   # you said yes to it before
  if [[ $src == github:* ]]; then tok=$(gh_token); if [[ -n $tok ]]; then login=$(GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" whoami 2>/dev/null || true); fi; fi
  if python3 "$LS_REPO/lib/source.py" yours "$src" --login "$login"; then return 0; fi
  warn "this profile is from ${src#github:}, not you: it can install software and change system settings"
  if ! have_tty; then die "not $done: to $verb it anyway, run $again"; fi
  exec {fd}<"${DECAL_TTY_IN:-/dev/tty}"
  while :; do
    printf 'p preview what it would change · y %s it · n stop [p]: ' "$verb" >> "${DECAL_TTY_OUT:-/dev/tty}"
    IFS= read -r a <&"$fd" || a=n
    case ${a:-p} in
      p|P) DECAL_NO_UPDATE=1 DECAL_YES=1 DECAL_PROFILE=$STAGE_DIR "$LS_REPO/decal" --dry-run add all || true ;;
      y|Y) exec {fd}<&-; asked "$src"; return 0 ;;
      *) die "not $done" ;;
    esac
  done
}
# copy_profile SRC DEST : a profile's files into DEST (made if needed), without its git history or where it came from
copy_profile() { mkdir -p "$2"; cp -a "$1/." "$2/"; rm -rf "$2/.git" "$2/.decal-source"; }
# save_profile DIR DEST : DIR saved at DEST, a .tar.gz (an earlier one kept as DEST.old) or a folder (new, or one decal
# made: marked .decal-stamp). Write new, then swap: an earlier one stays whole until the new one is complete
save_profile() {
  local dir=$1 dest=$2
  if [[ $dest == *.tar.gz || $dest == *.tgz ]]; then
    mkdir -p "$(dirname "$dest")"
    if [[ -e $dest ]]; then mv -f "$dest" "$dest.old"; fi
    tar -czf "$dest" -C "$dir" .
    return 0
  fi
  if [[ -e $dest && ! -e $dest/.decal-stamp && -n $(ls -A "$dest" 2>/dev/null) ]]; then die "$dest isn't empty and isn't one decal made: not writing into it"; fi
  rm -rf "$dest.decal-new" "$dest.decal-old"; mkdir -p "$dest.decal-new"
  cp -a "$dir/." "$dest.decal-new/" || { rm -rf "$dest.decal-new"; die "could not save the profile to $dest (the earlier one is untouched)"; }
  : > "$dest.decal-new/.decal-stamp"
  if [[ -e $dest ]]; then mv "$dest" "$dest.decal-old"; fi
  mv "$dest.decal-new" "$dest"; rm -rf "$dest.decal-old"
}
