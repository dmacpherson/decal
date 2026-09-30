# Starship prompt
if command -v starship >/dev/null; then
    export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/decal/terminal/starship.toml"
    eval "$(starship init bash)"
fi
