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

# safe_name NAME : a plain name (a theme, a UUID, an adapter): no /, not . or .., not starting with -, no control
# characters. The profile check already enforces this; modules check again where a name becomes a path or argument.
safe_name() { [[ -n $1 && $1 != */* && $1 != . && $1 != .. && $1 != -* && $1 != *[[:cntrl:]]* ]]; }
# inside DIR PATH : PATH (links followed, .. resolved) is somewhere under DIR
inside() { local d p; d=$(realpath -m -- "$1") && p=$(realpath -m -- "$2") && [[ $p == "$d"/* ]]; }
# run CMD...  : execute, or print under --dry-run
run()  { if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] %s\n' "$*" >&2; else "$@"; fi; }
# srun CMD... : like run, with sudo when not root
srun() {
  if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] %s%s\n' "${LS_SUDO:+$LS_SUDO }" "$*" >&2
  else ${LS_SUDO:+"$LS_SUDO"} "$@"; fi
}
# swrite PATH : write stdin to a (root-owned) PATH, creating parent dirs. Written beside it, then renamed over it
# (keeping its permissions): a crash or Ctrl+C never leaves half a file (CLAUDE.md: write new, then swap)
swrite() {
  local p=$1
  if [[ $LS_DRY_RUN == 1 ]]; then printf '[dry-run] write %s\n' "$p" >&2; cat >/dev/null; return 0; fi
  ${LS_SUDO:+"$LS_SUDO"} mkdir -p "$(dirname "$p")"
  ${LS_SUDO:+"$LS_SUDO"} tee "$p.decal-new" >/dev/null
  if [[ -e $p ]]; then ${LS_SUDO:+"$LS_SUDO"} chmod --reference="$p" "$p.decal-new" 2>/dev/null || true; fi
  ${LS_SUDO:+"$LS_SUDO"} mv -f "$p.decal-new" "$p"
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
  if [[ -e $bk ]]; then srun cp -a "$bk" "$real.decal-new"; srun mv -f "$real.decal-new" "$real"; srun rm -f "$bk"
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

# --- asking on the terminal (DECAL_TTY_IN / DECAL_TTY_OUT stand in for it in tests) ---
have_tty() { { : < "${DECAL_TTY_IN:-/dev/tty}"; } 2>/dev/null; }
# tty_ask PROMPT : one answer, in REPLY; fails at the end of input (Ctrl+D), so the caller says what that means
tty_ask() { printf '%s' "$1" >> "${DECAL_TTY_OUT:-/dev/tty}"; REPLY=""; IFS= read -r REPLY < "${DECAL_TTY_IN:-/dev/tty}"; }
# --- what a module put in place: one name per line in a record, so remove takes exactly that ---
rec_has() { grep -qxF "$2" "$1" 2>/dev/null; }            # rec_has REC NAME
rec_add() { rec_has "$1" "$2" || echo "$2" >> "$1"; }     # rec_add REC NAME
# rec_remove_all REC DIR : remove DIR/NAME for each NAME in REC, then REC
rec_remove_all() {
  [[ -r $1 ]] || return 0
  local n; while IFS= read -r n; do if [[ -n $n ]]; then run rm -rf "${2:?}/$n"; fi; done < "$1"
  run rm -f "$1"
}
# install_owned DIR NAME SRC REC : SRC copied to DIR/NAME and recorded; a DIR/NAME decal didn't put there is left as is
install_owned() {
  if [[ -e $1/$2 ]] && ! rec_has "$4" "$2"; then warn "$1/$2 already exists and isn't from decal: left as is"; return 0; fi
  rm -rf "${1:?}/$2"; cp -a "$3" "$1/$2"; rec_add "$4" "$2"
}
# gs_save PREV SCHEMA KEY... : the keys' current values, saved once (the first add) for remove to put back
gs_save() {
  local f=$1 s=$2 k; shift 2
  if [[ -e $f || $LS_DRY_RUN == 1 ]]; then return 0; fi
  mkdir -p "$(dirname "$f")"
  for k; do echo "$k=$(gsettings get "$s" "$k")"; done > "$f"
}
# gs_restore PREV SCHEMA : put the saved values back, then forget them
gs_restore() {
  [[ -r $1 ]] || return 0
  local k v; while IFS='=' read -r k v; do run gsettings set "$2" "$k" "$v"; done < "$1"
  run rm -f "$1"
}
# stamp_theme MODULE KEY DIR... : the theme in org.gnome.desktop.interface KEY, bundled into the stamp when it's
# installed in one of DIRs (your home); the system's own themes come with the system, so there's nothing to carry
stamp_theme() {
  have dconf || return 0
  local m=$1 key=$2 t d="" b; shift 2
  t=$(dconf read "/org/gnome/desktop/interface/$key" 2>/dev/null | tr -d "'"); [[ -n $t ]] || return 0
  for b; do if [[ -d $b/$t ]]; then d=$b/$t; break; fi; done
  if [[ -z $d ]]; then stamp_note "$m: $t (comes with the system: not stamped)"; return 0; fi
  stamp_copy "$d" "themes/$m/$t" >/dev/null
  stamp_note "$m: $t (bundled, $(du -sh "$d" 2>/dev/null | cut -f1))"
  printf '[%s]\nsource = "themes/%s"\ntheme = "%s"\n' "$m" "$m" "$t"
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
