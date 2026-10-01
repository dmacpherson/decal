#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora; B="$T_TMP/brew"; mkdir -p "$B/bin"
UNIT="$XDG_CONFIG_HOME/systemd/user/decal-ollama.service"
# fake Homebrew: installing the cask puts an `ollama` (that logs its calls) in the stable bin/ link folder
stub brew 'case "$1" in --prefix) echo "'"$B"'";;
  install) printf "#!/bin/sh\necho \"ollama \$*\" >> \"$STUBS/calls\"\n[ \"\$1\" = list ] && cat \"$STUBS/models\" 2>/dev/null\nexit 0\n" > "'"$B"'/bin/ollama"; chmod +x "'"$B"'/bin/ollama";;
  uninstall) rm -f "'"$B"'/bin/ollama";; esac; exit 0'
# the background model download job counts as running while $STUBS/pulling exists
stub systemctl 'case "$*" in *is-active*decal-ollama-models*) [ -e "$STUBS/pulling" ]; exit;; *is-active*decal-ollama*) exit 0;; *is-active*) exit 3;; esac'
stub systemd-run; stub curl 'exit 7'
printf '[ollama]\nmodels = ["llama3.2"]\n' >> "$PROFILE_DIR/profile.toml"
run_mod() { mod_run ollama "module_$1"; }
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add rc"
assert_contains "$(calls)" "brew install --cask ollama-binary" "GPU build (Homebrew cask) installed"
assert_contains "$(cat "$UNIT")" "ExecStart=$B/bin/ollama serve" "service runs Homebrew's stable ollama link (survives upgrades)"
assert_contains "$(calls)" "systemctl --user enable --now decal-ollama.service" "service enabled for the user"
assert_contains "$(calls)" "systemd-run --user --unit=decal-ollama-models" "models download in the background (add doesn't wait)"
assert_contains "$(calls)" "pull-models.sh $B/bin/ollama llama3.2" "the missing model handed to the job"
assert_not_contains "$(calls)" "ollama pull" "nothing downloaded in the foreground"
# while the job runs: not started twice, and status says so; once it's gone with the model still missing: retried
touch "$STUBS/pulling"; : > "$STUBS/calls"; out=$(run_mod add 2>&1)
assert_not_contains "$(calls)" "systemd-run" "job still running: not started twice"
assert_contains "$out" "still downloading" "says it is still downloading"
assert_eq "$(run_mod status 2>/dev/null)" "partial (downloading llama3.2)" "status while downloading"
rm -f "$STUBS/pulling"
assert_eq "$(run_mod status 2>/dev/null)" "partial (missing llama3.2)" "status when the download stopped short"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "pull-models.sh $B/bin/ollama llama3.2" "next run starts it again"
# idempotent: present model not pulled again, nothing reinstalled
echo "llama3.2:latest  a80c4f17acd5  2.0 GB  1 minute ago" > "$STUBS/models"; : > "$STUBS/calls"
run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "brew install" "already installed: not reinstalled"
assert_not_contains "$(calls)" "systemd-run" "model already there: no download job"
assert_eq "$(run_mod status 2>/dev/null)" "installed" "status"
# remove: service and program go, downloaded models stay (they can be tens of GB)
mkdir -p "$HOME/.ollama/models"; echo m > "$HOME/.ollama/models/x"; : > "$STUBS/calls"
touch "$STUBS/pulling"; out=$(run_mod remove 2>&1); rm -f "$STUBS/pulling"
assert_contains "$(calls)" "systemctl --user stop decal-ollama-models" "a running download stopped"
assert_contains "$(calls)" "systemctl --user disable --now decal-ollama.service" "service stopped"
assert_nofile "$UNIT" "unit removed"
assert_contains "$(calls)" "brew uninstall --cask ollama-binary" "ollama uninstalled"
assert_file "$HOME/.ollama/models/x" "models kept"
assert_contains "$out" ".ollama" "says where the models are and how to delete them"
# an ollama that was already there (installed some other way) is used as is and never uninstalled
printf '#!/bin/sh\necho "ollama $*" >> "%s/calls"\n' "$STUBS" > "$B/bin/ollama"; chmod +x "$B/bin/ollama"; export PATH="$B/bin:$PATH"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_not_contains "$(calls)" "brew install" "existing ollama: not installed again"
assert_not_contains "$(calls)" "brew uninstall" "existing ollama: never uninstalled"
# gpu = false: the CPU-only formula
rm -f "$B/bin/ollama"; export PATH="${PATH#"$B/bin:"}"; sed -i 's/^models = \["llama3.2"\]$/&\ngpu = false/' "$PROFILE_DIR/profile.toml"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "brew install ollama" "gpu = false: CPU-only formula"
# the background job itself: waits for the server, downloads one model at a time, keeps going past a failure
J="$REPO/modules/ollama/pull-models.sh"; F="$T_TMP/fake-ollama"
printf '#!/bin/sh\necho "ollama $*" >> "%s/calls"\n[ "$1 $2" = "pull bad" ] && { echo "Error: pull model manifest: file does not exist"; exit 1; }\nexit 0\n' "$STUBS" > "$F"; chmod +x "$F"
: > "$STUBS/calls"; out=$(bash "$J" "$F" llama3.2 bad qwen3 2>&1); rc=$?
assert_contains "$(calls)" "ollama pull llama3.2" "job downloads the first model"
assert_contains "$(calls)" "ollama pull qwen3" "and keeps going after a failure"
assert_contains "$out" "failed: bad: Error: pull model manifest" "says which model failed and why"
assert_eq "$rc" "1" "job fails when a model failed (decal starts it again next run)"
printf '#!/bin/sh\nexit 1\n' > "$F"; out=$(DECAL_OLLAMA_WAIT=1 bash "$J" "$F" llama3.2 2>&1); rc=$?
assert_eq "$rc" "1" "server never answers: job fails"; assert_contains "$out" "not answering" "and says so"
t_done
