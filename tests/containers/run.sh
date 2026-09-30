#!/usr/bin/env bash
set -o pipefail
# Real add/status/remove of the plymouth module on each distro family.
repo="$(cd "$(dirname "$0")/../.." && pwd)"; rc=0
for img in registry.fedoraproject.org/fedora:44 docker.io/library/debian:stable docker.io/library/ubuntu:latest docker.io/library/archlinux:latest; do
  echo "=== $img"
  podman run --rm -v "$repo:/repo:ro,Z" "$img" bash /repo/tests/containers/plymouth-e2e.sh 2>&1 || rc=1
  podman run --rm -v "$repo:/repo:ro,Z" "$img" bash /repo/tests/containers/hooks-e2e.sh 2>&1 || rc=1
  podman run --rm -v "$repo:/repo:ro,Z" "$img" bash /repo/tests/containers/uninstall-e2e.sh 2>&1 || rc=1
done
exit $rc
