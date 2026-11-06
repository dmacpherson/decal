# Git module design

A new `git` module: configures developer identity, default branch, signing keys, and core workflow preferences in git global configuration (`~/.config/git/config` / global gitconfig), with clean rollbacks on removal and stamp support.

## Goal

- Manage git identity and core config from `profile.toml` without clobbering unmanaged git settings.
- Record prior state in `$LS_USER_STATE/git-config.prev` so `decal remove git` restores exact prior values (or unsets keys decal added).
- Global ignores in `~/.config/git/ignore` managed cleanly with decal header/footer comment blocks.
- `decal stamp` reads the host's git configuration into a clean `[git]` section.
- Does not need root (`MODULE_NEEDS_ROOT=0`).

## Profile Configuration

```toml
[git]
name = "Denis Macpherson"
email = "denis@example.com"
default-branch = "main"
editor = "nano"
signing-key = "3AA5C34371567BD2"
sign-commits = true
auto-setup-remote = true
pull-rebase = false
ignores = [".DS_Store", "*.swp", ".direnv"]

[git.aliases]
co = "checkout"
st = "status -sb"
br = "branch"
```

## State & Rollback

- Previous values recorded in `$LS_USER_STATE/git-config.prev`:
  Format: `key=value` or `key=__UNSET__`.
- `module_remove` restores previous values or unsets newly added keys, then clears the state file.
- Any ignores added to `~/.config/git/ignore` are stripped between `# decal git: begin` and `# decal git: end`.
