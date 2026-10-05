#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
G="$DECAL_ROOT/etc/group"; mkdir -p "$DECAL_ROOT/etc"; printf 'wheel:x:10:me\n' > "$G"
stub rpm 'exit 1'; stub dnf; stub systemctl; stub usermod; stub gpasswd; stub groupadd; stub groupdel; stub apt-cache 'exit 1'
# the real machine may already have Docker: never let it decide the test (no docker-compose, not in the group)
stub id 'case "$1" in -un) echo tester;; -nG) echo "tester wheel";; *) /usr/bin/id "$@";; esac'
hide_compose() { have() { [[ $1 == docker-compose ]] && return 1; command -v "$1" >/dev/null 2>&1; }; }
mod_run_pre() { hide_compose; }
run_mod() { mod_run docker "module_$1"; }
# Fedora (mutable): packages, socket enabled, docker-compose command, user in the docker group
stub getent 'echo "docker:x:975:"'; printf 'docker:x:975:\n' >> "$G"
out=$(DECAL_PLATFORM=fedora run_mod add 2>&1); assert_eq "$?" "0" "add rc"
assert_contains "$(calls)" "dnf install -y -- moby-engine docker-compose" "engine + compose installed"
assert_eq "$(readlink "$DECAL_ROOT/etc/systemd/system/sockets.target.wants/docker.socket")" "/usr/lib/systemd/system/docker.socket" "docker.socket enabled"
assert_contains "$(cat "$DECAL_ROOT/usr/local/bin/docker-compose")" 'exec docker compose "$@"' "docker-compose command"
assert_contains "$(calls)" "usermod -aG docker tester" "user added to the docker group"
assert_contains "$out" "log out" "says the group needs a new login"
# remove undoes exactly that
: > "$STUBS/calls"; stub rpm 'exit 0'; DECAL_PLATFORM=fedora run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "gpasswd -d tester docker" "user taken out of the group"
assert_nofile "$DECAL_ROOT/etc/systemd/system/sockets.target.wants/docker.socket" "socket link removed"
assert_nofile "$DECAL_ROOT/usr/local/bin/docker-compose" "docker-compose command removed"
assert_contains "$(calls)" "dnf remove" "packages removed"
assert_not_contains "$(calls)" "groupdel" "a group decal didn't add is left alone"
# Fedora Atomic: the group is in the new image's /usr/lib/group, which usermod can't change: copied into /etc/group
printf 'wheel:x:10:me\n' > "$G"; stub rpm 'exit 1'; stub getent 'exit 2'; stub rpm-ostree; : > "$STUBS/calls"
mkdir -p "$T_TMP/pending/usr/lib"; printf 'docker:x:981:\n' > "$T_TMP/pending/usr/lib/group"
mod_run_pre() { hide_compose; _pending_root() { echo "$T_TMP/pending"; }; _initramfs_enabled() { return 1; }; }
out=$(DECAL_PLATFORM=fedora-atomic run_mod add 2>&1); assert_eq "$?" "0" "atomic add rc"
assert_contains "$(calls)" "rpm-ostree install --allow-inactive -- moby-engine docker-compose" "atomic: layered"
assert_contains "$(calls)" "groupadd -g 981 docker" "atomic: group created in /etc/group with the image's id (groupadd, never by rewriting the file)"
assert_contains "$(calls)" "usermod -aG docker tester" "atomic: user added"
: > "$STUBS/calls"; DECAL_PLATFORM=fedora-atomic run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "groupdel docker" "atomic: the group decal added is removed again"
assert_eq "$(cat "$G")" "wheel:x:10:me" "/etc/group itself never rewritten by decal"
mod_run_pre() { hide_compose; }
# group = false: Docker without the root-equivalent group
printf 'wheel:x:10:me\ndocker:x:975:\n' > "$G"; stub getent 'echo "docker:x:975:"'; : > "$STUBS/calls"
printf '[docker]\ngroup = false\n' >> "$PROFILE_DIR/profile.toml"
DECAL_PLATFORM=fedora run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "usermod" "group = false: user not added"
t_done
