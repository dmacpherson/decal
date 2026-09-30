#!/usr/bin/env bash
# build.sh IMAGE BLUR BRIGHTNESS MONITORS_JSON STOCK OUT : build the custom GDM gresource.
set -euo pipefail
image=$1 blur=$2 bright=$3 mons=$4 stock=$5 out=$6
here="$(cd "$(dirname "$0")" && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
python3 "$here/extract.py" "$stock" "$w/src"
cp "$image" "$w/orig"
{
  # shellcheck disable=SC2016  # written into inner.sh, expanded when it runs
  echo 'set -euo pipefail; cd "$(dirname "$0")"'
  echo "magick orig -resize 1920x -blur 0x$blur -fill black -colorize $((100 - bright))% one.png"
  python3 - "$mons" <<'EOF'
import json, sys
c = json.loads(sys.argv[1])
parts = [f"magick -respect-parentheses -size {c['width']}x{c['height']} xc:black"]
for x, y, rw, rh in c["rects"]:
    parts.append(f"\\( one.png -resize {rw}x{rh}^ -gravity center -extent {rw}x{rh} \\) -gravity northwest -geometry +{x}+{y} -composite")
parts.append("-quality 90 src/decal-background.jpg")
print(" ".join(parts))
EOF
  echo 'cd src && glib-compile-resources --target=../out.gresource gnome-shell-theme.gresource.xml'
} > "$w/inner.sh"
bash "$here/run-image-job.sh" "$w"
cp "$w/out.gresource" "$out"
cp "$w/src/decal-background.jpg" "${out%.gresource}.preview.jpg"
