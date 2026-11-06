# SSH module implementation plan

Implementation plan for the `ssh` client configuration module.

## Tasks

### Task 1: Create `modules/ssh/schema.json`
- Define keys:
  - `authorized-keys`: strings, default []
  - `known-hosts`: strings, default []
  - `config`: path, default ""
  - `hosts.*`: table with `hostname` (string), `user` (string), `port` (int), `identity-file` (string), `forward-agent` (bool)

### Task 2: Implement `modules/ssh/module.sh`
- `MODULE_DESC`, `MODULE_NEEDS_ROOT=0`, `STAMP_LIVE=1`.
- State tracking:
  - Recorded keys in `$LS_USER_STATE/ssh/` (`authorized_keys`, `known_hosts`).
  - `# decal ssh: begin` ... `# decal ssh: end` block in `~/.ssh/config`.
- `module_add`:
  - Ensure `~/.ssh` exists with 0700.
  - Append decal keys to `authorized_keys` and `known_hosts` (0600 / 0644).
  - Generate and inject decal config block into `~/.ssh/config` (0600).
- `module_remove`:
  - Strip decal keys from `authorized_keys` and `known_hosts`.
  - Strip decal config block from `~/.ssh/config`.
  - Clean up empty files and state.
- `module_status`:
  - Check whether keys and config blocks are present and match.
- `module_stamp`:
  - Read existing public keys or `~/.ssh/config` hosts.

### Task 3: Hermetic test suite `tests/test_ssh.sh`
- Test `add` sets authorized keys, known hosts, and config with strict permissions.
- Test `remove` peels off decal keys and leaves pre-existing user keys untouched.
- Test `status` reports installed / not-installed / partial.
- Test `stamp`.

### Task 4: Documentation & example
- Add `[ssh]` to `examples/profile/profile.toml` and list in `README.md`.
