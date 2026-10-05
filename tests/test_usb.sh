#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
U="$REPO/lib/usb.py"; MED="$T_TMP/media"; mkdir -p "$MED/Ventoy/ventoy" "$MED/KINGSTON"; : > "$MED/Ventoy/a.iso"; : > "$MED/Ventoy/b.iso"
cat > "$T_TMP/lsblk.json" <<EOF
{"blockdevices": [
 {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk", "rm": false, "hotplug": false, "tran": "nvme", "size": 2000000000000,
  "children": [{"name": "nvme0n1p1", "path": "/dev/nvme0n1p1", "type": "part", "fstype": "vfat", "label": null, "mountpoint": "/boot/efi", "size": 600000000}]},
 {"name": "sda", "path": "/dev/sda", "type": "disk", "rm": true, "hotplug": true, "tran": "usb", "size": 62000000000,
  "children": [{"name": "sda1", "path": "/dev/sda1", "type": "part", "fstype": "exfat", "label": "Ventoy", "mountpoint": "$MED/Ventoy", "size": 61900000000},
               {"name": "sda2", "path": "/dev/sda2", "type": "part", "fstype": "vfat", "label": "VTOYEFI", "mountpoint": null, "size": 33554432}]},
 {"name": "sdb", "path": "/dev/sdb", "type": "disk", "rm": true, "hotplug": true, "tran": "usb", "size": 16000000000,
  "children": [{"name": "sdb1", "path": "/dev/sdb1", "type": "part", "fstype": "vfat", "label": "KINGSTON", "mountpoint": "$MED/KINGSTON", "size": 16000000000}]},
 {"name": "sdc", "path": "/dev/sdc", "type": "disk", "rm": false, "hotplug": true, "tran": "usb", "size": 8000000000,
  "children": [{"name": "sdc1", "path": "/dev/sdc1", "type": "part", "fstype": "vfat", "label": "SPARE", "mountpoint": null, "size": 8000000000}]}
]}
EOF
export DECAL_LSBLK="$T_TMP/lsblk.json"
J=$(python3 "$U" drives --json)
q() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($1)" "$J"; }
assert_eq "$(q "[x['label'] for x in d]")" "['Ventoy', 'KINGSTON', 'SPARE']" "drives: USB only, Ventoy first, VTOYEFI and internal disks left out"
assert_eq "$(q "(d[0]['ventoy'], d[0]['isos'])")" "(True, 2)" "drives: Ventoy recognised, ISOs counted"
assert_eq "$(q "d[2]['mount']")" "" "drives: an unmounted one listed, no mount point"
stub udisksctl 'echo "Mounted /dev/sdc1 at /run/media/me/SPARE"'
assert_eq "$(python3 "$U" mount /dev/sdc1)" "/run/media/me/SPARE" "mount: the mount point from udisksctl"
assert_contains "$(calls)" "udisksctl mount -b /dev/sdc1 --no-user-interaction" "mount: no prompts, no sudo"

# writing: a new stick; everything outside Decal and .Decal/ untouched
SRC="$T_TMP/src"; mkdir -p "$SRC/.Decal"; echo launcher > "$SRC/Decal"; echo 'profile=github:me/p' > "$SRC/.Decal/stick.conf"; echo s > "$SRC/.Decal/start.sh"
before=$(cd "$MED/Ventoy" && find . -path ./.Decal -prune -o -path ./Decal -prune -o -type f -print | sort | xargs sha256sum)
assert_eq "$(python3 "$U" write "$MED/Ventoy" "$SRC")" "written" "write: a new stick"
assert_eq "$(cat "$MED/Ventoy/Decal")" "launcher" "...the launcher at the root"
assert_eq "$(python3 "$U" conf "$MED/Ventoy")" '{"profile": "github:me/p"}' "...stick.conf readable"
after=$(cd "$MED/Ventoy" && find . -path ./.Decal -prune -o -path ./Decal -prune -o -type f -print | sort | xargs sha256sum)
assert_eq "$after" "$before" "...nothing else on the drive changed"
assert_nofile "$MED/Ventoy/.Decal.new" "...no leftovers"; assert_nofile "$MED/Ventoy/.Decal.old" "...no leftovers"
# updating: the old setup is replaced whole
echo 'profile=copy' > "$SRC/.Decal/stick.conf"; echo stale > "$MED/Ventoy/.Decal/stale"
python3 "$U" write "$MED/Ventoy" "$SRC" >/dev/null; assert_nofile "$MED/Ventoy/.Decal/stale" "update: replaced whole"
# interrupted: a failure after .Decal.new leaves the old .Decal working
echo 'profile=github:me/kept' > "$MED/Ventoy/.Decal/stick.conf"
out=$(DECAL_USB_FAIL_AFTER_NEW=1 python3 "$U" write "$MED/Ventoy" "$SRC" 2>&1); assert_eq "$?" "1" "interrupted write: fails"
assert_eq "$(cat "$MED/Ventoy/.Decal/stick.conf")" "profile=github:me/kept" "...the old setup still there and whole"
# the hand-made stick: upgraded; its token removed only after the new setup is in place; other files kept
OLD="$MED/KINGSTON"; echo x > "$OLD/decal-me"; mkdir -p "$OLD/Decal"; echo s > "$OLD/Decal/decal-me.sh"; echo T0KEN > "$OLD/Decal/decal-token.txt"; echo mine > "$OLD/Decal/notes.txt"
python3 "$U" old "$OLD"; assert_eq "$?" "0" "old layout recognised"
assert_eq "$(python3 "$U" write "$OLD" "$SRC")" "upgraded" "upgrade: says so"
assert_eq "$(cat "$OLD/Decal")" "launcher" "upgrade: Decal is the launcher now"
assert_nofile "$OLD/decal-me" "upgrade: the old launcher gone"; assert_eq "$(grep -rl T0KEN "$OLD" | wc -l)" "0" "upgrade: the old token gone"
assert_eq "$(cat "$OLD/Decal-old/notes.txt")" "mine" "upgrade: your own files kept, in Decal-old"
# a folder target
python3 "$U" write "$T_TMP/folder" "$SRC" >/dev/null; assert_file "$T_TMP/folder/.Decal/stick.conf" "folder: written"
t_done
