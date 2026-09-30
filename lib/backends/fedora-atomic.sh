# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
# Fedora Atomic (rpm-ostree). /usr is read-only: files are wrapped in a local RPM and layered.
# shellcheck source=/dev/null
source "$LS_REPO/lib/backends/fedora.sh"   # PKG_MAP
txn_hooks_add() { return 0; }   # rpm-ostree writes a new tree; the running /usr is never modified

_ostree_json() { rpm-ostree status --json; }
_requested() {   # requested package names of deployment 0 (pending if any, else booted)
  _ostree_json | python3 -c '
import json,sys
d=json.load(sys.stdin)["deployments"][0]
for p in d.get("requested-packages",[]): print(p)
for p in d.get("requested-local-packages",[]): print(p.rsplit("-",2)[0] if p.count("-")>=2 else p)'
}
_requested_nevra() { _ostree_json | python3 -c '
import json,sys
for p in json.load(sys.stdin)["deployments"][0].get("requested-local-packages",[]): print(p)'; }
_pending_root() { _ostree_json | python3 -c '
import json,sys
d=json.load(sys.stdin)["deployments"][0]
if not d.get("booted"): print("/ostree/deploy/%s/deploy/%s.%s" % (d["osname"], d["checksum"], d["serial"]))'; }
_initramfs_enabled() { _ostree_json | python3 -c '
import json,sys; sys.exit(0 if json.load(sys.stdin)["deployments"][0].get("regenerate-initramfs") else 1)'; }

_pkg_present() {   # check the pending deployment if there is one
  local r; r=$(_pending_root)
  if [[ -n $r && -d $r/usr/share/rpm ]]; then rpm -q --quiet --dbpath "$r/usr/share/rpm" "$1"; else rpm -q --quiet "$1"; fi
}
# a staged deployment: reboot needed, and (while regeneration is on) its initramfs was rebuilt from the current /etc
_staged() { need_reboot; if [[ $LS_DRY_RUN != 1 ]] && _initramfs_enabled; then _initramfs_clean; fi; }
# regeneration off, or with other dracut args than wanted: needs an rpm-ostree initramfs call
_initramfs_stale() {
  _initramfs_enabled || return 0
  local want have; want=$(_prior_lines | tail -n +2 | paste -sd' ')
  have=$(_ostree_json | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["deployments"][0].get("initramfs-args", [])))')
  [[ $want != "$have" ]]
}
_pkg_add() { srun rpm-ostree install --allow-inactive "$@"; _staged; }
_pkg_del() { srun rpm-ostree uninstall "$@"; _staged; }

_tree_hash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum) | sha256sum | cut -c1-12; }
_container_engine() { if have podman; then echo podman; elif have docker; then echo docker; else die "podman or docker is required to build RPMs on Fedora Atomic"; fi; }
_rpm_build() {   # NAME HASH SRC DEST OUTDIR
  local name=$1 hash=$2 src=$3 dest=$4 out=$5 eng w
  eng=$(_container_engine)
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] build $name-1.0-$hash.noarch.rpm in a $eng container -> $out"; return 0; fi
  w=$(mktemp -d); mkdir -p "$w/SOURCES/payload" "$w/SPECS" "$out"
  cp -a "$src/." "$w/SOURCES/payload/"
  cat > "$w/SPECS/$name.spec" <<EOF
Name:      $name
Version:   1.0
Release:   $hash
Summary:   decal payload for $dest
License:   See payload
BuildArch: noarch
$(for r in ${FILES_REQUIRES:-}; do printf 'Requires:  %s\n' "$r"; done)
%description
Files installed by decal into $dest.
%install
mkdir -p %{buildroot}$dest
cp -a %{_sourcedir}/payload/. %{buildroot}$dest/
%files
$dest
EOF
  log "building $name in a $eng container"
  # the build is chatty: keep its output, show it only when it fails
  if ! "$eng" run --rm -v "$w:/root/rpmbuild:Z" registry.fedoraproject.org/fedora:latest \
       bash -c "dnf -qy install rpm-build && rpmbuild -bb /root/rpmbuild/SPECS/$name.spec" > "$w/build.log" 2>&1; then
    tail -n 20 "$w/build.log" >&2; rm -rf "$w"; die "RPM build failed for $name (container output above)"
  fi
  cp "$w"/RPMS/noarch/"$name"-1.0-"$hash".noarch.rpm "$out/" 2>/dev/null || [[ -e $out/$name-1.0-$hash.noarch.rpm ]] || { rm -rf "$w"; die "RPM build failed: no $name RPM produced"; }
  rm -rf "$w"
}

files_install() {
  local owner=$1 src=$2 dest=$3 name="decal-$1" hash rpmdir rpm args=() old req
  hash=$(_tree_hash "$src")
  # declared dependencies (FILES_REQUIRES) are part of the package: a change means a new build
  if [[ -n ${FILES_REQUIRES:-} ]]; then hash=$(printf '%s %s' "$hash" "$FILES_REQUIRES" | sha256sum | cut -c1-12); fi
  rpmdir="${DECAL_RPM_DIR:-$HOME/.local/share/decal/rpms}"
  rpm="$rpmdir/$name-1.0-$hash.noarch.rpm"
  if grep -qx "$name-1.0-$hash.noarch" <<<"$(_requested_nevra)"; then
    printf '%s\n' "$name" | swrite "$LS_STATE/files/$owner.rpm"; return 0
  fi
  [[ -e $rpm ]] || _rpm_build "$name" "$hash" "$src" "$dest" "$rpmdir"
  req=$(_requested)
  for old in "$name" ${FILES_REPLACES:-}; do grep -qx "$old" <<<"$req" && args+=("--uninstall=$old"); done
  srun rpm-ostree install "${args[@]}" "$rpm"
  _staged
  printf '%s\n' "$name" | swrite "$LS_STATE/files/$owner.rpm"
  # rpm-ostree keeps its own copy: older builds of this package are just clutter
  if [[ $LS_DRY_RUN != 1 ]]; then find "$rpmdir" -maxdepth 1 -name "$name-1.0-*.noarch.rpm" ! -name "${rpm##*/}" -delete 2>/dev/null || true; fi
}
files_remove() {
  local f="$LS_STATE/files/$1.rpm" name
  [[ -r $f ]] || return 0
  name=$(cat "$f")
  if grep -qx "$name" <<<"$(_requested)"; then srun rpm-ostree uninstall "$name"; _staged; fi
  srun rm -f "$f"
}
files_installed() { [[ -r $LS_STATE/files/$1.rpm ]] && grep -qx "decal-$1" <<<"$(_requested)"; }

# Local initramfs regeneration: enabled while any marker exists.
# Re-running --enable when already enabled regenerates with the current /etc
# (verified in Task 14; if rpm-ostree rejects it, fall back to disable+enable).
# Pre-tool state, recorded once: line 1 = regeneration enabled (1/0), then one dracut arg per line.
_PRIOR="$LS_STATE/initramfs.prior"
_prior_now() { _ostree_json | python3 -c '
import json,sys; d=json.load(sys.stdin)["deployments"][0]
print(1 if d.get("regenerate-initramfs") else 0)
for a in d.get("initramfs-args",[]): print(a)'; }
_prior_lines() { if [[ -r $_PRIOR ]]; then cat "$_PRIOR"; else _prior_now; fi; }   # dry-run: file not written yet
_initramfs_prior_record() {
  [[ -e $_PRIOR ]] && return 0
  [[ -n $(find "$LS_STATE/initramfs" -type f 2>/dev/null) ]] && return 0   # already managing: keep the original record
  _prior_now | swrite "$_PRIOR"
}
_initramfs_seed_prior() { [[ -e $_PRIOR ]] && return 0; if [[ $1 == enabled ]]; then echo 1; else echo 0; fi | swrite "$_PRIOR"; }

_initramfs_rebuild() {   # ACTION(require|release) OWNER — intent is passed so --dry-run (no markers written) plans correctly
  local action=${1:-require} owner=${2:-} n=0 args=() a
  while IFS= read -r a; do [[ -n $a ]] && args+=("--arg=$a"); done < <(_prior_lines | tail -n +2)
  [[ -d $LS_STATE/initramfs ]] && n=$(find "$LS_STATE/initramfs" -type f ! -name "$owner" | wc -l)
  if [[ $action == require ]] || (( n > 0 )); then
    # --enable refuses when already enabled: then disable + enable, which regenerates with the current /etc
    if _initramfs_enabled; then srun rpm-ostree initramfs --disable; fi
    srun rpm-ostree initramfs --enable "${args[@]}"
  else
    # last user gone: back to how it was before this tool
    if [[ $(_prior_lines | head -1) == 1 ]]; then srun rpm-ostree initramfs --enable "${args[@]}"
    elif _initramfs_enabled; then srun rpm-ostree initramfs --disable; fi
    if [[ -e $_PRIOR ]]; then srun rm -f "$_PRIOR"; fi
  fi
}

# base-image packages are hidden with an override; layered ones are uninstalled
_pkg_del_check() { return 0; }   # rpm-ostree refuses by itself if something depends on the package
_pkg_uninstall_names() {
  local req n base=() layered=(); req=$(_requested)
  for n in "$@"; do if grep -qx "$n" <<<"$req"; then layered+=("$n"); else base+=("$n"); fi; done
  if (( ${#base[@]} )); then srun rpm-ostree override remove "${base[@]}" >&2 || return 1; _staged; fi
  if (( ${#layered[@]} )); then srun rpm-ostree uninstall "${layered[@]}" >&2 || return 1; _staged; fi
  for n in "${base[@]}"; do echo "base:$n"; done
  for n in "${layered[@]}"; do echo "layer:$n"; done
}
_pkg_restore_names() {
  local t base=() layered=()
  for t in "$@"; do case $t in base:*) base+=("${t#base:}") ;; layer:*) layered+=("${t#layer:}") ;; *) layered+=("$t") ;; esac; done
  if (( ${#base[@]} )); then srun rpm-ostree override reset "${base[@]}"; _staged; fi
  if (( ${#layered[@]} )); then srun rpm-ostree install --allow-inactive "${layered[@]}"; _staged; fi
}
