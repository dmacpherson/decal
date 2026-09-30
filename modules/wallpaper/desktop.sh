#!/usr/bin/env bash
# desktop.sh IMAGE BLUR BRIGHTNESS OUT : blur (sigma at 1920 px wide) and darken one image, keeping its size.
set -euo pipefail
in=$1 blur=$2 bright=$3 out=$4
here="$(cd "$(dirname "$0")" && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cp "$in" "$w/in"
{
  # shellcheck disable=SC2016  # written into inner.sh, expanded when it runs
  echo 'set -euo pipefail; cd "$(dirname "$0")"; W=$(magick identify -format %w in)'
  if (( blur > 0 )); then
    # shellcheck disable=SC2016
    echo "magick in -resize 1920x -blur 0x$blur -resize \"\${W}x\" -fill black -colorize $((100 - bright))% -quality 92 out.jpg"
  else
    echo "magick in -fill black -colorize $((100 - bright))% -quality 92 out.jpg"
  fi
} > "$w/inner.sh"
bash "$here/run-image-job.sh" "$w"
cp "$w/out.jpg" "$out"
