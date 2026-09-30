# terminal module

Bash + Starship prompt + Nerd Font + eza/bat/fzf/zoxide/atuin/carapace + ble.sh,
with a Ptyxis colour palette. Your settings live in your profile's `[terminal]`
(see `examples/profile/profile.toml`). Every `[terminal.features]` switch maps to
one file in `features/`; your own layouts and themes can go in
`<profile>/terminal/layouts/` and `<profile>/terminal/themes/`, where they win over the presets here.

## Layouts and themes

The prompt is built at `add` time from two independent pieces:

    ~/.config/decal/terminal/starship.toml  =  palette = "theme"
                                                   + layouts/<LAYOUT>.toml
                                                   + themes/<THEME>/starship.toml

- **Layouts** (`layouts/*.toml`) define the prompt's shape and refer only to
  colour *roles*, never to hex values.
- **Themes** (`themes/<name>/`) define every role in `[palettes.theme]`, plus
  `colors.palette` (Ptyxis format) for the terminal's 16 colours; `palette.py` converts it for other terminals.

Any layout works with any theme, as long as the theme defines every role:

| Role | Used for |
|---|---|
| `accent` / `on_accent` | fade + first block / its text |
| `seg_dir` `seg_git` `seg_lang` `seg_time` | block backgrounds, left to right |
| `text` | directory text |
| `dim` | time text |
| `info` | git branch, success `❯` |
| `warn` | git changes, command duration |
| `error` | error `❯` |
| `lang` | language/version text |

To add a theme, copy `themes/cyberpunk/` and change the hex values. To add a
layout, copy `layouts/tokyo-sharp.toml` and keep to the roles above.
`./decal status terminal` fails if the selected theme is missing a role that
the selected layout uses.

Nerd Font icons are private-use Unicode characters. Some editors and tools strip
them silently, so check `grep -c` on the file after editing, or write them as
escapes when generating files.
