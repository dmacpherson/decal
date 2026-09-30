#!/usr/bin/env python3
"""palette.py COLORS.palette FORMAT: convert a Ptyxis-format palette for other terminals.
FORMAT: kitty | alacritty | foot | wezterm | ghostty"""
import configparser, sys
cp = configparser.RawConfigParser(); cp.optionxform = str; cp.read(sys.argv[1]); p = cp["Palette"]
bg, fg = p["Background"], p["Foreground"]; cur = p.get("Cursor", fg)
c = [p[f"Color{i}"] for i in range(16)]
names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
fmt = sys.argv[2]
if fmt == "kitty":
    print(f"background {bg}\nforeground {fg}\ncursor {cur}")
    for i, v in enumerate(c): print(f"color{i} {v}")
elif fmt == "ghostty":
    print(f"background = {bg}\nforeground = {fg}\ncursor-color = {cur}")
    for i, v in enumerate(c): print(f"palette = {i}={v}")
elif fmt == "foot":
    h = lambda v: v.lstrip("#").lower()
    print(f"[colors]\nbackground={h(bg)}\nforeground={h(fg)}\ncursor={h(bg)} {h(cur)}")
    for i in range(8): print(f"regular{i}={h(c[i])}")
    for i in range(8): print(f"bright{i}={h(c[i + 8])}")
elif fmt == "alacritty":
    print(f'[colors.primary]\nbackground = "{bg}"\nforeground = "{fg}"\n\n[colors.cursor]\ncursor = "{cur}"\ntext = "{bg}"\n\n[colors.normal]')
    for n, v in zip(names, c[:8]): print(f'{n} = "{v}"')
    print("\n[colors.bright]")
    for n, v in zip(names, c[8:]): print(f'{n} = "{v}"')
elif fmt == "wezterm":
    q = lambda l: "[" + ", ".join(f'"{v}"' for v in l) + "]"
    print(f'[colors]\nbackground = "{bg}"\nforeground = "{fg}"\ncursor_bg = "{cur}"\ncursor_border = "{cur}"\nansi = {q(c[:8])}\nbrights = {q(c[8:])}\n\n[metadata]\nname = "decal"')
else:
    sys.exit(f"unknown format: {fmt}")
