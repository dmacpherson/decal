# Git module implementation plan

Implementation plan for the `git` configuration module.

## Tasks

### Task 1: Create `modules/git/schema.json`
- Define keys:
  - `name`: string
  - `email`: string
  - `default-branch`: string, default "main"
  - `editor`: string, default ""
  - `signing-key`: string, default ""
  - `sign-commits`: bool, default false
  - `auto-setup-remote`: bool, default true
  - `pull-rebase`: bool, default false
  - `ignores`: names (strings)
  - `aliases.*`: string

### Task 2: Create `modules/git/module.sh`
- `MODULE_DESC`, `MODULE_NEEDS_ROOT=0`, `STAMP_LIVE=1`.
- `module_add`:
  - Check / record prior key values in `$LS_USER_STATE/git-config.prev`.
  - Apply `user.name`, `user.email`, `init.defaultBranch`, `core.editor`, `user.signingkey`, `commit.gpgsign`, `push.autoSetupRemote`, `pull.rebase`, `alias.*`.
  - Write ignores to `~/.config/git/ignore` with comment markers.
- `module_remove`:
  - Restore prior key values or unset keys decal added.
  - Remove decal block from `~/.config/git/ignore`.
  - Remove state file.
- `module_status`:
  - Check whether active git global config matches profile settings.
- `module_stamp`:
  - Read active global git config into `[git]` and `[git.aliases]`.

### Task 3: Hermetic test suite `tests/test_git.sh`
- Test `add` sets git configuration and ignores.
- Test `remove` restores previous configuration and removes ignores.
- Test unsetting keys that did not exist before decal.
- Test `status` reports installed / not-installed / partial.
- Test `stamp` produces correct TOML.

### Task 4: Documentation & example
- Add `[git]` to `examples/profile/profile.toml` and list in `README.md`.
