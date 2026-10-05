#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
cat > "$T_TMP/claude-install.sh" <<'EOS'
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions"; echo bin > "$HOME/.local/share/claude/versions/9.9"
ln -sf "$HOME/.local/share/claude/versions/9.9" "$HOME/.local/bin/claude"
EOS
echo "fake key" > "$T_TMP/key.asc"
# downloads are faked: the installer script, Anthropic's apt signing key
fake_fetch() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"
  case $1 in https://claude.ai/install.sh) echo "$T_TMP/claude-install.sh";; *key.asc) echo "$T_TMP/key.asc";; *) return 1;; esac; }; }
mod_run_pre() { fake_fetch; }
run_mod() { mod_run claude "module_$1"; }
prof() { python3 - "$PROFILE_DIR/profile.toml" "$1" <<'EOP'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[claude\]\n.*?(?=^\[|\Z)","",s); open(p,"w").write(s.rstrip("\n")+"\n\n[claude]\n"+sys.argv[2].replace(";","\n")+"\n")
EOP
}
stub gpg "echo 'fpr:::::::::$FPR:'"; stub dpkg 'echo amd64'; stub dpkg-query 'case "$*" in *Package*) echo base-files;; *) exit 1;; esac'; stub apt-get; stub usermod; stub gpasswd
mkdir -p "$HOME/.claude"; echo mine > "$HOME/.claude/settings.json"

# cli: Anthropic's installer when claude is missing; remove takes only what decal installed, never ~/.claude
prof 'cli = true'; export DECAL_PLATFORM=fedora
run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "cli add rc"
assert_contains "$(calls)" "ls_fetch https://claude.ai/install.sh" "Anthropic's installer fetched"
assert_file "$HOME/.local/bin/claude" "claude installed"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1; assert_not_contains "$(calls)" "claude.ai/install.sh" "already installed: not reinstalled"
prof 'cli = false'; run_mod add >/dev/null 2>&1
assert_nofile "$HOME/.local/bin/claude" "cli off: the claude decal installed is removed"
assert_nofile "$HOME/.local/share/claude" "with its versions"
assert_eq "$(cat "$HOME/.claude/settings.json")" "mine" "~/.claude (settings, memory, history) never touched"
mkdir -p "$HOME/.local/bin"; echo own > "$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"
prof 'cli = true'; : > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "claude.ai/install.sh" "an existing claude is used as is"
run_mod remove >/dev/null 2>&1; assert_eq "$(cat "$HOME/.local/bin/claude")" "own" "an existing claude is never removed"

# desktop: not available on Fedora (Linux beta is Debian/Ubuntu only): skipped with a note, nothing installed
prof 'cli = false;desktop = true'; : > "$STUBS/calls"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "desktop on fedora: rc 0"
assert_contains "$out" "Debian and Ubuntu only" "desktop on fedora: says why it's skipped"
assert_not_contains "$(calls)" "apt-get" "desktop on fedora: nothing installed"

# desktop on Debian/Ubuntu: Anthropic's apt repository (key checked against its fingerprint), then the package
export DECAL_PLATFORM=debian; : > "$STUBS/calls"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "desktop on debian rc"
assert_contains "$(calls)" "ls_fetch https://downloads.claude.ai/claude-desktop/key.asc" "signing key downloaded"
assert_eq "$(cat "$DECAL_ROOT/usr/share/keyrings/claude-desktop-archive-keyring.asc")" "fake key" "key installed"
assert_contains "$(cat "$DECAL_ROOT/etc/apt/sources.list.d/claude-desktop.list")" "signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" "repository registered"
assert_contains "$(calls)" "apt-get install -y -- claude-desktop" "claude-desktop installed"
assert_contains "$(calls)" "usermod -aG kvm" "cowork (default): you join the kvm group"
# a key with another fingerprint is refused before anything is registered
rm -rf "$DECAL_ROOT/etc/apt" "$DECAL_ROOT/usr/share/keyrings" "$DECAL_STATE"; stub gpg "echo 'fpr:::::::::0000000000000000000000000000000000000000:'"
out=$(run_mod add 2>&1); assert_eq "$?" "1" "wrong key rc"
assert_contains "$out" "fingerprint" "wrong key: says so"
assert_nofile "$DECAL_ROOT/etc/apt/sources.list.d/claude-desktop.list" "wrong key: nothing registered"
stub gpg "echo 'fpr:::::::::$FPR:'"; run_mod add >/dev/null 2>&1
# remove: package, repository, key and group membership undone
: > "$STUBS/calls"; stub dpkg-query 'case "$*" in *Package*) echo base-files;; *) echo "install ok installed";; esac'; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "claude-desktop" "package removed"
assert_nofile "$DECAL_ROOT/etc/apt/sources.list.d/claude-desktop.list" "repository removed"
assert_nofile "$DECAL_ROOT/usr/share/keyrings/claude-desktop-archive-keyring.asc" "key removed"
assert_contains "$(calls)" "gpasswd -d" "left the kvm group"
# cowork = false: no kvm group
rm -rf "$DECAL_STATE"; stub dpkg-query 'case "$*" in *Package*) echo base-files;; *) exit 1;; esac'; prof 'desktop = true;cowork = false'; : > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "usermod" "cowork = false: not added to kvm"
t_done
