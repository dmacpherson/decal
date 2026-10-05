#!/usr/bin/env python3
"""usb.py: USB drives for decal usb, and writing a decal stick safely.

  usb.py drives [--json]     removable/USB filesystems: mounted ones, and ones udisksctl can mount
  usb.py mount DEVICE        mount it (udisksctl, no sudo); prints the mount point
  usb.py conf TARGET         a stick's stick.conf as JSON ({} when there's none)
  usb.py old TARGET          exit 0 when TARGET has the hand-made layout (decal-me, Decal/decal-me.sh)
  usb.py write TARGET SRC    put SRC's Decal and .Decal/ on TARGET: .Decal.new first, then swapped in, so a stick
                             pulled out midway has the old setup or the new one; upgrades the hand-made layout

DECAL_LSBLK: a JSON file used instead of running lsblk (tests)."""
import argparse, glob, json, os, shutil, subprocess, sys

FS = {"vfat", "exfat", "ntfs", "ntfs3", "ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs"}
OLD_FILES = ["decal-me", os.path.join("Decal", "decal-me.sh"), os.path.join("Decal", "decal-token.txt"),
             os.path.join("Decal", "decal-me.desktop")]


def lsblk():
    f = os.environ.get("DECAL_LSBLK")
    if f:
        return json.load(open(f))
    r = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,MOUNTPOINT,RM,HOTPLUG,TRAN,SIZE,FSTYPE,TYPE"],
                       capture_output=True, text=True)
    return json.loads(r.stdout or '{"blockdevices": []}')


def old_layout(t):
    return os.path.exists(os.path.join(t, "decal-me")) and os.path.exists(os.path.join(t, "Decal", "decal-me.sh"))


def drives():
    out = []
    for disk in lsblk().get("blockdevices", []):
        if disk.get("type") != "disk" or not (disk.get("tran") == "usb" or disk.get("rm") or disk.get("hotplug")):
            continue
        for part in disk.get("children") or [disk]:
            if part.get("fstype") not in FS or part.get("label") == "VTOYEFI":
                continue
            mp = part.get("mountpoint") or ""
            d = {"device": part["path"], "label": part.get("label") or os.path.basename(mp) or part["name"],
                 "mount": mp, "size": int(part.get("size") or 0), "fstype": part["fstype"]}
            if mp:
                d.update(ventoy=d["label"] == "Ventoy" or os.path.isdir(os.path.join(mp, "ventoy")),
                         isos=len(glob.glob(os.path.join(mp, "*.iso"))),
                         decal=os.path.exists(os.path.join(mp, ".Decal", "stick.conf")), old=old_layout(mp))
            out.append(d)
    out.sort(key=lambda d: (not d.get("ventoy"), d["label"].lower()))
    return out


def mount(device):
    try:
        r = subprocess.run(["udisksctl", "mount", "-b", device, "--no-user-interaction"], capture_output=True, text=True)
    except FileNotFoundError:
        sys.exit(f"error: can't mount {device} here (no udisksctl): mount the stick, then use --to with its folder")
    if r.returncode != 0 or " at " not in r.stdout:
        sys.exit(f"error: couldn't mount {device}: {(r.stderr or r.stdout).strip()}")
    return r.stdout.strip().split(" at ", 1)[1].rstrip(".")


def read_conf(dot_decal):
    """A stick's .Decal/stick.conf as a dict ({} when there's none); DOT_DECAL is the .Decal folder."""
    out = {}
    try:
        for line in open(os.path.join(dot_decal, "stick.conf")):
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def _copytree(src, dst):   # FAT/exFAT keep no modes or owners: plain copies
    shutil.copytree(src, dst, copy_function=shutil.copyfile)


def write(target, src):
    os.makedirs(target, exist_ok=True)
    new, cur, old = (os.path.join(target, n) for n in (".Decal.new", ".Decal", ".Decal.old"))
    for p in (new, old):
        shutil.rmtree(p, ignore_errors=True)
    _copytree(os.path.join(src, ".Decal"), new)
    os.sync()
    if os.environ.get("DECAL_USB_FAIL_AFTER_NEW"):   # tests: a stick pulled out here
        sys.exit("error: interrupted")
    if os.path.exists(cur):
        os.rename(cur, old)
    os.rename(new, cur)
    os.sync()
    shutil.rmtree(old, ignore_errors=True)
    how = "upgraded" if old_layout(target) else "written"
    d = os.path.join(target, "Decal")
    if how == "upgraded":   # the hand-made stick: its files inside Decal/ go now the new setup is in place
        for f in OLD_FILES[1:]:
            try:
                os.remove(os.path.join(target, f))
            except FileNotFoundError:
                pass
    if os.path.isdir(d):   # a Decal folder can't share the launcher's name (FAT/exFAT ignore case, too)
        if os.listdir(d):
            keep, n = os.path.join(target, "Decal-old"), 1
            while os.path.exists(keep):   # never onto an earlier one
                n += 1
                keep = os.path.join(target, f"Decal-old-{n}")
            os.rename(d, keep)
        else:
            os.rmdir(d)
    tmp = os.path.join(target, "Decal.new")
    shutil.copyfile(os.path.join(src, "Decal"), tmp)
    try:
        os.chmod(tmp, 0o755)
    except OSError:
        pass
    os.replace(tmp, d)
    if how == "upgraded":   # the old launcher last: the stick always has one
        try:
            os.remove(os.path.join(target, OLD_FILES[0]))
        except FileNotFoundError:
            pass
    os.sync()
    return how


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["drives", "mount", "conf", "old", "write"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if a.cmd == "drives":
        ds = drives()
        print(json.dumps(ds) if a.json else "\n".join(f"{d['device']}\t{d['label']}\t{d['mount']}" for d in ds))
    elif a.cmd == "mount":
        print(mount(a.args[0]))
    elif a.cmd == "conf":
        print(json.dumps(read_conf(os.path.join(a.args[0], ".Decal"))))
    elif a.cmd == "old":
        sys.exit(0 if old_layout(a.args[0]) else 1)
    else:
        try:
            print(write(a.args[0], a.args[1]))
        except Exception as e:   # OSError and shutil.Error alike: plain words, never a traceback
            why = getattr(e, "strerror", None) or str(e) or type(e).__name__
            sys.exit(f"error: couldn't write to {a.args[0]}: {why} (is the stick full, read-only or unplugged?)")


if __name__ == "__main__":
    main()
