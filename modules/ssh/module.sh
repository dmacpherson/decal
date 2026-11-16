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

_ssh_config_block() {
  if [[ -n $P_config && -r $P_config ]]; then
    cat "$P_config"
    echo
  fi
  local l
  for l in "${P_config_lines[@]}"; do
    [[ $l != *$'\n'* ]] || die "ssh config-lines item cannot contain newlines"
    echo "$l"
  done
  local host
  while IFS= read -r host; do
    [[ -n $host ]] || continue
    local val="${P_hosts[$host]}"
    if [[ $val == "Host "* || $val == "Match "* ]]; then
      echo "$val"
    else
      echo "Host $host"
      printf '  %s\n' "$val"
    fi
    echo
  done < <(printf '%s\n' "${!P_hosts[@]}" | sort)
}

_ssh_append_lines() {
  local label=$1 file=$2 rec=$3 mode=$4 item real
  shift 4
  for item; do
    [[ -n $item ]] || continue
    [[ $item != *$'\n'* ]] || die "ssh $label cannot contain newlines"
    if [[ ! -f $file ]] || ! grep -qxF "$item" "$file"; then
      if [[ $LS_DRY_RUN == 1 ]]; then
        log "[dry-run] add $label: $item"
      else
        mkdir -p "$SSH_DIR" "$LS_USER_STATE"
        chmod 700 "$SSH_DIR"
        real=$(realpath -m -- "$file")
        mkdir -p "$(dirname "$real")"
        echo "$item" >> "$real"
        chmod "$mode" "$real"
        rec_add "$rec" "$item"
      fi
    fi
  done
  if [[ $LS_DRY_RUN != 1 && -f $file ]]; then
    chmod "$mode" "$(realpath -m -- "$file")"
  fi
}

_ssh_remove_lines() {
  local label=$1 file=$2 rec=$3 mode=$4
  [[ -r $rec ]] || return 0
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] remove recorded $label entries from $file"
    return 0
  fi
  if [[ -f $file ]]; then
    python3 -c '
import os, sys
file_path, rec_path, mode = sys.argv[1:4]
is_link = os.path.islink(file_path)
real = os.path.realpath(file_path)
with open(rec_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    drop = {line.rstrip("\n") for line in f if line.rstrip("\n")}
with open(real, "r", encoding="utf-8", errors="surrogateescape") as f:
    kept = [line for line in f if line.rstrip("\n") not in drop]
if not kept and not is_link:
    if os.path.lexists(file_path):
        os.unlink(file_path)
    sys.exit(0)
tmp = os.path.join(os.path.dirname(real), f".{os.path.basename(real)}.decal-new")
with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.writelines(kept)
os.chmod(tmp, int(mode, 8))
os.replace(tmp, real)
' "$file" "$rec" "$mode"
  fi
  rm -f "$rec"
}

module_add() {
  _ssh_append_lines "authorized key" "$AUTH_KEYS" "$AUTH_REC" 600 "${P_authorized_keys[@]}"
  _ssh_append_lines "known host" "$KNOWN_HOSTS" "$KNOWN_REC" 644 "${P_known_hosts[@]}"

  local has_cfg=0
  if [[ -n $P_config ]] || (( ${#P_config_lines[@]} )) || (( ${#P_hosts[@]} )); then
    has_cfg=1
  fi
  if (( has_cfg )); then
    if [[ $LS_DRY_RUN != 1 ]]; then
      mkdir -p "$SSH_DIR" "$LS_USER_STATE"
      chmod 700 "$SSH_DIR"
    fi
    _ssh_config_block | user_block_set "$CONFIG_FILE" "ssh" 600 prepend
  fi
  return 0
}

module_remove() {
  _ssh_remove_lines "authorized key" "$AUTH_KEYS" "$AUTH_REC" 600
  _ssh_remove_lines "known host" "$KNOWN_HOSTS" "$KNOWN_REC" 644
  user_block_set "$CONFIG_FILE" "ssh" </dev/null
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
    local cur_cfg exp_cfg
    cur_cfg=$(user_block_get "$CONFIG_FILE" "ssh" 2>/dev/null || true)
    exp_cfg=$(_ssh_config_block)
    if [[ -n $cur_cfg && $cur_cfg == "$exp_cfg" ]]; then
      have_n=$((have_n+1))
    else
      missing+=("config")
    fi
  fi

  if (( total == 0 || have_n == total )); then
    echo "installed"
  elif (( have_n == 0 )); then
    echo "not-installed"
  else
    echo "partial (missing: ${missing[*]})"
  fi
}

module_stamp() {
  local auth=() known=() k h cfg_toml=""
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
  if [[ -r $CONFIG_FILE ]]; then
    cfg_toml=$(python3 -c '
import json, re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    lines = [l.rstrip("\r\n") for l in f]
global_lines, hosts = [], []
cur_host, cur_body = None, []
def flush():
    if cur_host is not None and cur_body:
        first = cur_body[0].lstrip()
        rest = [("  " + x.lstrip()) for x in cur_body[1:]]
        hosts.append((cur_host, "\n".join([first] + rest)))
for raw in lines:
    s = raw.strip()
    if s in ("# decal ssh: begin", "# decal ssh: end") or not s:
        continue
    if s.startswith("Host ") or s.startswith("Match "):
        flush()
        if s.startswith("Host ") and len(s.split()) == 2:
            cur_host, cur_body = s.split()[1], []
        else:
            cur_host, cur_body = None, []
            global_lines.append(s)
    elif cur_host is not None:
        cur_body.append(raw)
    elif not s.startswith("#"):
        global_lines.append(s)
flush()
out = []
if global_lines:
    out.append("config-lines = [" + ", ".join(json.dumps(x) for x in global_lines) + "]")
if hosts:
    out.append("\n[ssh.hosts]")
    for h, body in hosts:
        k = h if re.fullmatch(r"[A-Za-z0-9_-]+", h) else json.dumps(h)
        out.append(f"{k} = {json.dumps(body)}")
sys.stdout.write("\n".join(out))
' "$CONFIG_FILE")
  fi

  (( ${#auth[@]} || ${#known[@]} )) || [[ -n $cfg_toml ]] || return 0
  stamp_note "ssh: ${#auth[@]} authorized keys, ${#known[@]} known hosts"
  echo "[ssh]"
  if (( ${#auth[@]} )); then
    printf 'authorized-keys = %s\n' "$(toml_list "${auth[@]}")"
  fi
  if (( ${#known[@]} )); then
    printf 'known-hosts = %s\n' "$(toml_list "${known[@]}")"
  fi
  if [[ -n $cfg_toml ]]; then
    printf '%s\n' "$cfg_toml"
  fi
}
