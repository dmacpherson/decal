# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="SSH client configuration, authorized keys, known hosts, and host definitions"
MODULE_NEEDS_ROOT=0
STAMP_LIVE=1

SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
CONFIG_FILE="$SSH_DIR/config"
AUTH_REC="$LS_USER_STATE/ssh-auth.installed"
KNOWN_REC="$LS_USER_STATE/ssh-known.installed"

_strip_decal_block() {
  local f=$1
  [[ -f $f ]] || return 0
  sed -i '/^# decal ssh: begin/,/^# decal ssh: end/d' "$f"
  if [[ ! -s $f ]]; then rm -f "$f"; fi
}

module_add() {
  mkdir -p "$SSH_DIR" "$LS_USER_STATE"
  chmod 700 "$SSH_DIR"

  # 1. Authorized keys
  local k
  for k in "${P_authorized_keys[@]}"; do
    [[ -n $k ]] || continue
    if [[ ! -f $AUTH_KEYS ]] || ! grep -qxF "$k" "$AUTH_KEYS"; then
      if [[ $LS_DRY_RUN == 1 ]]; then
        log "[dry-run] add authorized key: $k"
      else
        echo "$k" >> "$AUTH_KEYS"
        rec_add "$AUTH_REC" "$k"
      fi
    fi
  done
  [[ -f $AUTH_KEYS ]] && chmod 600 "$AUTH_KEYS"

  # 2. Known hosts
  local h
  for h in "${P_known_hosts[@]}"; do
    [[ -n $h ]] || continue
    if [[ ! -f $KNOWN_HOSTS ]] || ! grep -qxF "$h" "$KNOWN_HOSTS"; then
      if [[ $LS_DRY_RUN == 1 ]]; then
        log "[dry-run] add known host: $h"
      else
        echo "$h" >> "$KNOWN_HOSTS"
        rec_add "$KNOWN_REC" "$h"
      fi
    fi
  done
  [[ -f $KNOWN_HOSTS ]] && chmod 644 "$KNOWN_HOSTS"

  # 3. SSH Client Config
  local has_cfg=0
  if [[ -n $P_config ]] || (( ${#P_config_lines[@]} )) || (( ${#P_hosts[@]} )); then
    has_cfg=1
  fi

  if (( has_cfg )); then
    _strip_decal_block "$CONFIG_FILE"
    if [[ $LS_DRY_RUN == 1 ]]; then
      log "[dry-run] update $CONFIG_FILE with decal host block"
    else
      {
        echo "# decal ssh: begin"
        if [[ -n $P_config && -f $P_config ]]; then
          cat "$P_config"
          echo
        fi
        local l
        for l in "${P_config_lines[@]}"; do
          echo "$l"
        done
        local host
        for host in "${!P_hosts[@]}"; do
          local val="${P_hosts[$host]}"
          if [[ $val == "Host "* || $val == "Match "* ]]; then
            echo "$val"
          else
            echo "Host $host"
            printf '  %s\n' "$val"
          fi
          echo
        done
        echo "# decal ssh: end"
      } >> "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
    fi
  fi
  return 0
}

module_remove() {
  if [[ -r $AUTH_REC ]]; then
    if [[ -f $AUTH_KEYS ]]; then
      while IFS= read -r k; do
        [[ -n $k ]] || continue
        grep -vxF "$k" "$AUTH_KEYS" > "$AUTH_KEYS.t" || true
        mv "$AUTH_KEYS.t" "$AUTH_KEYS"
      done < "$AUTH_REC"
      if [[ ! -s $AUTH_KEYS ]]; then rm -f "$AUTH_KEYS"; fi
    fi
    rm -f "$AUTH_REC"
  fi

  if [[ -r $KNOWN_REC ]]; then
    if [[ -f $KNOWN_HOSTS ]]; then
      while IFS= read -r h; do
        [[ -n $h ]] || continue
        grep -vxF "$h" "$KNOWN_HOSTS" > "$KNOWN_HOSTS.t" || true
        mv "$KNOWN_HOSTS.t" "$KNOWN_HOSTS"
      done < "$KNOWN_REC"
      if [[ ! -s $KNOWN_HOSTS ]]; then rm -f "$KNOWN_HOSTS"; fi
    fi
    rm -f "$KNOWN_REC"
  fi

  _strip_decal_block "$CONFIG_FILE"
  return 0
}

module_status() {
  local missing=() total=0 have_n=0 k h
  for k in "${P_authorized_keys[@]}"; do
    total=$((total+1))
    if [[ -f $AUTH_KEYS ]] && grep -qxF "$k" "$AUTH_KEYS"; then
      have_n=$((have_n+1))
    else
      missing+=("authorized-key")
    fi
  done

  for h in "${P_known_hosts[@]}"; do
    total=$((total+1))
    if [[ -f $KNOWN_HOSTS ]] && grep -qxF "$h" "$KNOWN_HOSTS"; then
      have_n=$((have_n+1))
    else
      missing+=("known-host")
    fi
  done

  if [[ -n $P_config ]] || (( ${#P_config_lines[@]} )) || (( ${#P_hosts[@]} )); then
    total=$((total+1))
    if [[ -f $CONFIG_FILE ]] && grep -qxF "# decal ssh: begin" "$CONFIG_FILE"; then
      have_n=$((have_n+1))
    else
      missing+=("config")
    fi
  fi

  if (( total == 0 )); then
    echo "installed"
  elif (( have_n == total )); then
    echo "installed"
  elif (( have_n == 0 )); then
    echo "not-installed"
  else
    echo "partial (missing: ${missing[*]})"
  fi
}

module_stamp() {
  local auth=() known=() k h
  if [[ -r $AUTH_KEYS ]]; then
    while IFS= read -r k; do
      [[ -n $k && ($k == ssh-* || $k == ecdsa-* || $k == sk-*) ]] || continue
      auth+=("$k")
    done < "$AUTH_KEYS"
  fi
  if [[ -r $KNOWN_HOSTS ]]; then
    while IFS= read -r h; do
      [[ -n $h && $h != "#"* ]] || continue
      known+=("$h")
    done < "$KNOWN_HOSTS"
  fi

  (( ${#auth[@]} || ${#known[@]} )) || return 0
  stamp_note "ssh: ${#auth[@]} authorized keys, ${#known[@]} known hosts"
  echo "[ssh]"
  if (( ${#auth[@]} )); then
    printf 'authorized-keys = %s\n' "$(toml_list "${auth[@]}")"
  fi
  if (( ${#known[@]} )); then
    printf 'known-hosts = %s\n' "$(toml_list "${known[@]}")"
  fi
}
