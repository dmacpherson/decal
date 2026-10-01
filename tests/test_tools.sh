#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora
# fake Astral installer: puts uv/uvx (which log their calls) in ~/.local/bin and writes the receipt
cat > "$T_TMP/uv-install.sh" <<EOS
echo "installer UV_NO_MODIFY_PATH=\${UV_NO_MODIFY_PATH:-}" >> "$STUBS/calls"
mkdir -p "\$HOME/.local/bin" "\$XDG_CONFIG_HOME/uv"
for b in uv uvx; do printf '#!/bin/sh\necho "%s \$*" >> "%s"\n' "\$b" "$STUBS/calls" > "\$HOME/.local/bin/\$b"; chmod +x "\$HOME/.local/bin/\$b"; done
echo '{}' > "\$XDG_CONFIG_HOME/uv/uv-receipt.json"
EOS
mod_run_pre() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"; [[ $1 == https://astral.sh/uv/install.sh ]] && echo "$T_TMP/uv-install.sh"; }; }
export PATH="$HOME/.local/bin:$PATH"
run_mod() { mod_run tools "module_$1"; }
printf '[tools]\ninstall = ["uv"]\n' >> "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "add rc"
assert_contains "$(calls)" "ls_fetch https://astral.sh/uv/install.sh" "Astral's installer fetched"
assert_contains "$(calls)" "installer UV_NO_MODIFY_PATH=1" "installer never edits shell startup files"
assert_file "$HOME/.local/bin/uvx" "uv and uvx installed"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "astral.sh" "already installed: not reinstalled"
assert_contains "$(calls)" "uv self update" "kept current with its own updater"
assert_eq "$(run_mod status 2>/dev/null)" "installed" "status"
# remove: decal's binaries and receipt go, your Pythons/tools/cache stay
mkdir -p "$XDG_DATA_HOME/uv/python" "$XDG_CACHE_HOME/uv"
out=$(run_mod remove 2>&1)
assert_nofile "$HOME/.local/bin/uv" "uv removed"; assert_nofile "$HOME/.local/bin/uvx" "uvx removed"
assert_nofile "$XDG_CONFIG_HOME/uv/uv-receipt.json" "receipt removed"
assert_file "$XDG_DATA_HOME/uv/python" "installed Pythons kept"; assert_file "$XDG_CACHE_HOME/uv" "cache kept"
assert_contains "$out" "uv cache clean" "says how to delete the data"
# a uv you installed yourself is updated but never removed
for b in uv uvx; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$b" "$STUBS/calls" > "$HOME/.local/bin/$b"; chmod +x "$HOME/.local/bin/$b"; done
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_not_contains "$(calls)" "astral.sh" "existing uv: not installed again"
assert_file "$HOME/.local/bin/uv" "existing uv: never removed"
# unknown tool: clear error listing what decal knows
sed -i 's/^install = \["uv"\]$/install = ["nope"]/' "$PROFILE_DIR/profile.toml"
out=$(run_mod add 2>&1); assert_eq "$?" "1" "unknown tool rc"
assert_contains "$out" "known: uv" "unknown tool: lists the known ones"
t_done
