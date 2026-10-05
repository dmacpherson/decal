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
# a second upgrade of a hand-made stick whose Decal-old/ is already taken: a free name, never a stranded stick
O2="$T_TMP/o2"; mkdir -p "$O2/Decal" "$O2/Decal-old"; echo x > "$O2/decal-me"; echo s > "$O2/Decal/decal-me.sh"; echo again > "$O2/Decal/more.txt"; echo first > "$O2/Decal-old/notes.txt"
out=$(python3 "$U" write "$O2" "$SRC" 2>&1); assert_eq "$?" "0" "upgrade with Decal-old taken: works"
assert_eq "$(cat "$O2/Decal")" "launcher" "...the launcher in place"; assert_eq "$(cat "$O2/Decal-old/notes.txt")" "first" "...the earlier Decal-old untouched"
assert_eq "$(cat "$O2/Decal-old-2/more.txt")" "again" "...the new leftovers in Decal-old-2"; assert_nofile "$O2/decal-me" "...the old launcher gone"
# a folder target
python3 "$U" write "$T_TMP/folder" "$SRC" >/dev/null; assert_file "$T_TMP/folder/.Decal/stick.conf" "folder: written"
# a stick that can't be written (read-only, full, pulled out): a plain message, no traceback (audit batch 3)
RO="$T_TMP/ro"; mkdir -p "$RO"; chmod a-w "$RO"
out=$(python3 "$U" write "$RO" "$SRC" 2>&1); assert_eq "$?" "1" "unwritable stick: fails"
assert_contains "$out" "couldn't write to $RO" "...says where"; assert_contains "$out" "full, read-only or unplugged" "...and what to check"
assert_not_contains "$out" "Traceback" "...without a traceback"; chmod u+w "$RO"
# no udisksctl on this PC: say how to go on instead of a traceback
mkdir -p "$T_TMP/py"; ln -sf "$(command -v python3)" "$T_TMP/py/python3"
out=$(PATH="$T_TMP/py" python3 "$U" mount /dev/sdc1 2>&1); assert_eq "$?" "1" "no udisksctl: fails"
assert_contains "$out" "mount the stick, then use --to with its folder" "...says how to go on"; assert_not_contains "$out" "Traceback" "...without a traceback"
# stick.conf is written here (decal usb gives the answers), and read back the same
SC="$T_TMP/scw/.Decal"; mkdir -p "$SC"
python3 "$U" conf-text --profile github:me/p --key saved --decal newest --version v0.4.0 > "$SC/stick.conf"
assert_eq "$(python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import usb; print(usb.read_conf('$SC'))")" "{'profile': 'github:me/p', 'key': 'saved', 'decal': 'newest', 'version': 'v0.4.0'}" "conf-text: read back the same"
assert_contains "$(head -1 "$SC/stick.conf")" "# Made by decal v0.4.0" "...with its header"
out=$(python3 "$U" conf-text --profile $'x\nkey=saved' --key none --decal copy --version v 2>&1); assert_eq "$?" "1" "conf-text: a value with a new line refused"
# a case-sensitive stick with both decal/ and Decal/: Decal/ is the one moved aside, decal/ left alone (review)
CS="$T_TMP/cs"; mkdir -p "$CS/decal" "$CS/Decal"; echo mine > "$CS/decal/f"; echo old > "$CS/Decal/g"
out=$(python3 "$U" write "$CS" "$SRC" 2>&1); assert_eq "$?" "0" "both decal/ and Decal/: written"
assert_eq "$(cat "$CS/decal/f")" "mine" "...decal/ untouched"; assert_file "$CS/Decal-old/g" "...Decal/ kept as Decal-old"
t_done
