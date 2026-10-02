# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Ollama (local AI models) from Homebrew, running as your user, plus the models in your profile (downloaded in the background)"
# Homebrew keeps it current (brew upgrade); the service runs Homebrew's stable bin/ link, never a versioned path
export HOMEBREW_NO_SUDO=1   # brew would otherwise reset decal's sudo session
UNIT_NAME=decal-ollama.service
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$UNIT_NAME"
REC="$LS_USER_STATE/ollama.installed"   # "cask ollama-binary" / "formula ollama": what decal installed
JOB=decal-ollama-models   # background download job (transient systemd user unit, see pull-models.sh)
_pkg() { if [[ $P_gpu == true ]]; then echo "cask ollama-binary"; else echo "formula ollama"; fi; }
_bin() { echo "$(brew --prefix)/bin/ollama"; }
_have_ollama() { [[ -x $(_bin) ]] || have ollama; }
_cli() { if [[ -x $(_bin) ]]; then _bin; else command -v ollama; fi; }

_install() {
  local kind name; read -r kind name <<<"$(_pkg)"
  if [[ -r $REC && $(cat "$REC") != "$kind $name" ]]; then _uninstall; fi   # gpu switched: swap builds
  _have_ollama && return 0
  have brew || die "Homebrew not found (needed for Ollama)"
  step "installing Ollama ($( [[ $kind == cask ]] && echo GPU || echo CPU ) build)"
  if [[ $kind == cask ]]; then run brew install --cask "$name"; else run brew install "$name"; fi
  [[ $LS_DRY_RUN == 1 ]] || { mkdir -p "$LS_USER_STATE"; echo "$kind $name" > "$REC"; }
}
_uninstall() {
  [[ -r $REC ]] || return 0
  local kind name; read -r kind name < "$REC"
  if [[ $kind == cask ]]; then run brew uninstall --cask "$name"; else run brew uninstall "$name"; fi
  run rm -f "$REC"
}
# integrated GPU (laptops): Ollama leaves it alone unless OLLAMA_IGPU_ENABLE=1. auto = only when Vulkan (which
# Ollama uses for it) sees an integrated GPU and no discrete one, so a desktop's CPU graphics don't get a share.
_igpu() {
  case $P_igpu in on) return 0 ;; off) return 1 ;; esac
  local types
  if types=$(vulkaninfo --summary 2>/dev/null | grep -oE 'PHYSICAL_DEVICE_TYPE_(INTEGRATED|DISCRETE)_GPU'); then
    grep -q INTEGRATED <<<"$types" && ! grep -q DISCRETE <<<"$types"; return
  fi
  ! cat "${DECAL_SYS_DRM:-/sys/class/drm}"/card*/device/vendor 2>/dev/null | grep -qx 0x10de   # no vulkaninfo: anything but NVIDIA
}
_unit_text() {
  printf '%s\n' "[Unit]" "Description=Ollama (decal)" "After=network-online.target" "" "[Service]" "ExecStart=$(_bin) serve"
  if [[ $P_gpu == true ]] && _igpu; then echo "Environment=OLLAMA_IGPU_ENABLE=1"; fi
  printf '%s\n' "Restart=on-failure" "" "[Install]" "WantedBy=default.target"
}
_service() {
  # someone else's Ollama service already serving (e.g. a system install): use that one
  if systemctl --quiet is-active ollama.service 2>/dev/null || systemctl --user --quiet is-active ollama.service 2>/dev/null; then
    if [[ $P_gpu == true ]] && _igpu; then warn "Ollama runs as another service here: set OLLAMA_IGPU_ENABLE=1 in it to use the integrated GPU"; fi
    return 0
  fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] user service $UNIT_NAME: $(_bin) serve"; return 0; fi
  local want had=0; want=$(_unit_text)
  if [[ -e $UNIT && $(cat "$UNIT") == "$want" ]]; then systemctl --user enable --now "$UNIT_NAME"; return 0; fi
  [[ -e $UNIT ]] && had=1
  mkdir -p "$(dirname "$UNIT")"; printf '%s\n' "$want" > "$UNIT"
  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT_NAME"
  if (( had )); then systemctl --user restart "$UNIT_NAME"; fi   # changed settings take effect now
}
# the profile's models not downloaded yet (all of them while the server isn't answering yet)
_missing() {
  local list m; list=$("$(_cli)" list 2>/dev/null | awk '{print $1}')
  for m in "${P_models[@]}"; do
    if [[ $m == *:* ]]; then grep -qxF "$m" <<<"$list" || echo "$m"; else grep -qxF "$m:latest" <<<"$list" || echo "$m"; fi
  done
}
_pulling() { systemctl --user --quiet is-active "$JOB" 2>/dev/null; }
# missing models download in the background; a later run finds the job still going, or starts it again if it
# stopped short. Nothing is ever deleted: models taken off the list stay.
_models() {
  local missing; mapfile -t missing < <(_missing)
  (( ${#missing[@]} )) || return 0
  if _pulling; then info "models still downloading in the background (${missing[*]}): journalctl --user -u $JOB -f"; return 0; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] download in the background: ${missing[*]}"; return 0; fi
  step "downloading models in the background: ${missing[*]}"
  systemd-run --user --unit="$JOB" --collect --quiet --description="decal: download Ollama models" \
    bash "$MODULE_DIR/pull-models.sh" "$(_cli)" "${missing[@]}" || { warn "could not start the model download"; return 0; }
  info "models downloading in the background; follow them with: journalctl --user -u $JOB -f"
}

module_add() { _install; _service; _models; }

module_remove() {
  if _pulling; then run systemctl --user stop "$JOB"; fi
  if [[ -e $UNIT ]]; then
    run systemctl --user disable --now "$UNIT_NAME" || true
    run rm -f "$UNIT"; run systemctl --user daemon-reload
  fi
  _uninstall
  if [[ -d $HOME/.ollama ]]; then
    info "your downloaded models are kept in ~/.ollama ($(du -sh "$HOME/.ollama" 2>/dev/null | cut -f1)); delete them with: rm -rf ~/.ollama"
  fi
}

module_status() {
  _have_ollama || { echo not-installed; return 0; }
  local why=() missing
  if [[ -e $UNIT ]] && ! systemctl --user --quiet is-active "$UNIT_NAME" 2>/dev/null; then why+=("service not running"); fi
  if [[ -e $UNIT && $(cat "$UNIT") != "$(_unit_text)" ]]; then why+=("service settings out of date"); fi
  mapfile -t missing < <(_missing)
  if (( ${#missing[@]} )); then
    if _pulling; then why+=("downloading ${missing[*]}"); else why+=("missing ${missing[*]}"); fi
  fi
  if (( ${#why[@]} )); then echo "partial (${why[*]})"; else echo installed; fi
}
