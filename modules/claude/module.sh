# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Claude Code (CLI) and the Claude desktop app (Linux beta: Debian/Ubuntu)"
MODULE_NEEDS_ROOT=1   # the desktop app's apt repository and package
# CLI: Anthropic's installer, then claude updates itself. Desktop: Anthropic's apt repository, updated with the system.
CLI_REC="$LS_USER_STATE/claude.cli"
KEY=/usr/share/keyrings/claude-desktop-archive-keyring.asc
LIST=/etc/apt/sources.list.d/claude-desktop.list
KEY_URL=https://downloads.claude.ai/claude-desktop/key.asc
KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE   # Anthropic's signing key, as published in the install docs
REPO="deb [arch=amd64,arm64 signed-by=$KEY] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
ST="$LS_STATE/claude"

_cli_add() {   # an existing claude (installed any way) is used as is
  if [[ -e $HOME/.local/bin/claude ]] || have claude; then return 0; fi
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] install Claude Code (https://claude.ai/install.sh)"; return 0; }
  step "installing Claude Code"
  local inst; inst=$(ls_fetch https://claude.ai/install.sh) || die "could not download the Claude Code installer"
  bash "$inst" || die "the Claude Code installer failed"
  mkdir -p "$LS_USER_STATE"; : > "$CLI_REC"
}
_cli_remove() {   # only a claude decal installed; never ~/.claude or ~/.claude.json (settings, memory, history)
  [[ -e $CLI_REC ]] || return 0
  run rm -rf "$HOME/.local/bin/claude" "$HOME/.local/share/claude"; run rm -f "$CLI_REC"
}

_desktop_add() {
  if [[ $PLATFORM != debian ]]; then
    warn "Claude Desktop for Linux is a beta for Debian and Ubuntu only: skipped on this system (the CLI works everywhere)"
    return 0
  fi
  if [[ ! -e $(sys_path "$LIST") ]]; then
    step "adding Anthropic's apt repository"
    local key; key=$(ls_fetch "$KEY_URL") || die "could not download Anthropic's signing key from $KEY_URL"
    if [[ $LS_DRY_RUN != 1 ]]; then
      have gpg || pkg_install claude gnupg
      gpg --show-keys --with-colons "$key" 2>/dev/null | grep -q "^fpr:*$KEY_FPR:" \
        || die "the signing key from $KEY_URL doesn't have Anthropic's fingerprint $KEY_FPR: not installed"
    fi
    : | swrite "$ST/repo"   # the record first: an interrupted add can still be undone
    if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] write $(sys_path "$KEY") (Anthropic's signing key)"
    else swrite "$(sys_path "$KEY")" < "$key"; fi
    printf '%s\n' "$REPO" | swrite "$(sys_path "$LIST")"
    rm -f "${LS_RUNTMP:-/nonexistent}/apt-updated"   # the backend refreshes its lists before the next install
  fi
  pkg_install claude claude-desktop
  if [[ $P_cowork == true ]]; then _kvm_add; else _kvm_remove; fi
}
_desktop_remove() {
  _kvm_remove
  pkg_remove claude
  if [[ -e $ST/repo ]]; then srun rm -f "$(sys_path "$LIST")" "$(sys_path "$KEY")" "$ST/repo"; fi
}
# Cowork runs its tasks in a VM: it needs /dev/kvm and /dev/vhost-vsock, which the kvm group opens
_kvm_add() {
  id -nG | tr ' ' '\n' | grep -qx kvm && return 0
  srun usermod -aG kvm "$(id -un)"; id -un | swrite "$ST/kvm-member"
  info "log out and back in so the desktop app's Cowork tab can use virtualization (kvm group)"
}
_kvm_remove() { if [[ -r $ST/kvm-member ]]; then srun gpasswd -d "$(cat "$ST/kvm-member")" kvm || true; srun rm -f "$ST/kvm-member"; fi; }

module_add() {
  if [[ $P_cli == true ]]; then _cli_add; else _cli_remove; fi
  if [[ $P_desktop == true ]]; then _desktop_add; else _desktop_remove; fi
}
module_remove() { _desktop_remove; _cli_remove; }
module_status() {
  local parts=()
  if [[ $P_cli == true ]]; then if [[ -e $HOME/.local/bin/claude ]] || have claude; then parts+=("cli"); else parts+=("cli missing"); fi; fi
  if [[ $P_desktop == true ]]; then
    if [[ $PLATFORM != debian ]]; then parts+=("desktop: not available here")
    elif _pkg_present claude-desktop; then parts+=("desktop"); else parts+=("desktop missing"); fi
  fi
  if (( ${#parts[@]} == 0 )); then echo not-installed
  elif [[ " ${parts[*]} " == *missing* ]]; then echo "partial (${parts[*]})"
  else echo "installed (${parts[*]})"; fi
}
# stamp: Claude Code installed -> [claude.dev]
module_stamp() {
  have claude || [[ -x $HOME/.local/bin/claude ]] || return 0
  stamp_note "claude: Claude Code (dev tag)"
  printf '[claude.dev]\ncli = true\n'
}
