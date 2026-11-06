#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup

# Create sandbox git environment
export HOME="$T_TMP/home"
export XDG_CONFIG_HOME="$T_TMP/home/.config"
mkdir -p "$XDG_CONFIG_HOME/git"

# Pre-existing git config
git config --global user.name "Old Name"
git config --global core.editor "vim"

P="$T_TMP/profile"
mkdir -p "$P"
cat > "$P/profile.toml" <<'EOF'
[git]
name = "New Name"
email = "dev@example.com"
default-branch = "main"
editor = "nano"
signing-key = "KEY12345"
sign-commits = true
auto-setup-remote = true
pull-rebase = true
ignores = [".DS_Store", "*.swp"]

[git.aliases]
co = "checkout"
st = "status -sb"
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
    penv=$(python3 "$REPO/lib/profile.py" shell git --profile "$P" --modules "$REPO/modules") || exit 3
    eval "$penv"
    cd "$REPO/modules/git"
    source ./module.sh
    "module_$1"
  )
}

# 1. Test add
run_mod add
assert_eq "$(git config --global --get user.name)" "New Name" "user.name updated"
assert_eq "$(git config --global --get user.email)" "dev@example.com" "user.email set"
assert_eq "$(git config --global --get init.defaultBranch)" "main" "init.defaultBranch set"
assert_eq "$(git config --global --get core.editor)" "nano" "core.editor updated"
assert_eq "$(git config --global --get user.signingkey)" "KEY12345" "signing-key set"
assert_eq "$(git config --global --get commit.gpgsign)" "true" "commit.gpgsign set"
assert_eq "$(git config --global --get push.autoSetupRemote)" "true" "push.autoSetupRemote set"
assert_eq "$(git config --global --get pull.rebase)" "true" "pull.rebase set"
assert_eq "$(git config --global --get alias.co)" "checkout" "alias.co set"
assert_eq "$(git config --global --get alias.st)" "status -sb" "alias.st set"

# Check ignores
assert_file "$XDG_CONFIG_HOME/git/ignore" "ignore file created"
assert_contains "$(cat "$XDG_CONFIG_HOME/git/ignore")" ".DS_Store" "ignore contains .DS_Store"
assert_contains "$(cat "$XDG_CONFIG_HOME/git/ignore")" "*.swp" "ignore contains *.swp"

# Check state recording
assert_file "$DECAL_USER_STATE/git.prev" "previous config recorded"
assert_contains "$(cat "$DECAL_USER_STATE/git.prev")" "user.name=Old Name" "previous name recorded"
assert_contains "$(cat "$DECAL_USER_STATE/git.prev")" "core.editor=vim" "previous editor recorded"
assert_contains "$(cat "$DECAL_USER_STATE/git.prev")" "user.email=__UNSET__" "unset email recorded"

# 2. Test status
st=$(run_mod status)
assert_eq "$st" "installed" "status reports installed"

git config --global user.name "Tampered"
st_tampered=$(run_mod status)
assert_contains "$st_tampered" "partial (mismatch: user.name)" "status catches mismatch"
git config --global user.name "New Name"

# 3. Test stamp
stamp_out=$(run_mod stamp)
assert_contains "$stamp_out" '[git]' "stamp prints [git]"
assert_contains "$stamp_out" 'name = "New Name"' "stamp prints name"
assert_contains "$stamp_out" 'email = "dev@example.com"' "stamp prints email"
assert_contains "$stamp_out" 'default-branch = "main"' "stamp prints default-branch"

# 4. Test remove
run_mod remove
assert_eq "$(git config --global --get user.name)" "Old Name" "user.name restored"
assert_eq "$(git config --global --get core.editor)" "vim" "core.editor restored"
assert_nofile "$DECAL_USER_STATE/git.prev" "state file removed"

# Keys that were unset originally should now be unset
git config --global --get user.email >/dev/null 2>&1
assert_eq "$?" "1" "user.email unset"
git config --global --get init.defaultBranch >/dev/null 2>&1
assert_eq "$?" "1" "init.defaultBranch unset"
git config --global --get alias.co >/dev/null 2>&1
assert_eq "$?" "1" "alias.co unset"

# Ignores removed
assert_nofile "$XDG_CONFIG_HOME/git/ignore" "empty ignore file deleted"

t_done
