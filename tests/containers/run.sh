#!/usr/bin/env bash
set -o pipefail
# Real add/status/remove of the plymouth module, transaction hooks and package removal on each distro family.
# Images this run had to pull are removed at the end (--keep-images keeps them for faster re-runs).
repo="$(cd "$(dirname "$0")/../.." && pwd)"; rc=0; keep=0
[[ ${1:-} == --keep-images ]] && keep=1
imgs=(registry.fedoraproject.org/fedora:44 docker.io/library/debian:stable docker.io/library/ubuntu:latest docker.io/library/archlinux:latest)
pulled=()
for img in "${imgs[@]}"; do podman image exists "$img" || pulled+=("$img"); done
for img in "${imgs[@]}"; do
  echo "=== $img"
  podman run --rm -v "$repo:/repo:ro,z" "$img" bash /repo/tests/containers/plymouth-e2e.sh 2>&1 || rc=1
  podman run --rm -v "$repo:/repo:ro,z" "$img" bash /repo/tests/containers/hooks-e2e.sh 2>&1 || rc=1
  podman run --rm -v "$repo:/repo:ro,z" "$img" bash /repo/tests/containers/uninstall-e2e.sh 2>&1 || rc=1
done
if (( ! keep && ${#pulled[@]} )); then
  echo "=== removing the images this run pulled (${#pulled[@]})"
  podman rmi "${pulled[@]}" >/dev/null 2>&1 || true
fi
exit $rc
