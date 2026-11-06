#!/usr/bin/env python3
"""lib/review.py: inspect a profile and evaluate trust signals before applying."""

import argparse
import ipaddress
import json
import os
import re
import stat
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request

KNOWN_HOSTS = {
    "github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "api.github.com",
    "gitlab.com",
    "codeberg.org",
    "gnome-look.org",
    "pling.com",
    "dl.flathub.org",
    "flathub.org",
    "extensions.gnome.org",
    "astral.sh",
    "launchpad.net",
    "archive.ubuntu.com",
    "deb.debian.org",
    "fedoraproject.org",
    "archlinux.org",
}

SHORTENERS = {
    "bit.ly",
    "tinyurl.com",
    "t.co",
    "is.gd",
    "buff.ly",
    "ow.ly",
    "goo.gl",
}

SCRIPT_EXTS = {".sh", ".bash", ".py", ".bin", ".elf", ".exe"}
LARGE_FILE_BYTES = 10 * 1024 * 1024  # 10 MB


def detect_gnome_version():
    try:
        out = subprocess.check_output(
            ["gnome-shell", "--version"], stderr=subprocess.DEVNULL, text=True
        )
        m = re.search(r"(\d+)", out)
        if m:
            return m.group(1)
    except Exception:
        pass
    return None


def fetch_json(url, timeout=2.0):
    req = urllib.request.Request(url, headers={"User-Agent": "decal-review"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 404
        return None
    except Exception:
        return None
    return None


def inspect_profile(profile_dir, shell_version=None, offline=False):
    profile_toml = os.path.join(profile_dir, "profile.toml")
    data = {}
    if os.path.isfile(profile_toml):
        try:
            with open(profile_toml, "rb") as f:
                data = tomllib.load(f)
        except Exception as e:
            return {"error": f"Failed to read profile.toml: {e}"}

    results = {
        "flatpaks": [],
        "gnome_extensions": [],
        "homebrew": [],
        "native_packages": {
            "install": [],
            "remove": [],
        },
        "remote_urls": [],
        "files": [],
        "total_items": 0,
        "total_flags": 0,
    }

    # 1. Flatpaks
    apps_sec = data.get("apps", {})
    flatpaks = apps_sec.get("flatpaks", [])
    if isinstance(flatpaks, list):
        for fp in flatpaks:
            if not isinstance(fp, str):
                continue
            item = {
                "id": fp,
                "name": fp,
                "verified": None,
                "installs": None,
                "flags": [],
            }
            if not offline:
                summary = fetch_json(f"https://flathub.org/api/v2/summary/{fp}")
                if summary == 404:
                    item["flags"].append("unlisted on Flathub")
                elif isinstance(summary, dict):
                    item["name"] = summary.get("name", fp)
                    ver = fetch_json(f"https://flathub.org/api/v2/verification/{fp}/status")
                    if isinstance(ver, dict):
                        item["verified"] = ver.get("verified", False)
                        if not item["verified"]:
                            item["flags"].append("unverified publisher")
                    stats = fetch_json(f"https://flathub.org/api/v2/stats/{fp}")
                    if isinstance(stats, dict):
                        item["installs"] = stats.get("installs_total", 0)
                        if item["installs"] < 100:
                            item["flags"].append(f"few installs ({item['installs']})")
                else:
                    item["note"] = "check unavailable"
            results["flatpaks"].append(item)

    # 2. GNOME Extensions
    ge_sec = data.get("gnome-extensions", {})
    ge_enable = ge_sec.get("enable", [])
    if isinstance(ge_enable, list):
        for ext in ge_enable:
            if not isinstance(ext, str):
                continue
            item = {
                "uuid": ext,
                "name": ext,
                "downloads": None,
                "compatible": None,
                "flags": [],
            }
            if not offline:
                encoded = urllib.parse.quote(ext, safe="@")
                info = fetch_json(f"https://extensions.gnome.org/extension-info/?uuid={encoded}")
                if info == 404:
                    item["flags"].append("not on extensions.gnome.org")
                elif isinstance(info, dict):
                    item["name"] = info.get("name", ext)
                    item["downloads"] = info.get("downloads", 0)
                    if item["downloads"] < 100:
                        item["flags"].append(f"few downloads ({item['downloads']})")
                    ver_map = info.get("shell_version_map", {})
                    if shell_version:
                        if str(shell_version) in ver_map:
                            item["compatible"] = True
                        else:
                            item["compatible"] = False
                            item["flags"].append(f"not updated for GNOME {shell_version}")
                else:
                    item["note"] = "check unavailable"
            results["gnome_extensions"].append(item)

    # 3. Homebrew formulas
    term_sec = data.get("terminal", {})
    brew = term_sec.get("brew", [])
    if isinstance(brew, list):
        for b in brew:
            if not isinstance(b, str):
                continue
            item = {"formula": b, "flags": []}
            if "/" in b:
                tap = b.rsplit("/", 1)[0]
                item["flags"].append(f"third-party tap ({tap})")
            results["homebrew"].append(item)

    # 4. Native packages
    # Installs: apps.packages, tools.install, vpn.install
    pkg_inst = []
    if isinstance(apps_sec.get("packages"), list):
        pkg_inst.extend(apps_sec["packages"])
    tools_sec = data.get("tools", {})
    if isinstance(tools_sec.get("install"), list):
        pkg_inst.extend(tools_sec["install"])
    vpn_sec = data.get("vpn", {})
    if isinstance(vpn_sec.get("install"), list):
        pkg_inst.extend(vpn_sec["install"])
    for p in pkg_inst:
        if isinstance(p, str):
            results["native_packages"]["install"].append(p)

    # Removals: apps.remove-packages
    pkg_rem = apps_sec.get("remove-packages", [])
    if isinstance(pkg_rem, list):
        for p in pkg_rem:
            if isinstance(p, str):
                results["native_packages"]["remove"].append(p)

    # 5. Remote URLs
    def scan_for_urls(val):
        urls = []
        if isinstance(val, str):
            if val.startswith("http://") or val.startswith("https://"):
                urls.append(val)
        elif isinstance(val, list):
            for x in val:
                urls.extend(scan_for_urls(x))
        elif isinstance(val, dict):
            for x in val.values():
                urls.extend(scan_for_urls(x))
        return urls

    found_urls = scan_for_urls(data)
    for u in sorted(set(found_urls)):
        item = {"url": u, "flags": []}
        parsed = urllib.parse.urlparse(u)
        if parsed.scheme == "http":
            item["flags"].append("insecure http://")
        host = (parsed.hostname or "").lower()
        if host in SHORTENERS:
            item["flags"].append(f"URL shortener ({host})")
        else:
            try:
                ipaddress.ip_address(host)
                item["flags"].append(f"bare IP address ({host})")
            except ValueError:
                # Domain check
                domain_parts = host.split(".")
                root_domain = ".".join(domain_parts[-2:]) if len(domain_parts) >= 2 else host
                if host not in KNOWN_HOSTS and root_domain not in KNOWN_HOSTS:
                    item["flags"].append(f"unrecognized host ({host})")
        results["remote_urls"].append(item)

    # 6. Bundled files in profile directory
    ignored_names = {"profile.toml", "README", "README.md", "README.txt"}
    ignored_prefixes = {".git", ".decal-"}
    for root, dirs, files in os.walk(profile_dir):
        dirs[:] = [d for d in dirs if not any(d.startswith(p) for p in ignored_prefixes)]
        for f in sorted(files):
            if f in ignored_names or any(f.startswith(p) for p in ignored_prefixes):
                continue
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, profile_dir)
            try:
                st = os.stat(full_path)
            except OSError:
                continue

            size = st.st_size
            is_exec = bool(st.st_mode & 0o111)
            _, ext = os.path.splitext(f)
            is_script_ext = ext.lower() in SCRIPT_EXTS

            is_shebang = False
            if size > 0:
                try:
                    with open(full_path, "rb") as bf:
                        start_bytes = bf.read(2)
                        if start_bytes == b"#!":
                            is_shebang = True
                except Exception:
                    pass

            item = {
                "path": rel_path,
                "size": size,
                "flags": [],
            }
            if is_exec:
                item["flags"].append("executable")
            if is_shebang or is_script_ext:
                item["flags"].append("script/binary")
            if size > LARGE_FILE_BYTES:
                size_mb = size / (1024 * 1024)
                item["flags"].append(f"large file ({size_mb:.1f} MB)")

            results["files"].append(item)

    # Summary tallies
    total_items = (
        len(results["flatpaks"])
        + len(results["gnome_extensions"])
        + len(results["homebrew"])
        + len(results["native_packages"]["install"])
        + len(results["native_packages"]["remove"])
        + len(results["remote_urls"])
        + len(results["files"])
    )
    total_flags = 0
    for category in ("flatpaks", "gnome_extensions", "homebrew", "remote_urls", "files"):
        for it in results[category]:
            total_flags += len(it.get("flags", []))

    results["total_items"] = total_items
    results["total_flags"] = total_flags
    return results


def format_bytes(n):
    if n < 1024:
        return f"{n} B"
    elif n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    else:
        return f"{n / (1024 * 1024):.1f} MB"


def format_count(n):
    if n is None:
        return "unknown"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def print_review(results, profile_name="Profile"):
    print(f"\nProfile review: {profile_name} ({results['total_items']} items)")

    # Flatpaks
    if results["flatpaks"]:
        print("\nFlatpaks (Flathub):")
        for it in results["flatpaks"]:
            flags = it.get("flags", [])
            details = []
            if it.get("verified") is True:
                details.append("verified")
            elif it.get("verified") is False:
                details.append("unverified")
            if it.get("installs") is not None:
                details.append(f"{format_count(it['installs'])} installs")
            if it.get("note"):
                details.append(it["note"])
            det_str = f" ({' · '.join(details)})" if details else ""

            if flags:
                print(f"  ! {it['id']:<28} {it['name']}{det_str} [{' · '.join(flags)}]")
            else:
                print(f"  ✓ {it['id']:<28} {it['name']}{det_str}")

    # GNOME Extensions
    if results["gnome_extensions"]:
        print("\nGNOME extensions:")
        for it in results["gnome_extensions"]:
            flags = it.get("flags", [])
            details = []
            if it.get("downloads") is not None:
                details.append(f"{format_count(it['downloads'])} downloads")
            if it.get("compatible") is True:
                details.append("compatible")
            if it.get("note"):
                details.append(it["note"])
            det_str = f" ({' · '.join(details)})" if details else ""

            if flags:
                print(f"  ! {it['uuid']:<32} {it['name']}{det_str} [{' · '.join(flags)}]")
            else:
                print(f"  ✓ {it['uuid']:<32} {it['name']}{det_str}")

    # Homebrew
    if results["homebrew"]:
        print("\nHomebrew formulas:")
        for it in results["homebrew"]:
            flags = it.get("flags", [])
            if flags:
                print(f"  ! {it['formula']:<24} [{' · '.join(flags)}]")
            else:
                print(f"  ✓ {it['formula']:<24} (core formula)")

    # Native packages
    np = results["native_packages"]
    if np["install"] or np["remove"]:
        print("\nNative packages:")
        if np["install"]:
            print(f"  + install: {', '.join(np['install'])}")
        if np["remove"]:
            print(f"  - remove:  {', '.join(np['remove'])}")

    # Remote URLs
    if results["remote_urls"]:
        print("\nRemote downloads:")
        for it in results["remote_urls"]:
            flags = it.get("flags", [])
            if flags:
                print(f"  ! {it['url']} [{' · '.join(flags)}]")
            else:
                print(f"  ✓ {it['url']}")

    # Files
    if results["files"]:
        print("\nFiles in profile:")
        for it in results["files"]:
            flags = it.get("flags", [])
            size_str = format_bytes(it["size"])
            if flags:
                print(f"  ! {it['path']:<30} {size_str} [{' · '.join(flags)}]")
            else:
                print(f"  ✓ {it['path']:<30} {size_str}")

    # Summary
    flags = results["total_flags"]
    if flags == 0:
        print(f"\n✓ All {results['total_items']} items clean: no flags raised.\n")
    else:
        print(f"\n! Flags: {flags} warning{'s' if flags != 1 else ''} found across {results['total_items']} items.\n")


def main():
    parser = argparse.ArgumentParser(description="Inspect profile contents and trust signals.")
    parser.add_argument("profile_dir", help="Path to profile directory")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--shell-version", default=None, help="Target GNOME Shell major version")
    parser.add_argument("--offline", action="store_true", help="Skip remote API lookups")
    args = parser.parse_args()

    pdir = os.path.abspath(args.profile_dir)
    if not os.path.isdir(pdir):
        sys.stderr.write(f"decal: not a directory: {pdir}\n")
        sys.exit(1)

    shell_ver = args.shell_version or detect_gnome_version()
    results = inspect_profile(pdir, shell_version=shell_ver, offline=args.offline)

    if "error" in results:
        sys.stderr.write(f"decal review: {results['error']}\n")
        sys.exit(1)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        pname = os.path.basename(pdir.rstrip("/"))
        print_review(results, profile_name=pname)


if __name__ == "__main__":
    main()
