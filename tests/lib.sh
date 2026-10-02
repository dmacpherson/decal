# shellcheck shell=bash
# Minimal test harness: source it, call t_setup, write assertions, end with t_done.
set -uo pipefail
T_FAILS=0; T_COUNT=0
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_t_fail() { T_FAILS=$((T_FAILS+1)); printf '  FAIL: %s\n' "$*"; }
assert_eq()       { T_COUNT=$((T_COUNT+1)); [[ "$1" == "$2" ]] || _t_fail "${3:-assert_eq}: expected [$2] got [$1]"; }
assert_contains() { T_COUNT=$((T_COUNT+1)); [[ "$1" == *"$2"* ]] || _t_fail "${3:-assert_contains}: [$2] not in [$1]"; }
assert_not_contains() { T_COUNT=$((T_COUNT+1)); [[ "$1" != *"$2"* ]] || _t_fail "${3:-assert_not_contains}: [$2] unexpectedly in [$1]"; }
assert_file()     { T_COUNT=$((T_COUNT+1)); [[ -e "$1" ]] || _t_fail "${2:-assert_file}: missing $1"; }
assert_nofile()   { T_COUNT=$((T_COUNT+1)); [[ ! -e "$1" ]] || _t_fail "${2:-assert_nofile}: exists $1"; }

# Fresh sandbox: fake root, state dirs, stub bin dir first on PATH, no sudo.
t_setup() {
  T_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lstest.XXXXXX")"
  trap 'rm -rf "$T_TMP"' EXIT   # also when a test stops early
  export TMPDIR="$T_TMP"        # every temp file the code under test makes goes with it
  # never the real home: modules write and delete under $HOME and the XDG folders (tests may point them elsewhere);
  # tools installed in the real home (e.g. ~/.local/bin) are hidden too
  PATH=$(tr ':' '\n' <<<"$PATH" | grep -v -e "^$HOME/" -e "^/home/linuxbrew/" | paste -sd:); export PATH   # and Homebrew's tools
  export HOME="$T_TMP/home" XDG_CONFIG_HOME="$T_TMP/home/.config" XDG_DATA_HOME="$T_TMP/home/.local/share" \
         XDG_STATE_HOME="$T_TMP/home/.local/state" XDG_CACHE_HOME="$T_TMP/home/.cache"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
  export DECAL_ROOT="$T_TMP/root" DECAL_STATE="$T_TMP/state"
  export DECAL_USER_STATE="$T_TMP/ustate" DECAL_SUDO=""
  export STUBS="$T_TMP/stubs"; mkdir -p "$STUBS" "$DECAL_ROOT"
  : > "$STUBS/calls"; export PATH="$STUBS:$PATH"
}
# stub NAME [BODY]: fake command that logs "NAME args" to $STUBS/calls, then runs BODY.
stub() {
  local name=$1 body=${2:-true}
  cat > "$STUBS/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$STUBS/calls"
$body
EOF
  chmod +x "$STUBS/$name"
}
calls() { cat "$STUBS/calls"; }
t_done() { rm -rf "$T_TMP"; printf '%s: %d assertions, %d failed\n' "$(basename "$0")" "$T_COUNT" "$T_FAILS"; exit $(( T_FAILS > 0 )); }

# fixture_profile : copy the generic test profile and point PROFILE_DIR at it
fixture_profile() {
  cp -a "$REPO/tests/fixtures/profile" "$T_TMP/profile"
  export PROFILE_DIR="$T_TMP/profile" DECAL_PROFILE="$T_TMP/profile"
}
# mod_run MODULE FUNC [ARGS...] : run a module function the way the runner does (profile vars loaded).
# If the test defines mod_run_pre, it runs after the platform loads (to stub backend helpers).
mod_run() {
  local m=$1; shift
  ( set -euo pipefail
    source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    if declare -F mod_run_pre >/dev/null; then mod_run_pre; fi
    export MODULE_DIR="$REPO/modules/$m"; cd "$MODULE_DIR"
    # DECAL_DROP=TAG: the settings remove --only TAG gives module_drop
    penv=$(python3 "$REPO/lib/profile.py" shell "$m" --profile "$PROFILE_DIR" --modules "$REPO/modules" ${DECAL_DROP:+--drop "$DECAL_DROP"}) || exit 3
    eval "$penv"
    source ./module.sh; "$@" )
}
