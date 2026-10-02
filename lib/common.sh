# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
# Shared helpers for the runner and modules. Sourced, never executed.
LS_STATE="${DECAL_STATE:-/var/lib/decal}"
LS_USER_STATE="${DECAL_USER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/decal}"
LS_ROOT="${DECAL_ROOT:-}"
LS_DRY_RUN="${LS_DRY_RUN:-0}"
LS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n ${DECAL_SUDO+x} ]]; then LS_SUDO="$DECAL_SUDO"
elif (( EUID == 0 )); then LS_SUDO=""
else LS_SUDO="sudo"; fi

log()  { printf '    %s\n' "$*" >&2; }
info() { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
# step TEXT : what a module is doing now (the spinner shows it; otherwise an ordinary detail line)
step() { if [[ ${DECAL_FANCY:-} == 1 ]]; then printf '::step:: %s\n' "$*" >&2; else log "$*"; fi; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# run CMD...  : execute, or print under --dry-run
run()  { if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] %s\n' "$*" >&2; else "$@"; fi; }
# srun CMD... : like run, with sudo when not root
srun() {
  if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] %s%s\n' "${LS_SUDO:+$LS_SUDO }" "$*" >&2
  else ${LS_SUDO:+"$LS_SUDO"} "$@"; fi
}
# swrite PATH : write stdin to a (root-owned) PATH, creating parent dirs
swrite() {
  local p=$1
  if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] write %s\n' "$p" >&2; cat >/dev/null; return 0; fi
  ${LS_SUDO:+"$LS_SUDO"} mkdir -p "$(dirname "$p")"
  ${LS_SUDO:+"$LS_SUDO"} tee "$p" >/dev/null
}
need_reboot() { [[ -n ${LS_RUNTMP:-} && -d $LS_RUNTMP ]] && : > "$LS_RUNTMP/reboot"; return 0; }
sys_path() { printf '%s%s' "$LS_ROOT" "$1"; }

# --- /etc (or any system file) backups -------------------------------------
_bk_path() { printf '%s/backups/%s%s' "$LS_STATE" "$1" "$2"; }
# etc_seed_backup OWNER PATH <stdin : record stdin as the original, if none recorded yet
etc_seed_backup() {
  local bk; bk=$(_bk_path "$1" "$2")
  if [[ -e $bk || -e $bk.absent ]]; then cat >/dev/null; return 0; fi
  swrite "$bk"
}
# etc_write OWNER PATH <stdin : back up the original once, then write stdin
etc_write() {
  local owner=$1 path=$2 bk real; bk=$(_bk_path "$owner" "$path"); real=$(sys_path "$path")
  if [[ ! -e $bk && ! -e $bk.absent ]]; then
    srun mkdir -p "$(dirname "$bk")"
    if [[ -e $real ]]; then srun cp -a "$real" "$bk"; else srun touch "$bk.absent"; fi
  fi
  swrite "$real"
}
# etc_restore OWNER PATH : put the original back (or delete if it was absent)
etc_restore() {
  local owner=$1 path=$2 bk real; bk=$(_bk_path "$owner" "$path"); real=$(sys_path "$path")
  if [[ -e $bk ]]; then srun cp -a "$bk" "$real"; srun rm -f "$bk"
  elif [[ -e $bk.absent ]]; then srun rm -f "$real" "$bk.absent"; fi
  return 0
}

# terminal_cmd : command that opens the terminal chosen in the profile's [terminal] app
terminal_cmd() {
  ( penv=$(python3 "$LS_LIB/profile.py" shell terminal --profile "${PROFILE_DIR:-.}" --modules "$LS_LIB/../modules") || exit 1
    eval "$penv"
    cd "$LS_LIB/../modules/terminal" && export MODULE_DIR="$PWD" && source "./terminals/$P_app.sh" && printf '%s' "$TERM_CMD" )
}

# ls_fetch SOURCE [fetch.py options] : local path for a source (downloaded/cached as needed)
ls_fetch() {
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] fetch $*"
    local d; d=$(mktemp -d "${LS_RUNTMP:-${TMPDIR:-/tmp}}/dry-fetch.XXXXXX"); echo "$d"; return 0   # removed with the run
  fi
  python3 "$LS_REPO/lib/fetch.py" "$@" --profile "${PROFILE_DIR:-.}"
}
# state_append FILE LINE : add LINE to a (root-owned) state file once
state_append() {
  local f=$1 cur=""; [[ -r $f ]] && cur=$(cat "$f")
  { [[ -n $cur ]] && printf '%s\n' "$cur"; printf '%s\n' "$2"; } | sort -u | swrite "$f"
}

# stamp helpers (module_stamp): a line for the summary; copy a file/folder into the stamp (prints REL);
# a TOML list of strings
stamp_note() { printf '%s\n' "$*" >> "$STAMP_NOTES"; }
stamp_copy() { mkdir -p "$STAMP_DIR/$(dirname "$2")"; cp -aL "$1" "$STAMP_DIR/$2"; printf '%s' "$2"; }
toml_list() { local x items=() IFS=,; for x; do x=${x//\\/\\\\}; items+=("\"${x//\"/\\\"}\""); done; printf '[%s]' "${items[*]}" | sed 's/","/", "/g'; }

# state_drop FILE LINE : take LINE out of a (root-owned) state file
state_drop() { [[ -r $1 ]] || return 0; local cur; cur=$(grep -vxF "$2" "$1" || true); { [[ -z $cur ]] || printf '%s\n' "$cur"; } | swrite "$1"; }

# shellcheck source=lib/gdm.sh
source "$LS_LIB/gdm.sh"
