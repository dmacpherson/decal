# VPN module

A new `vpn` module: installs and sets up the VPN tools a person picks (any one, several or all), so a profile can
carry "this machine uses Tailscale and the OpenVPN plugin" to every machine it's applied on, and `remove` peels it
off again. Built along the lines of `modules/docker` (packages, a service, a user permission) and `modules/claude`
(a vendor's signed package repo).

## Goal

Success looks like:

- `[vpn] install = ["tailscale"]` on Bazzite (Tailscale preinstalled, service off): one `decal add vpn` turns on
  tailscaled, lets you control it without sudo, starts the Tailscale tray icon at login, and says "sign in from the
  Tailscale icon in the tray". No reboot, no `ujust`.
- The same profile on Silverblue, Fedora, Debian/Ubuntu and Arch installs Tailscale from a trusted repo first.
- `install = ["tailscale", "netbird", "protonvpn", "wireguard", "openvpn", "openconnect"]` sets up all six;
  dropping one from the list and adding again removes just that one.
- `decal stamp` on a machine that uses these writes the matching `[vpn]` section.
- `decal remove vpn` takes away exactly what decal added, and never the machine's VPN identity or your connections.

Out of scope: signing in, auth keys, VPN connection files (`.ovpn`, WireGuard keys) or server URLs. Those are
secrets or per-person, and profiles can be public or sit on a stick. You sign in from each tray or app.

## Profile

```toml
[vpn]
install = ["tailscale", "netbird", "protonvpn", "wireguard", "openvpn", "openconnect"]
```

`schema.json`: `"install": {"type": "names", "values": [the six names], "default": []}`. `lib/profile.py` gains the
`values` option on `names` (each item must be one of them), so a typo or an unknown name fails the profile check
before anything runs. The profile only ever picks names: repo URLs, keys and fingerprints live in decal's code.

## Layout

- `modules/vpn/module.sh`: the runner contract. `module_add` adds each listed service and removes each recorded
  one that's no longer listed; `module_remove` removes every recorded one; `module_status`, `module_stamp`,
  `module_drop` (`MODULE_CAN_DROP=1`, for `remove --only TAG`), `MODULE_NEEDS_ROOT=1`.
- One short file per service, sourced by `module.sh`, each defining `<name>_add`, `<name>_remove`,
  `<name>_status`, `<name>_stamp`: `tailscale.sh`, `netbird.sh`, `protonvpn.sh`, and `nm.sh` for the three
  NetworkManager-based ones (wireguard, openvpn, openconnect: the same shape, differing only in packages).
- State under `$LS_STATE/vpn/` (root-owned), one record per thing decal did: `repo` files written by the repo
  helper, `<service>.enabled`, `tailscale.operator` (the user set), plus `pkg_install` ownership under the
  owner `vpn-<service>` so each service's packages come off on their own.
- The tray autostart is per user (Tailscale's `systemd` user unit); recorded in `$LS_USER_STATE/vpn.tray`.

## Shared vendor-repo helper

Three vendors need a signed repo on apt and dnf, which `modules/claude` already does for apt inline. It becomes
one helper in `lib/backends/_shared.sh`, used by both modules (claude moves onto it, unchanged in behaviour):

- `repo_add NAME --key URL FPR [--key URL FPR]... [--apt LINE] [--dnf BASEURL] [--repo-gpgcheck]` (several keys:
  Proton signs each Fedora release with its own): downloads each key with `ls_fetch` (https only), checks it holds
  exactly one primary key with the pinned fingerprint (`gpg --show-keys`), and fails closed if not. Then it writes the key and the source:
  - apt: the key to `/usr/share/keyrings/NAME-archive-keyring.asc`, `APT_LINE` (with `signed-by=` that key) to
    `/etc/apt/sources.list.d/NAME.list`, and the apt-updated marker cleared so the backend refreshes.
  - dnf, rpm-ostree: the key to `/etc/pki/rpm-gpg/decal-NAME.asc` and `/etc/yum.repos.d/NAME.repo` with
    `baseurl=DNF_BASEURL`, `gpgcheck=1` (and `repo_gpgcheck=1` where the vendor's own repo file sets it) and
    `gpgkey=file:///etc/pki/rpm-gpg/decal-NAME.asc`.
    The key is pinned locally, never fetched again by dnf from a URL. rpm-ostree reads the same folder. Key files
    are named by fingerprint; when decal learns a new key list, the next add rewrites the repo.
  - arch: nothing (the helper isn't called there).
  - The record is written first, so an interrupted add can still be undone. A repo file that already exists and
    wasn't written by decal (someone added Tailscale's repo by hand) is used as is and not recorded.
- `repo_remove NAME`: deletes exactly the files its record lists.
- Apt lines that name a release use `VERSION_CODENAME` from `/etc/os-release` (Tailscale's apt repo is per release).

The exact repo URLs and fingerprints are pinned in the plan, each checked against the vendor's published docs.

## Services

| | Fedora, Fedora Atomic | Debian/Ubuntu | Arch |
|---|---|---|---|
| tailscale | Tailscale's repo; `tailscale` | Tailscale's repo; `tailscale` | `tailscale` |
| netbird | NetBird's repo; `netbird`, `netbird-ui` | same | skipped (AUR only) |
| protonvpn | Proton's repo; `proton-vpn-gnome-desktop` | same | skipped (AUR only) |
| wireguard | `wireguard-tools` | `wireguard-tools` | `wireguard-tools` |
| openvpn | `NetworkManager-openvpn-gnome` | `network-manager-openvpn-gnome` | `networkmanager-openvpn` |
| openconnect | `NetworkManager-openconnect-gnome` | `network-manager-openconnect-gnome` | `networkmanager-openconnect` |

Package names differ by distro and go through `PKG_MAP` (`nm-openvpn`, `nm-openconnect`). A package that's already
installed (Tailscale on Bazzite, a plugin Fedora ships) isn't installed or recorded, so `remove` leaves it, and no
repo is added for it.

**tailscale**
1. The package (repo first, only when the package isn't already there).
2. tailscaled enabled. On a mutable system: `systemctl enable --now tailscaled`. On Fedora Atomic with a freshly
   layered package: enabled by a link in `multi-user.target.wants` (as docker does), so it starts after the reboot.
   Recorded only when decal turned it on.
3. `tailscale set --operator=$USER` (needs tailscaled running), so you and the tray control it without sudo.
   Recorded. Before the reboot on Atomic it's skipped with "after the reboot, run decal add vpn again".
4. Tray at login: `tailscale configure systray --enable-startup=systemd` (it only writes
   `~/.config/systemd/user/tailscale-systray.service`), then `systemctl --user enable` + `start` it, all as you
   (never with sudo; Tailscale 1.88+). Recorded; a unit you made yourself is left alone.
5. "Tailscale is ready: sign in from the Tailscale icon in the tray (or run tailscale up)."

**netbird**: the repo and both packages. NetBird's package turns its service on itself; where it couldn't (Fedora
Atomic, at layering time) decal runs `netbird service install` + `start` after the reboot, recorded. `netbird-ui` at
login: if the package doesn't add a login entry itself (the plan checks), decal adds one to `~/.config/autostart`,
recorded. "Sign in from the NetBird icon in the tray."

**protonvpn**: the repo and `proton-vpn-gnome-desktop`. On Fedora the repo trusts Proton's key for this release
and every later one decal knows (Proton publishes the next release's ahead), so an upgrade keeps working; a release
decal has no key for is skipped with a warning. On Fedora Atomic a warning: "Proton VPN supports Fedora
Workstation; on Atomic it's layered and may need a reboot". "Open Proton VPN and sign in."

**wireguard / openvpn / openconnect**: packages only. "Add connections in Settings → Network → VPN."

**Tray on GNOME**: when tailscale, netbird or protonvpn is chosen, GNOME is running and the AppIndicator extension
(`appindicatorsupport@rgcjonas.gmail.com`) isn't enabled, a warning says to add it to `[gnome-extensions]`. The
module doesn't change another module's section.

## Remove

Per service, from its records, newest first: tray autostart off (`systemctl --user disable --now`, the unit removed), operator cleared (`tailscale set --operator=`, only if it's still the recorded user), service
disabled and stopped (only if decal enabled it), packages decal installed removed (`pkg_remove vpn-<service>`), then
the repo (`repo_remove`).

Never removed: `/var/lib/tailscale`, `/var/lib/netbird` (the machine's identity on that network), Proton's sign-in,
NetworkManager connections. `remove` says: "this machine is still listed in your Tailscale admin console: remove it
there if you're done with it" (and the same for NetBird).

## Status

Per service, like `modules/claude`: `installed (tailscale, wireguard)`,
`partial (tailscale: reboot pending; netbird: not available on Arch)`, `not-installed`. A service is complete when
its package is present, its service is enabled and running, and (tailscale) the operator is set.

## Stamp

`module_stamp` writes `[vpn] install = [...]` with what it finds:
- tailscale, netbird: only when the service is enabled (Bazzite ships tailscale switched off; an unused copy isn't
  "used").
- protonvpn, openvpn, openconnect: the package is installed.
- wireguard: `wg` is present.
A stamp note lists them. Fedora ships some NetworkManager plugins already, so a stamp may list them; harmless (apply
skips what's present, remove only takes what decal added). No tag: plain `[vpn]`.

## Failures

- Fail closed, stopping the module with a plain message: a key without the pinned fingerprint ("the signing key
  from … doesn't have Tailscale's fingerprint …: not installed"), a failed download, a redirect to http. What was
  already done keeps its record, so `decal remove vpn` still cleans it up.
- Warn and skip, the run carries on: netbird or protonvpn on Arch; no tray support; a repo file or service that
  existed before decal (used as is, never removed).
- `--dry-run` prints every command and changes nothing.

## Security

- Profiles only pick from six fixed names; everything a root process trusts (repo URLs, keys, fingerprints) is in
  decal's code. A stranger's profile can't point your package manager at their repo.
- Keys are fingerprint-checked and pinned to local files; https only.
- sudo only for repos, packages, services and `--operator`; the tray autostart runs as you.
- No secrets are involved anywhere.
- Gets a `/security-review` before merging (it writes package-repo files root trusts).

## Testing

Tests come first, hermetic, like `tests/test_claude.sh` (fake root, stubbed `gpg`, `systemctl`, `tailscale`,
`netbird`, package managers, `ls_fetch`; no network).

`tests/test_vpn.sh`:
- each service: add writes the expected repo, packages, service link, operator and tray, with records; remove
  undoes exactly those
- dropping one name from `install` removes only that one
- Bazzite: tailscale installed and disabled → no repo, no package install; service enabled and recorded; remove
  disables it and keeps the package
- something already there (service enabled, repo file) is left in place by remove
- attacks: a wrong fingerprint writes nothing; an unknown name (`"evilvpn"`) or an extra key (a repo URL) is
  rejected by `profile.py check`
- Arch: netbird and protonvpn skipped with a warning, the rest installed
- Atomic before the reboot: `partial (reboot pending)`, no operator call
- `--dry-run` changes nothing
- stamp: `[vpn] install = [...]` for what's present; Bazzite's disabled tailscale not included
- GNOME without AppIndicator: the warning

Docs: a `vpn` row in the README's module table and a `[vpn]` example.

Elsewhere: `tests/test_profile.sh` for `names` with `values`; `tests/test_claude.sh` unchanged and passing on the
shared repo helper; the vpn module in the Fedora, Debian and Arch container runs (`tests/containers`) with the real
repos if that's cheap to add.
