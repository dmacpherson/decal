# shellcheck shell=bash disable=SC2034,SC2153,SC2154  # sourced by decal: LS_REPO, MODULES_DIR, PROFILE_DIR and friends come from it
# decal new: a new profile, on GitHub, in a file or on a USB stick
# do_new NAME [--from this-machine|PROFILE|empty] [--to github|file[:PATH]|stick[:NAME]] [--public] [--use] : a new profile.
# Never overwrites: an existing repo, file or stick profile stops it before any work.
do_new() {
  local name="" from=this-machine to=github public=0 use=0 dest="" repo="" tok="" src stage sticks n a
  while (( $# )); do
    case $1 in
      --from) val "$1" "${2:-}" "this-machine, a profile, or empty"; from=$2; shift ;;
      --to) val "$1" "${2:-}" "github, file, file:PATH, stick or stick:NAME"; to=$2; shift ;;
      --public) public=1 ;;
      --use) use=1 ;;
      -*) die "new: unknown option $1" ;;
      *) [[ -z $name ]] || die "new: one name (got $name and $1)"; name=$1 ;;
    esac; shift
  done
  [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] || die "new: a name like decal-work (letters, digits, - _ .)"
  case $to in   # where, checked first
    github) ;;
    file) dest="$HOME/$name.tar.gz" ;;
    file:*) dest=${to#file:}; dest=${dest/#\~/$HOME} ;;
    stick|stick:*)
      mapfile -t sticks < <(python3 "$LS_REPO/lib/profiles.py" sticks | sed '/^$/d')
      (( ${#sticks[@]} )) || die "no USB stick found: plug in a USB stick and try again"
      if [[ $to == stick:* ]]; then   # named: no question
        for a in "${sticks[@]}"; do if [[ $(basename "$a") == "${to#stick:}" || $a == "${to#stick:}" ]]; then dest="$a/.Decal/profile"; fi; done
        [[ -n $dest ]] || die "no USB stick named ${to#stick:} (plugged in: $(for a in "${sticks[@]}"; do printf '%s ' "$(basename "$a")"; done))"
      elif (( ${#sticks[@]} == 1 )); then dest="${sticks[0]}/.Decal/profile"
      else
        have_tty || die "several USB sticks: say which with --to stick:NAME"
        n=0; for a in "${sticks[@]}"; do n=$((n + 1)); printf '  %s) %s\n' "$n" "$(basename "$a")" >> "${DECAL_TTY_OUT:-/dev/tty}"; done
        tty_ask 'Which stick? ' || REPLY=""; a=$REPLY
        if ! [[ $a =~ ^[0-9]+$ ]] || (( a < 1 || a > ${#sticks[@]} )); then die "no stick chosen"; fi
        dest="${sticks[$((a - 1))]}/.Decal/profile"
      fi ;;
    *) die "new: --to github, file, file:PATH, stick or stick:NAME" ;;
  esac
  if [[ -n $dest && -e $dest ]]; then die "$dest already exists: use decal stamp to update it"; fi
  if [[ $to == github ]]; then
    gh_write_key "$name"; tok=$GH_KEY; repo=$GH_REPO
    if GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" exists "$repo"; then die "github:$repo already exists: use decal stamp -gh $repo to update it"; fi
  fi
  stage="$LS_RUNTMP/new/$name"
  case $from in   # what goes in
    this-machine) do_stamp "$stage" ;;
    empty) python3 "$LS_REPO/lib/profiles.py" empty "$stage" ;;
    *) stage_profile "$from"; copy_profile "$STAGE_DIR" "$stage" ;;
  esac
  rm -f "$stage/.decal-stamp"
  python3 "$LS_REPO/lib/profiles.py" readme "$stage" "$name" "$( [[ $from == this-machine || $from == empty ]] && echo "$from" || echo "${STAGE_SRC:-$from}")"
  case $to in   # where it goes
    github)
      local pub=(); if (( public )); then pub=(--public); fi
      GITHUB_TOKEN=$tok python3 "$LS_REPO/lib/github.py" push "$stage" "$repo" "${pub[@]}" --message "decal new: $name" >/dev/null \
        || die "could not create github:$repo"
      src="github:$repo" ;;
    stick|stick:*) save_profile "$stage" "$dest"; src=$dest ;;   # the stick's folder
    *) mkdir -p "$(dirname "$dest")"; tar -czf "$dest" -C "$stage" .; src=$dest ;;   # a file, whatever its name
  esac
  info "new profile: $src"
  if (( use )); then set_profile "$src"; python3 "$LS_REPO/lib/source.py" remember "$STAGE_SRC" || true; fi
}
