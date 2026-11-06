# decal v0.5.0 (draft release notes)

## New

- **VPN module.** `[vpn]` installs and sets up your choice of VPN tools:
  - Tailscale: turns on the service, sets up user-level control without sudo, and starts the tray icon at login.
  - NetBird and Proton VPN: configured from vendor-signed repositories with pinned GPG keys, including tray clients at login.
  - WireGuard, OpenVPN, and OpenConnect: NetworkManager integration across all supported distros.
  - Clean removal: only packages and services decal added are removed; connections and identities remain intact.
- **Shared vendor-repo helper.** `repo_add` and `repo_remove` in backends manage signed vendor repositories (apt, dnf, rpm-ostree) with strict single-key pinned fingerprint validation. Claude Desktop repo management moved to this helper.
- **Profile review.** `decal review [PROFILE]` (and an `r` review option when prompted before applying someone else's profile):
  - Inspects everything a profile installs or downloads, grouped clearly.
  - Trust signals: checks Flathub (verified publisher, total installs), extensions.gnome.org (download count, GNOME version compatibility), Homebrew taps (core vs third-party), distro package changes, download host security (http vs https, bare IPs, shorteners, unrecognized domains), and bundled files (executable permissions, scripts/binaries, large files >10 MB).
  - Includes machine-readable `--json` output.
- **Software source preference.** `[apps] prefer = ["flatpak", "distro", "brew"]` and `[apps] install = [...]`:
  - Dynamically resolves software across Flathub, native distro repositories, and Homebrew in your specified priority order.
  - Provenance is recorded per item, ensuring `decal remove apps` cleanly uninstalls each application from the exact source that installed it.
- **Git module.** `[git]` configures developer identity (`name`, `email`), `default-branch`, `editor`, commit signing (`signing-key`, `sign-commits`), `auto-setup-remote`, `pull-rebase`, aliases (`[git.aliases]`), and global ignore rules (`~/.config/git/ignore`). Reversible: preserves and restores any prior settings.
- **SSH module.** `[ssh]` manages developer SSH client configurations:
  - Authorized keys (`authorized-keys`) in `~/.ssh/authorized_keys`.
  - Known hosts (`known-hosts`) in `~/.ssh/known_hosts`.
  - Client config and host definitions (`[ssh.hosts.*]`) in `~/.ssh/config`.
  - Enforces strict security permissions (`0700` ~/.ssh, `0600` keys and config, `0644` known hosts).
  - Leaves pre-existing user keys and host blocks untouched on removal.

## Changed

- Untrusted profile confirmation prompt (`trust()`): now defaults to `[r]` review, allowing full inspection of what will be installed or changed before applying.
- `.gitattributes`: export-ignore anchored to the repository root so release archives retain `modules/tools/`.
- Test harness: interactive TTY tests wrapped with `setsid -w` for reliable non-blocking test execution.
