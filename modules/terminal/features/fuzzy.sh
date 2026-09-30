# fzf: Ctrl-T files, Alt-C cd into folder. Loaded before carapace so carapace's completions win.
if command -v fzf >/dev/null; then eval "$(fzf --bash)"; fi
