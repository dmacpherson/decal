#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"
osr() { mkdir -p "$DECAL_ROOT/etc"; printf '%s\n' "$@" > "$DECAL_ROOT/etc/os-release"; }
osr 'ID=fedora';                        assert_eq "$(platform_detect)" fedora "fedora"
osr 'ID=bazzite' 'ID_LIKE="fedora"';    assert_eq "$(platform_detect)" fedora "bazzite mutable view"
mkdir -p "$DECAL_ROOT/run"; : > "$DECAL_ROOT/run/ostree-booted"
assert_eq "$(platform_detect)" fedora-atomic "atomic"
osr 'ID=steamos' 'ID_LIKE=arch';        assert_eq "$(platform_detect)" unsupported "non-fedora atomic"
rm "$DECAL_ROOT/run/ostree-booted"
osr 'ID=ubuntu' 'ID_LIKE=debian';       assert_eq "$(platform_detect)" debian "ubuntu"
osr 'ID=debian';                        assert_eq "$(platform_detect)" debian "debian"
osr 'ID=arch';                          assert_eq "$(platform_detect)" arch "arch"
osr 'ID=endeavouros' 'ID_LIKE=arch';    assert_eq "$(platform_detect)" arch "arch-like"
osr 'ID=nixos';                         assert_eq "$(platform_detect)" unsupported "nixos"
out=$( (platform_load) 2>&1 ); assert_contains "$out" "unsupported platform" "load dies"
DECAL_PLATFORM=debian; assert_eq "$(platform_detect)" debian "override"
t_done
