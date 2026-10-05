# shellcheck shell=bash disable=SC2034,SC2153,SC2154  # sourced by decal: LS_REPO, MODULES_DIR, PROFILE_DIR and friends come from it
# decal stamp: this machine's setup, changed from the defaults only, as a profile
INSTALL_URL="https://dmacpherson.github.io/decal/install"
# module_has NAME FUNC : the module defines FUNC
module_has() { ( cd "$MODULES_DIR/$1" && export MODULE_DIR="$PWD"; set +u; source ./module.sh >/dev/null 2>&1; declare -F "$2" >/dev/null ); }
# do_stamp [PATH] [-gh [REPO]] [--public] : this machine's setup, changed from default only, as a profile.
# Each module's module_stamp reads the machine (prints its TOML, files go to $STAMP_DIR, notes via stamp_note).
# A module decal set up from your profile that is still in place is taken from the profile as you wrote it
# (tags, sources, comments aside) unless it sets STAMP_LIVE=1 (those compare the machine with the defaults).
do_stamp() {
  local dest="" gh=0 repo="" public=0 signed=0 me m frag st rc from only=()
  while (( $# )); do
    case $1 in
      -gh|--github) gh=1
        if [[ ${2:-} =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$ && ${2:-} != *.tar.gz && ${2:-} != *.tgz ]]; then repo=$2; shift; fi ;;
      --github=*) gh=1; repo=${1#--github=} ;;
      --public) public=1 ;;
      -*) die "stamp: unknown option $1" ;;
      *) if [[ $1 != */* && $1 != *.* && -f $MODULES_DIR/$1/module.sh ]]; then only+=("$1")   # a module name
         else [[ -z $dest ]] || die "stamp: one place to save it (got $dest and $1)"; dest=$1; fi ;;
    esac; shift
  done
  me=${USER:-$(id -un)}
  [[ -n $dest ]] || dest="$HOME/decal-$me.tar.gz"
  [[ -n $repo ]] || repo="decal-$me"
  export STAMP_DIR="$LS_RUNTMP/stamp/profile" STAMP_NOTES="$LS_RUNTMP/stamp/notes"
  local body="$LS_RUNTMP/stamp/body.toml"; mkdir -p "$STAMP_DIR"; : > "$STAMP_NOTES"; : > "$body"
  info "stamping this machine: only what's changed from the defaults"
  for m in $(all_modules); do
    [[ $(module_field "$m" STAMP_SKIP) != 1 ]] || continue
    if (( ${#only[@]} )) && ! printf '%s\n' "${only[@]}" | grep -qxF "$m"; then continue; fi   # decal stamp MODULE...
    frag=""; from=0
    if [[ -f $PROFILE_DIR/profile.toml && -r $APPLIED/$m && $(module_field "$m" STAMP_LIVE) != 1 ]] && DECAL_TAGS=all in_profile "$m"; then
      st=$(DECAL_TAGS=all run_module status "$m" 2>/dev/null || true); [[ $st != installed* ]] || from=1
    fi
    if (( from )); then
      frag=$(python3 "$LS_REPO/lib/stamp.py" section "$m" --profile "$PROFILE_DIR" --modules "$MODULES_DIR" --to "$STAMP_DIR") \
        || die "stamp: could not copy [$m] from your profile"
      if [[ -n $frag ]]; then echo "$m: your profile's settings (decal set it up; tags kept)" >> "$STAMP_NOTES"; fi
    elif module_has "$m" module_stamp; then
      set +e; frag=$(run_module stamp "$m" 2>"$LS_RUNTMP/err"); rc=$?; set -e
      if (( rc != 0 )); then warn "stamp $m: $(tail -1 "$LS_RUNTMP/err")"; frag=""; fi
    fi
    if [[ -n $frag ]]; then printf '%s\n\n' "$frag" >> "$body"; fi
  done
  [[ -s $body ]] || die "nothing to stamp: this machine is at its defaults"
  { printf '# decal profile, stamped by %s on %s: only what differed from the defaults.\n' "$me" "$(date +%F)"
    printf '# Apply it anywhere: decal apply <this folder, its .tar.gz, or github:owner/repo>. Edit freely.\n\n'
    cat "$body"; } > "$STAMP_DIR/profile.toml"
  DECAL_TAGS="" python3 "$LS_REPO/lib/profile.py" check --profile "$STAMP_DIR" --modules "$MODULES_DIR" \
    || die "the stamp isn't a valid profile (a decal bug: please report it); nothing was saved"
  info "in this stamp:"; sed 's/^/    /' "$STAMP_NOTES" >&2
  if [[ ${LS_DRY_RUN:-0} == 1 ]]; then printf '\n'; cat "$STAMP_DIR/profile.toml"; info "dry run: nothing saved"; return 0; fi
  local tok=""
  if (( gh )); then   # the key first: the README names the repo, and a wrong key shouldn't come after the work
    gh_write_key "$repo"; tok=$GH_KEY; repo=$GH_REPO; signed=$GH_SIGNED
  fi
  local src; if (( gh )); then src="github:$repo"; else src=$(basename "$dest"); fi
  # shellcheck disable=SC2016  # Markdown backticks, not command substitution
  { printf '# My Linux setup\n\nA [decal](https://github.com/dmacpherson/decal) profile: `decal stamp` saved what was changed from the defaults on %s.\n\n' "$(date +%F)"
    # shellcheck disable=SC2016
    printf '## Put it on a machine\n\n```bash\ncurl -fsSL %s | bash -s -- %s\n```\n\n' "$INSTALL_URL" "$src"
    printf '## In it\n\n'; sed 's/^/- /' "$STAMP_NOTES"; } > "$STAMP_DIR/README.md"
  save_profile "$STAMP_DIR" "$dest"
  info "saved: $dest   (apply it anywhere: decal apply $dest)"
  (( gh )) || return 0
  local r
  if (( public )); then warn "a public repo: anyone can see what's in it (pictures, app list, settings)"; fi
  local pub=(); if (( public )); then pub=(--public); fi
  r=$(GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" push "$STAMP_DIR" "$repo" "${pub[@]}" --message "decal stamp $(date '+%F %H:%M')") \
    || { if (( signed )); then local u; u=$(python3 "$LS_REPO/lib/auth.py" install-url --need write 2>/dev/null) && info "Decal Profile Write needs access to $repo: $u"; fi
         die "could not save the stamp to GitHub (it is saved at $dest)"; }
  info "on GitHub: https://github.com/$r"
  info "on another machine: curl -fsSL $INSTALL_URL | bash -s -- github:$r"
}
