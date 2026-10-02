# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Docker Engine + Compose: packages, the docker service, you in the docker group"
MODULE_NEEDS_ROOT=1
WANTS=/etc/systemd/system/sockets.target.wants/docker.socket   # enabled by link: works before a Fedora Atomic reboot too
SHIM=/usr/local/bin/docker-compose                               # some distros only ship the `docker compose` plugin
ST="$LS_STATE/docker"
_me() { id -un; }
_compose_pkg() { if [[ $PLATFORM == debian ]] && apt-cache show docker-compose-v2 >/dev/null 2>&1; then echo docker-compose-v2; else echo docker-compose; fi; }
_in_group() { id -nG "$(_me)" 2>/dev/null | tr ' ' '\n' | grep -qx docker; }

_group_add() {
  _in_group && return 0
  local line="" r
  if ! grep -q '^docker:' "$(sys_path /etc/group)" 2>/dev/null; then
    line=$(getent group docker 2>/dev/null || true)
    if [[ -z $line && $PLATFORM == fedora-atomic ]]; then
      r=$(_pending_root); if [[ -n $r ]]; then line=$(grep -m1 '^docker:' "$r/usr/lib/group" 2>/dev/null || true); fi
    fi
    if [[ -z $line ]]; then warn "the docker group appears after the reboot: run ./decal add docker again then"; return 0; fi
    # Fedora Atomic keeps package groups in /usr/lib/group, which usermod can't change:
    # create the same group (same id) in /etc/group with the system's own tool
    srun groupadd -g "$(cut -d: -f3 <<<"$line")" docker
    : | swrite "$ST/group-added"
  fi
  srun usermod -aG docker "$(_me)"
  _me | swrite "$ST/member"
  info "log out and back in to use docker without sudo (the docker group gives root-level access)"
}
_group_remove() {
  if [[ -r $ST/member ]]; then srun gpasswd -d "$(cat "$ST/member")" docker || true; srun rm -f "$ST/member"; fi
  if [[ -r $ST/group-added ]]; then srun groupdel docker || true; srun rm -f "$ST/group-added"; fi
}

module_add() {
  pkg_install docker docker-engine "$(_compose_pkg)"
  local w; w=$(sys_path "$WANTS")
  if [[ ! -L $w && ! -e $w ]]; then
    step "enabling the docker service"
    srun mkdir -p "$(dirname "$w")"; srun ln -s /usr/lib/systemd/system/docker.socket "$w"
    : | swrite "$ST/socket"
  fi
  if [[ $PLATFORM != fedora-atomic ]]; then srun systemctl daemon-reload; srun systemctl start docker.socket || true; fi
  if ! have docker-compose && [[ ! -e $(sys_path "$SHIM") ]]; then
    printf '#!/bin/sh\nexec docker compose "$@"\n' | swrite "$(sys_path "$SHIM")"
    srun chmod 0755 "$(sys_path "$SHIM")"; : | swrite "$ST/shim"
  fi
  if [[ $P_group == true ]]; then _group_add; else _group_remove; fi
}

module_remove() {
  _group_remove
  if [[ -r $ST/shim ]]; then srun rm -f "$(sys_path "$SHIM")" "$ST/shim"; fi
  if [[ -r $ST/socket ]]; then
    if [[ $PLATFORM != fedora-atomic ]]; then srun systemctl stop docker.socket docker.service 2>/dev/null || true; fi
    srun rm -f "$(sys_path "$WANTS")" "$ST/socket"
    if [[ $PLATFORM != fedora-atomic ]]; then srun systemctl daemon-reload; fi
  fi
  pkg_remove docker
}

module_status() {
  local p; p=$(_pkg_name docker-engine)
  if ! _pkg_present "$p"; then echo not-installed; return 0; fi
  local why=()
  [[ -L $(sys_path "$WANTS") ]] || why+=("service not enabled")
  if [[ $P_group == true ]] && ! _in_group; then why+=("not in the docker group yet"); fi
  if (( ${#why[@]} )); then echo "partial (${why[*]})"
  elif ! have docker; then echo "installed (reboot pending)"
  else echo installed; fi
}
# stamp: Docker installed -> [docker.dev] (dev tools carry the dev tag), with whether you're in the docker group
module_stamp() {
  have docker || return 0
  local g=false; if id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then g=true; fi
  stamp_note "docker: installed (dev tag)"
  printf '[docker.dev]\ngroup = %s\n' "$g"
}
