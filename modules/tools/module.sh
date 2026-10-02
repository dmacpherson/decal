# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Command-line tools from their official installers (uv), kept current with their own updaters"
# Each tool: its installer (always the latest release), the env that stops it editing shell startup files,
# what it installs, how it updates itself, and the data that remove keeps (with how to delete it).
declare -A T_URL=([uv]=https://astral.sh/uv/install.sh)
declare -A T_ENV=([uv]="UV_NO_MODIFY_PATH=1")
declare -A T_BINS=([uv]="uv uvx")
declare -A T_FILES=([uv]="${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv-receipt.json")
declare -A T_UPDATE=([uv]="uv self update")
declare -A T_KEEP=([uv]="installed Pythons and tools in ~/.local/share/uv and the cache in ~/.cache/uv are kept; delete them with: uv cache clean && rm -rf ~/.local/share/uv")
BIN="$HOME/.local/bin"
REC="$LS_USER_STATE/tools.installed"
_known() { printf '%s ' "${!T_URL[@]}" | xargs -n1 | sort | xargs; }
_ours() { grep -qxF "$1" "$REC" 2>/dev/null; }
_present() { local b; for b in ${T_BINS[$1]}; do [[ -x $BIN/$b ]] || have "$b" || return 1; done; }

_add() {
  local t=$1 inst envs=() upd=()
  read -ra envs <<<"${T_ENV[$t]:-}"; read -ra upd <<<"${T_UPDATE[$t]:-}"
  if ! _present "$t"; then
    [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] install $t (${T_URL[$t]})"; return 0; }
    step "installing $t"
    inst=$(ls_fetch "${T_URL[$t]}") || die "could not download the $t installer from ${T_URL[$t]}"
    env "${envs[@]}" sh "$inst" || die "the $t installer failed"
    mkdir -p "$LS_USER_STATE"; _ours "$t" || echo "$t" >> "$REC"
  elif (( ${#upd[@]} )); then
    step "updating $t"
    run env PATH="$BIN:$PATH" "${upd[@]}" || warn "$t: '${T_UPDATE[$t]}' failed (still installed)"
  fi
}
_remove() {   # only what decal installed
  local t=$1 b files=()
  _ours "$t" || return 0
  read -ra files <<<"${T_FILES[$t]:-}"
  for b in ${T_BINS[$t]}; do run rm -f "$BIN/$b"; done
  if (( ${#files[@]} )); then run rm -f "${files[@]}"; fi
  [[ -n ${T_KEEP[$t]:-} ]] && info "$t removed: ${T_KEEP[$t]}"
  if [[ $LS_DRY_RUN != 1 ]]; then grep -vxF "$t" "$REC" > "$REC.t" || true; mv "$REC.t" "$REC"; fi
}

module_add() {
  local t
  for t in "${P_install[@]}"; do [[ -n ${T_URL[$t]:-} ]] || die "unknown tool '$t' in [tools] install (known: $(_known))"; done
  for t in "${P_install[@]}"; do _add "$t"; done
  # tools decal installed earlier that left the list
  if [[ -r $REC ]]; then while IFS= read -r t; do [[ -n $t && " ${P_install[*]} " != *" $t "* ]] && _remove "$t"; done < <(cat "$REC"); fi
  return 0
}
module_remove() { local t; if [[ -r $REC ]]; then while IFS= read -r t; do [[ -n $t ]] && _remove "$t"; done < <(cat "$REC"); fi; return 0; }
module_status() {
  local t missing=()
  (( ${#P_install[@]} )) || { echo not-installed; return 0; }
  for t in "${P_install[@]}"; do _present "$t" || missing+=("$t"); done
  if (( ${#missing[@]} == ${#P_install[@]} )); then echo not-installed
  elif (( ${#missing[@]} )); then echo "partial (missing: ${missing[*]})"
  else echo installed; fi
}
# stamp: the tools decal knows, installed in your home -> [tools.dev]
module_stamp() {
  local t on=()
  for t in "${!T_URL[@]}"; do if [[ -x $HOME/.local/bin/$t ]]; then on+=("$t"); fi; done
  (( ${#on[@]} )) || return 0
  stamp_note "tools: ${on[*]} (dev tag)"
  printf '[tools.dev]\ninstall = %s\n' "$(toml_list "${on[@]}")"
}
