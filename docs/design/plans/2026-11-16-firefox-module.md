# Firefox Module Implementation Plan

## Goal
Implement `modules/firefox/` alongside `decal stamp`, `decal review`, `examples/profile/profile.toml`, `README.md`, and comprehensive unit tests matching decal's security, `--dry-run`, rollback, and Flatpak + native support standards.

## Tasks

1. **Firefox helpers (`modules/firefox/prefs.py`) + unit tests (`tests/test_firefox.sh`)**
   - Implement `profiles.ini` resolver (`resolve-profile`), `prefs.js` parser/merger/status/restorer (`prefs-apply`, `prefs-status`, `prefs-restore`), pure-Python `mozLz40\0` decompressor (`read-mozlz4`), and deterministic `policies.json` builder (`build-policy`, `drop-extensions`, `policy-status`).
   - Reject malformed/control-char pref keys, path traversal, and invalid AMO IDs.
   - Use symlink-safe `.decal-new` + `os.replace` writes preserving file permissions.

2. **Firefox module (`modules/firefox/schema.json`, `modules/firefox/module.sh`)**
   - Schema: `profile`, `prefs`, `search`, `containers`, `handlers`, `chrome`, `policies`, `extensions`.
   - `MODULE_NEEDS_ROOT=1` for `/etc/firefox/policies/policies.json` and system Flatpak extension paths; user-only backup/restore for `$LS_USER_STATE` and `--user` Flatpak.
   - `module_add`, `module_remove`, `module_drop` (`MODULE_CAN_DROP=1`), `module_status`, `module_stamp` (`STAMP_LIVE=1`).
   - Strict `--dry-run` isolation and running-Firefox guard.

3. **Stamp integration (`lib/stamp.py`, `tests/test_stamp.sh`)**
   - Add `cmd_firefox` (`stamp.py firefox --profile-dir DIR --to DIR`): stamps curated non-ephemeral prefs, `search.json` from `search.json.mozlz4`, `containers.json`, `chrome/` CSS files, and user-installed AMO extension IDs from `extensions.json`.
   - Add tests to `tests/test_stamp.sh`.

4. **Review integration (`lib/review.py`, `tests/test_review.sh`)**
   - Inspect `[firefox]` (including tagged `[firefox.<tag>]`): list extensions (with offline/online AMO lookup support), scan custom search engine / policy URLs, verify no regressions on existing review test fixtures.
   - Add tests to `tests/test_review.sh`.

5. **Docs & Example Profile (`examples/profile/profile.toml`, `README.md`, `docs/design/README.md`)**
   - Document `[firefox]` keys in `examples/profile/profile.toml` (validated by `test_examples.sh`) and add `firefox` to the module table in `README.md`.

6. **Verification**
   - Run `bash tests/test_firefox.sh`, `bash tests/test_stamp.sh`, `bash tests/test_review.sh`, `bash tests/test_examples.sh`, full `bash tests/run.sh`, `shellcheck`, `py_compile`, and `gitleaks`.
