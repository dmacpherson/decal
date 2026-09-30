#!/usr/bin/env bash
# run-image-job.sh DIR : run DIR/inner.sh with ImageMagick + glib-compile-resources,
# in a Fedora container when podman/docker exists, otherwise on the host.
set -euo pipefail
w=$1
if eng=$(command -v podman || command -v docker); then
  "$eng" run --rm -v "$w:/w:Z" registry.fedoraproject.org/fedora:latest \
    bash -c 'dnf -qy install ImageMagick glib2-devel >/dev/null 2>&1 && bash /w/inner.sh'
elif command -v magick >/dev/null && command -v glib-compile-resources >/dev/null; then
  bash "$w/inner.sh"
else
  echo "need podman/docker, or ImageMagick 7 + glib-compile-resources (glib2-devel / libglib2.0-dev-bin)" >&2; exit 1
fi
