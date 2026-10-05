#!/usr/bin/env bash
# pages-site.sh MAIN_INSTALL DEV_INSTALL OUT REPO : the GitHub Pages site. /install (and /install.sh) is the stable
# installer from main; /dev/install (and /dev/install.sh) is the dev branch's, defaulting to the dev channel.
set -euo pipefail
main=$1 dev=$2 out=$3 repo=$4
mkdir -p "$out/dev"
cp "$main" "$out/install"; cp "$main" "$out/install.sh"
# shellcheck disable=SC2016  # written into the installer as is
{ sed -n 1p "$dev"; echo 'DECAL_VERSION=${DECAL_VERSION:-dev}   # the dev installer: the dev channel unless told otherwise'; sed 1d "$dev"; } > "$out/dev/install"
cp "$out/dev/install" "$out/dev/install.sh"
printf '<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=https://github.com/%s"><title>decal</title><a href="https://github.com/%s">decal</a>\n' "$repo" "$repo" > "$out/index.html"
