# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile (P_*)
MODULE_DESC="GNOME preferences, dock, app launcher and your app folders (dconf)"
MERGE_KEYS=(/org/gnome/desktop/app-folders/folder-children)
_gs() {  # _gs CMD [extra args]
  local m f args=(); for m in "${MERGE_KEYS[@]}"; do args+=(--merge "$m"); done
  for f in "${P_file[@]}"; do args+=(--ini "$f"); done   # several files (e.g. a tag's): in order, a later one wins
  python3 "$LS_REPO/lib/dconf_tool.py" "$1" --base / \
    --prev "$LS_USER_STATE/gnome-settings.prev.json" --subst "@HOME@=$HOME" --subst "@TERMINAL_CMD@=$(terminal_cmd)" "${args[@]}" "${@:2}"
}
module_add() {
  have dconf || die "dconf not found (GNOME required)"
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] would apply $(cat "${P_file[@]}" | grep -c '=') keys from ${P_file[*]}"; return 0; fi
  step "applying GNOME settings"
  _gs apply
}
module_remove() { [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] would restore saved settings"; return 0; }; _gs remove; }
module_status() { if (( ${#P_file[@]} == 0 )); then echo not-installed; return 0; fi; _gs status | tail -1; }
module_capture() { python3 "$LS_REPO/lib/dconf_tool.py" capture --base /; }
