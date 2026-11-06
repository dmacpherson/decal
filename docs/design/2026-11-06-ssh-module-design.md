# SSH module design

A new `ssh` module: manages developer SSH client configuration, public authorized keys, known host keys, and host blocks cleanly across machines, with strict security permissions and zero-trace rollbacks.

## Goal

- Manage SSH public authorized keys (`authorized-keys`) in `~/.ssh/authorized_keys`.
- Manage trusted host keys (`known-hosts`) in `~/.ssh/known_hosts` (e.g. for GitHub, GitLab, internal servers).
- Manage SSH client config via a profile config file (`config = "ssh/config"`) and/or `[ssh.hosts.<name>]` host blocks in `~/.ssh/config`.
- Strict file permissions: `~/.ssh` (0700), `~/.ssh/authorized_keys` (0600), `~/.ssh/config` (0600), `~/.ssh/known_hosts` (0644).
- Least privilege: User-level only (`MODULE_NEEDS_ROOT=0`).
- Clean removal: Only lines and blocks decal inserted are removed on `decal remove ssh`; user-added keys and host blocks are never touched.
- `decal stamp` stamps public keys and host definitions if present.

## Profile Configuration

```toml
[ssh]
authorized-keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... personal-laptop"
]
known-hosts = [
  "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
]
# config = "ssh/config" # optional path to extra config file

[ssh.hosts.github]
hostname = "github.com"
user = "git"
identity-file = "~/.ssh/id_ed25519"

[ssh.hosts.server]
hostname = "192.168.1.100"
user = "admin"
port = 2222
```
