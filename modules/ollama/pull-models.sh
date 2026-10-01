#!/usr/bin/env bash
# Background job of the ollama module (systemd-run --user --unit=decal-ollama-models): downloads models one at a
# time, so decal itself doesn't wait for tens of GB. Usage: pull-models.sh OLLAMA MODEL...
# Follow it: journalctl --user -u decal-ollama-models -f. If it fails, decal's next run starts it again.
set -u
ollama=$1; shift
# the service may still be starting (just installed or enabled)
for _ in $(seq "${DECAL_OLLAMA_WAIT:-300}"); do "$ollama" list >/dev/null 2>&1 && break; sleep 1; done
"$ollama" list >/dev/null 2>&1 || { echo "Ollama is not answering; decal tries again on its next run"; exit 1; }
rc=0
for m in "$@"; do
  echo "downloading $m"
  # pull draws progress bars: keep them out of the journal, keep the last line for a failure
  if out=$("$ollama" pull "$m" < /dev/null 2>&1); then echo "done: $m"
  else echo "failed: $m: $(tr '\r' '\n' <<<"$out" | grep -v '^[[:space:]]*$' | tail -1)"; rc=1; fi
done
exit $rc
