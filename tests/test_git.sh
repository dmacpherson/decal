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

export DECAL_SUDO="false"

run_mod() {
  local op=$1 dry=${2:-0} prof=${3:-$P}
  (
    set -euo pipefail
    source "$REPO/lib/common.sh"
    LS_REPO="$REPO"
    LS_USER_STATE="$DECAL_USER_STATE"
    LS_DRY_RUN="$dry"
    export STAMP_NOTES="$T_TMP/stamp_notes"
    : > "$STAMP_NOTES"
    penv=$(python3 "$REPO/lib/profile.py" shell git --profile "$prof" --modules "$REPO/modules") || exit 3
    eval "$penv"
    cd "$REPO/modules/git"
    source ./module.sh
    "module_$op"
  )
}

# 0. Omitted optional keys are left untouched
P_MIN="$T_TMP/profile-min"
mkdir -p "$P_MIN"
cat > "$P_MIN/profile.toml" <<'EOF'
[git]
name = "Min Name"
EOF
git config --global init.defaultBranch "trunk"
git config --global push.autoSetupRemote "false"
run_mod add 0 "$P_MIN"
assert_eq "$(git config --global --get init.defaultBranch)" "trunk" "omitted default-branch untouched"
assert_eq "$(git config --global --get push.autoSetupRemote)" "false" "omitted auto-setup-remote untouched"
run_mod remove 0 "$P_MIN"
git config --global --unset init.defaultBranch
git config --global --unset push.autoSetupRemote

# 0b. Before add: status is not-installed, and --dry-run touches nothing
assert_eq "$(run_mod status)" "not-installed" "status before add reports not-installed"
run_mod add 1
assert_eq "$(git config --global --get user.name)" "Old Name" "dry-run add leaves user.name untouched"
assert_nofile "$DECAL_USER_STATE/git.prev" "dry-run add does not create git.prev"
assert_nofile "$XDG_CONFIG_HOME/git/ignore" "dry-run add does not create ignore"

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

git config --global core.editor "ed"
assert_contains "$(run_mod status)" "core.editor" "status catches core.editor mismatch"
git config --global core.editor "nano"

git config --global pull.rebase "false"
assert_contains "$(run_mod status)" "pull.rebase" "status catches pull.rebase mismatch"
git config --global pull.rebase "true"

printf 'tampered\n' > "$XDG_CONFIG_HOME/git/ignore"
assert_contains "$(run_mod status)" "ignores" "status catches ignores mismatch"
rm -f "$XDG_CONFIG_HOME/git/ignore"
run_mod add

# 3. Test stamp
stamp_out=$(run_mod stamp)
assert_contains "$stamp_out" '[git]' "stamp prints [git]"
assert_contains "$stamp_out" 'name = "New Name"' "stamp prints name"
assert_contains "$stamp_out" 'email = "dev@example.com"' "stamp prints email"
assert_contains "$stamp_out" 'default-branch = "main"' "stamp prints default-branch"
assert_contains "$stamp_out" '[git.aliases]' "stamp prints [git.aliases]"
assert_contains "$stamp_out" 'co = "checkout"' "stamp prints alias co"
assert_contains "$stamp_out" 'st = "status -sb"' "stamp prints alias st"
assert_contains "$stamp_out" 'ignores = [".DS_Store", "*.swp"]' "stamp prints ignores"

git config --global user.name 'Quote "User"\x'
stamp_q=$(run_mod stamp)
python3 -c 'import sys, tomllib; d = tomllib.loads(sys.argv[1]); assert d["git"]["name"] == "Quote \"User\"\\x"' "$stamp_q"
assert_eq "$?" "0" "stamp output with quotes/backslashes is valid TOML"
git config --global user.name "New Name"

# 3b. Dry-run remove leaves everything untouched
run_mod remove 1
assert_eq "$(git config --global --get user.name)" "New Name" "dry-run remove leaves user.name"
assert_file "$DECAL_USER_STATE/git.prev" "dry-run remove leaves git.prev"
assert_file "$XDG_CONFIG_HOME/git/ignore" "dry-run remove leaves ignore"

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

# 5. Symlinked git ignore preserved
printf '*.log\n' > "$T_TMP/dot-ignore"
ln -s "$T_TMP/dot-ignore" "$XDG_CONFIG_HOME/git/ignore"
run_mod add
assert_eq "$(test -L "$XDG_CONFIG_HOME/git/ignore" && echo yes || echo no)" "yes" "ignore symlink preserved on add"
assert_contains "$(cat "$T_TMP/dot-ignore")" "*.log" "symlink target retains existing entries"
assert_contains "$(cat "$T_TMP/dot-ignore")" ".DS_Store" "symlink target receives decal entries"
run_mod remove
assert_eq "$(test -L "$XDG_CONFIG_HOME/git/ignore" && echo yes || echo no)" "yes" "ignore symlink preserved on remove"
assert_contains "$(cat "$T_TMP/dot-ignore")" "*.log" "symlink target retains user entry after remove"
assert_not_contains "$(cat "$T_TMP/dot-ignore")" ".DS_Store" "symlink target removes decal entry"

# 6. Rejects newlines in git config values or ignores
P_NL="$T_TMP/profile-nl"
mkdir -p "$P_NL"
cat > "$P_NL/profile.toml" <<'EOF'
[git]
ignores = ["*.a\n*.b"]
EOF
bad_rc=0
run_mod add 0 "$P_NL" >/dev/null 2>&1 || bad_rc=$?
assert_eq "$(( bad_rc != 0 ))" "1" "newline in ignores rejected"

t_done
