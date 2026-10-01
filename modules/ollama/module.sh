# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Ollama (local AI models) from Homebrew, running as your user, plus the models in your profile"
# Homebrew keeps it current (brew upgrade); the service runs Homebrew's stable bin/ link, never a versioned path
export HOMEBREW_NO_SUDO=1   # brew would otherwise reset decal's sudo session
UNIT_NAME=decal-ollama.service
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$UNIT_NAME"
REC="$LS_USER_STATE/ollama.installed"   # "cask ollama-binary" / "formula ollama": what decal installed
_pkg() { if [[ $P_gpu == true ]]; then echo "cask ollama-binary"; else echo "formula ollama"; fi; }
_bin() { echo "$(brew --prefix)/bin/ollama"; }
_have_ollama() { [[ -x $(_bin) ]] || have ollama; }

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
_service() {
  # someone else's Ollama service already serving (e.g. a system install): use that one
  if systemctl --quiet is-active ollama.service 2>/dev/null || systemctl --user --quiet is-active ollama.service 2>/dev/null; then return 0; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] user service $UNIT_NAME: $(_bin) serve"; return 0; fi
  mkdir -p "$(dirname "$UNIT")"
  printf '%s\n' "[Unit]" "Description=Ollama (decal)" "After=network-online.target" "" "[Service]" \
    "ExecStart=$(_bin) serve" "Restart=on-failure" "" "[Install]" "WantedBy=default.target" > "$UNIT"
  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT_NAME"
}
_models() {
  (( ${#P_models[@]} )) || return 0
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] download models: ${P_models[*]}"; return 0; }
  local i m have_list
  for i in $(seq 30); do have_list=$("$(_bin)" list 2>/dev/null) && break; sleep 1; done   # wait for the server
  for m in "${P_models[@]}"; do
    [[ $m == *:* ]] || m="$m:latest"
    if awk 'NR > 0 {print $1}' <<<"$have_list" | grep -qxF "$m"; then continue; fi
    step "downloading model $m"
    "$(_bin)" pull "${m%:latest}" || warn "could not download model $m"
  done
}

module_add() { _install; _service; _models; }

module_remove() {
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
  local why=() m list
  if [[ -e $UNIT ]] && ! systemctl --user --quiet is-active "$UNIT_NAME" 2>/dev/null; then why+=("service not running"); fi
  list=$("$(_bin)" list 2>/dev/null || true)
  for m in "${P_models[@]}"; do [[ $m == *:* ]] || m="$m:latest"; awk '{print $1}' <<<"$list" | grep -qxF "$m" || why+=("model $m missing"); done
  if (( ${#why[@]} )); then echo "partial (${why[*]})"; else echo installed; fi
}
