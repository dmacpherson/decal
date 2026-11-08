#!/usr/bin/env bash
# decal: restart Ollama after Homebrew upgraded it. brew deletes the old version's folder, and a server still running
# from it can no longer start models (it looks for llama-server next to itself). Started by decal-ollama-upgrade.path.
# Usage: restart-after-upgrade.sh STABLE_BIN WATCHED_DIR UNIT
bin=$1 dir=$2 unit=$3 proc=${DECAL_PROC:-/proc} poll=${DECAL_OLLAMA_POLL:-5}
# wait (up to ~10 minutes) for the upgrade to finish: no half-done *.upgrading folder, and the link points at a program
for ((i = 0; i < 120; i++)); do
  if ! compgen -G "$dir/*.upgrading" >/dev/null && [[ -x $(readlink -f "$bin") ]]; then break; fi
  sleep "$poll"
done
sleep "${DECAL_OLLAMA_SETTLE:-10}"   # let brew finish relinking
pid=$(systemctl --user show -p MainPID --value "$unit" 2>/dev/null)
[[ -n $pid && $pid != 0 ]] || exit 0   # not running: its next start is the new version anyway
running=$(readlink "$proc/$pid/exe") new=$(readlink -f "$bin")
[[ $running == "$new" ]] && exit 0      # already running the installed version
echo "Ollama was upgraded (running ${running:-?}, installed $new): restarting $unit"
systemctl --user restart "$unit"
