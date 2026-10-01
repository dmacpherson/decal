# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Display scaling for every monitor (e.g. 150%), saved like GNOME Settings does"
PREV="$LS_USER_STATE/display.prev"   # the layout before decal changed it (put back by remove)
_s() { python3 "$MODULE_DIR/scale.py" "$@"; }

module_add() {
  local st pl; st=$(mktemp); pl=$(mktemp)   # inside decal: the run's own temp dir
  if ! _s get > "$st" 2>/dev/null; then warn "no GNOME display information (not in a GNOME session?): display scale skipped"; return 0; fi
  _s plan "$st" "$P_scale" > "$pl"
  if grep -q '"unchanged": true' "$pl"; then log "every monitor is already at $P_scale"; return 0; fi
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] set every monitor to $P_scale: $(cat "$pl")"; return 0; }
  mkdir -p "$LS_USER_STATE"
  [[ -e $PREV ]] || cp "$st" "$PREV"
  step "setting every monitor to $(python3 -c "print(f'{float(\"$P_scale\")*100:g}%')")"
  _s apply "$pl"
}
module_remove() {
  [[ -r $PREV ]] || return 0
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] restore the previous display layout"; return 0; }
  _s apply "$PREV" || warn "could not restore the previous display layout (different monitors?)"
  rm -f "$PREV"
}
module_status() {
  local st; st=$(mktemp)
  _s get > "$st" 2>/dev/null || { echo "partial (no GNOME display information)"; return 0; }
  if _s plan "$st" "$P_scale" 2>/dev/null | grep -q '"unchanged": true'; then echo installed; else echo "partial (not every monitor at $P_scale)"; fi
}
