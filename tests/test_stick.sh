#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
ST="$T_TMP/stick"; mkdir -p "$ST/.Decal"; cp "$REPO/usb/start.sh" "$ST/.Decal/"
stub decal 'echo "decal $* KEY=${GITHUB_TOKEN:-} STICK=${DECAL_STICK:-}" >> "$STUBS/calls"; [ -e "$STUBS/use-fails" ] && case " $* " in *" use "*) exit 1;; esac; exit 0'
export DECAL_CMD="$STUBS/decal" DECAL_STICK_IN_TERM=1 DECAL_INSTALL_URL=https://example.invalid/install
conf() { printf '%s\n' "# test" "$@" > "$ST/.Decal/stick.conf"; }
copy() {  # a decal copy whose install.sh just logs
  mkdir -p "$T_TMP/c/decal"; printf '#!/usr/bin/env bash\necho "copy-install $DECAL_ARCHIVE_VERSION" >> "%s"\n' "$STUBS/calls" > "$T_TMP/c/decal/install.sh"
  tar -czf "$ST/.Decal/decal.tar.gz" -C "$T_TMP/c" decal; (cd "$ST/.Decal" && sha256sum decal.tar.gz > decal.tar.gz.sha256); }
S() { : > "$STUBS/calls"; bash "$ST/.Decal/start.sh" < /dev/null 2>&1; }

# newest: online works → the online installer, then the profile, then the menu
stub curl 'echo "echo online-install >> $STUBS/calls"'
conf profile=github:me/prof key=saved decal=newest version=v0.4.0; echo "  k3y  " > "$ST/.Decal/key"; copy
out=$(S); assert_eq "$?" "0" "newest, online: ok"
assert_contains "$(calls)" "online-install" "the online installer ran"; assert_contains "$(grep ^curl "$STUBS/calls")" "--proto =https --proto-redir =https" "...fetched https only"; assert_not_contains "$(calls)" "copy-install" "...not the copy"
assert_contains "$(calls)" "decal --no-update --yes use github:me/prof KEY=k3y" "the profile with the saved key (spaces trimmed)"
assert_contains "$(calls)" "decal --no-update ui KEY=k3y STICK=$ST/.Decal" "the menu in stick mode"
# newest: offline → the copy, with the message
stub curl 'exit 7'
out=$(S); assert_contains "$out" "Couldn't check for a newer decal: using the copy on this stick (v0.4.0)" "offline: says so"
assert_contains "$(calls)" "copy-install v0.4.0" "...installs the copy"
# copy only: never online
stub curl 'echo "echo online-install >> $STUBS/calls"'; conf profile=github:me/prof key=ask decal=copy version=v0.4.0
out=$(S); assert_not_contains "$(calls)" "online-install" "copy: no download"; assert_contains "$(calls)" "copy-install" "copy: from the stick"
assert_contains "$(calls)" "decal --no-update --yes use github:me/prof KEY= " "ask: no key (decal signs in itself)"
# a borrowed PC's own keys never reach the stick's decal (only the stick's key, when it has one)
stub curl 'exit 7'; conf profile=github:me/prof key=ask decal=copy version=v0.4.0; copy
out=$(GITHUB_TOKEN=pc-key GH_TOKEN=pc-gh S); assert_contains "$(calls)" "decal --no-update --yes use github:me/prof KEY= " "the PC's GITHUB_TOKEN/GH_TOKEN dropped"
# online only, offline → the message; damaged copy → refused
stub curl 'exit 7'; conf profile=github:me/prof key=ask decal=online
out=$(S); assert_eq "$?" "1" "online only, offline: fails"; assert_contains "$out" "No internet, and this stick has no copy of decal" "...says what to do"
conf profile=github:me/prof key=ask decal=copy; echo tampered >> "$ST/.Decal/decal.tar.gz"
out=$(S); assert_eq "$?" "1" "damaged copy: refused"; assert_contains "$out" "The decal copy on this stick is damaged" "...says so"
assert_not_contains "$(calls)" "copy-install" "...and doesn't run it"
# the profile copy on the stick: packed and used (lives on the machine afterwards)
copy; mkdir -p "$ST/.Decal/profile"; echo '[apps]' > "$ST/.Decal/profile/profile.toml"; conf profile=copy key=none decal=copy
out=$(S); assert_contains "$(calls)" "decal --no-update --yes use $XDG_CACHE_HOME/decal/stick-profile.tar.gz" "copy: packed to one stable place"
A="$XDG_CONFIG_HOME/decal/profile"; mkdir -p "$A"; cp "$ST/.Decal/profile/profile.toml" "$A/"; echo "$XDG_CACHE_HOME/decal/stick-profile.tar.gz" > "$A/.decal-source"
out=$(S); assert_not_contains "$(calls)" " use " "the same profile already here: not used again (no pile of backups)"
assert_contains "$out" "already here" "...says so"
echo '[wallpaper]' >> "$ST/.Decal/profile/profile.toml"
out=$(S); assert_contains "$(calls)" "decal --no-update --yes use $XDG_CACHE_HOME/decal/stick-profile.tar.gz" "a changed profile on the stick: used (decal keeps a backup)"
rm -rf "$A"
# a saved key that no longer works
conf profile=github:me/prof key=saved decal=copy; : > "$STUBS/use-fails"
out=$(S); assert_eq "$?" "1" "a dead key: fails"; assert_contains "$out" "The key on this stick no longer works" "...says what to do"
rm "$STUBS/use-fails"
# started outside a terminal: reopens in one
conf profile=github:me/prof key=ask decal=copy; stub ptyxis
: > "$STUBS/calls"; env -u DECAL_STICK_IN_TERM bash "$ST/.Decal/start.sh" < /dev/null >/dev/null 2>&1
assert_contains "$(calls)" "ptyxis -- bash $ST/.Decal/start.sh" "not in a terminal: opens one"
# no stick.conf
rm "$ST/.Decal/stick.conf"; out=$(S); assert_contains "$out" "run decal usb to set it up again" "no stick.conf: says so"

# the launcher (built here when a C compiler is available; the release builds it static)
if command -v cc >/dev/null; then
  cc -O2 -o "$T_TMP/Decal" "$REPO/usb/launch.c" 2>/dev/null
  L="$T_TMP/lst"; mkdir -p "$L/.Decal"; cp "$T_TMP/Decal" "$L/Decal"; printf 'echo "ran $0" > %s/out\n' "$T_TMP" > "$L/.Decal/start.sh"
  (cd / && "$L/Decal"); assert_eq "$(cat "$T_TMP/out")" "ran $L/.Decal/start.sh" "launcher: runs .Decal/start.sh from any folder"
  cp "$T_TMP/Decal" "$L/.Decal/Decal-ARM"; rm "$T_TMP/out"; (cd / && "$L/.Decal/Decal-ARM")
  assert_eq "$(cat "$T_TMP/out")" "ran $L/.Decal/start.sh" "launcher inside .Decal (ARM): the start.sh next to it"
  rm "$L/.Decal/start.sh"; : > "$L/.Decal/README.txt"; stub xdg-open; : > "$STUBS/calls"; "$L/Decal"
  assert_contains "$(calls)" "xdg-open $L/.Decal/README.txt" "launcher: no start.sh → the README"
else
  echo "  (no C compiler: launcher not tested here; the release workflow builds and checks it)"
fi
assert_contains "$(cat "$REPO/usb/README.txt")" "{profile}" "README template has the profile placeholder"
t_done
