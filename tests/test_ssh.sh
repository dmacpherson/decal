#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup

export HOME="$T_TMP/home"
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Pre-existing keys and config
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPreExistingUserKey original@host" > "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

echo "existing.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldHostKey" > "$SSH_DIR/known_hosts"
chmod 644 "$SSH_DIR/known_hosts"

echo -e "Host oldserver\n  User olduser" > "$SSH_DIR/config"
chmod 600 "$SSH_DIR/config"

P="$T_TMP/profile"
mkdir -p "$P"
cat > "$P/profile.toml" <<'EOF'
[ssh]
authorized-keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDecalManagedKey decal@machine"
]
known-hosts = [
  "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
]
config-lines = [
  "ServerAliveInterval 60",
  "ServerAliveCountMax 3"
]

[ssh.hosts]
myserver = "HostName 192.168.1.100\n  User myuser\n  Port 2222"
EOF

run_mod() {
  (
    set -euo pipefail
    source "$REPO/lib/common.sh"
    LS_REPO="$REPO"
    LS_USER_STATE="$DECAL_USER_STATE"
    LS_DRY_RUN=0
    export STAMP_NOTES="$T_TMP/stamp_notes"
    : > "$STAMP_NOTES"
    penv=$(python3 "$REPO/lib/profile.py" shell ssh --profile "$P" --modules "$REPO/modules") || exit 3
    eval "$penv"
    cd "$REPO/modules/ssh"
    source ./module.sh
    "module_$1"
  )
}

# 1. Test add
run_mod add

# Permissions
assert_eq "$(stat -c %a "$SSH_DIR")" "700" "~/.ssh permission 700"
assert_eq "$(stat -c %a "$SSH_DIR/authorized_keys")" "600" "authorized_keys permission 600"
assert_eq "$(stat -c %a "$SSH_DIR/known_hosts")" "644" "known_hosts permission 644"
assert_eq "$(stat -c %a "$SSH_DIR/config")" "600" "config permission 600"

# Contents
assert_contains "$(cat "$SSH_DIR/authorized_keys")" "original@host" "pre-existing authorized key kept"
assert_contains "$(cat "$SSH_DIR/authorized_keys")" "decal@machine" "decal authorized key added"

assert_contains "$(cat "$SSH_DIR/known_hosts")" "existing.example.com" "pre-existing known host kept"
assert_contains "$(cat "$SSH_DIR/known_hosts")" "github.com" "decal known host added"

assert_contains "$(cat "$SSH_DIR/config")" "Host oldserver" "pre-existing config kept"
assert_contains "$(cat "$SSH_DIR/config")" "ServerAliveInterval 60" "config-lines added"
assert_contains "$(cat "$SSH_DIR/config")" "Host myserver" "host block added"
assert_contains "$(cat "$SSH_DIR/config")" "Port 2222" "host details added"

# State records
assert_contains "$(cat "$DECAL_USER_STATE/ssh-auth.installed")" "decal@machine" "auth key recorded"
assert_contains "$(cat "$DECAL_USER_STATE/ssh-known.installed")" "github.com" "known host recorded"

# 2. Test status
st=$(run_mod status)
assert_eq "$st" "installed" "status reports installed"

# 3. Test stamp
stamp_out=$(run_mod stamp)
assert_contains "$stamp_out" '[ssh]' "stamp prints [ssh]"
assert_contains "$stamp_out" 'authorized-keys =' "stamp lists authorized keys"
assert_contains "$stamp_out" 'known-hosts =' "stamp lists known hosts"

# 4. Test remove
run_mod remove

# Decal items removed, pre-existing preserved
assert_contains "$(cat "$SSH_DIR/authorized_keys")" "original@host" "pre-existing authorized key preserved"
assert_not_contains "$(cat "$SSH_DIR/authorized_keys")" "decal@machine" "decal authorized key removed"

assert_contains "$(cat "$SSH_DIR/known_hosts")" "existing.example.com" "pre-existing known host preserved"
assert_not_contains "$(cat "$SSH_DIR/known_hosts")" "github.com" "decal known host removed"

assert_contains "$(cat "$SSH_DIR/config")" "Host oldserver" "pre-existing config preserved"
assert_not_contains "$(cat "$SSH_DIR/config")" "ServerAliveInterval 60" "decal config lines removed"
assert_not_contains "$(cat "$SSH_DIR/config")" "Host myserver" "decal host block removed"

assert_nofile "$DECAL_USER_STATE/ssh-auth.installed" "auth record deleted"
assert_nofile "$DECAL_USER_STATE/ssh-known.installed" "known record deleted"

t_done
