# decal v0.5.1

## Fixed

- **Ollama keeps working after Homebrew upgrades it.** A background `brew upgrade` (Bazzite's uupd or decal's daily
  timer) deletes the old Ollama version's folder. The server still running from it could then no longer start any
  model (it looks for `llama-server` next to itself), so every request failed until the service was restarted.
  - A user path unit, `decal-ollama-upgrade.path`, watches Homebrew's folder for Ollama (Caskroom for the GPU build,
    Cellar for the CPU build).
  - Its service waits for the upgrade to finish, then restarts `decal-ollama` only when the running server isn't the
    installed version.
  - Only set up for an Ollama decal installed. `decal status ollama` reports `no restart after upgrades` until
    `decal add ollama` sets it up; `decal remove ollama` takes it away.
