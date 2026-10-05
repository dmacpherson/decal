# Audit batch 3: messages and tests

> Executed with superpowers:executing-plans (native). Spec: the 2026-10-05 compliance audit against CLAUDE.md →
> Plain words, Choices with a default and a way past, Tests (findings H1, M1–M6, M9, L1–L6, L9, L10; M7/M8 were
> closed in batch 1).

**Goal:** nothing decal says is a Python traceback or shell jargon; every failure says what happened and what to do;
every question has a switch; the suite never reaches the internet and never depends on timing.

## Tasks (each test-first)

1. **Tests never reach the internet** (H1, M1). `t_setup` exports `DECAL_GITHUB` and `DECAL_GITHUB_API` as
   `http://127.0.0.1:9` (fails at once), so any GitHub call a test didn't fake fails fast instead of going out; suites
   with a fake GitHub set their own. `test_terminal.sh` makes the font folder before every add that would download it.
2. **No tracebacks** (M2–M5, L3).
   - `usb.py write`: an `OSError` → "couldn't write to TARGET: REASON (is the stick full, read-only or unplugged?)".
   - `usb.py mount` without `udisksctl` → "can't mount DEVICE here (no udisksctl): mount the stick, then use --to
     with its folder".
   - `profile.py`: a `profile.toml` that isn't UTF-8 → `ProfileError("profile.toml isn't UTF-8 text")`.
   - `github.py call`: an answer that isn't JSON, a dropped connection (`OSError`, `http.client.HTTPException`) →
     `Fail("couldn't reach GitHub (…)")`.
   - `ui.py`: the update check timing out → no update shown, the menu carries on.
3. **Plain words** (M6, L1, L2, L6).
   - `start.sh`: a saved key's `decal use` failing while offline says "Couldn't reach GitHub…: connect to the
     internet and try again", not "the key no longer works" (the key message only when GitHub answers).
   - A missing option value (`--from`, `--how`, `--decal`, `--to`, `--profile`, `--tags`, `--only`) → "decal: --how
     needs saved-key, sign-in, copy or latest" (a shared `val` helper; no `line N: 2: parameter null`).
   - `gh_tarball` HTTP 000 → "couldn't reach GitHub to get github:X: check the internet connection".
   - `auth.py make_token`: an answer that isn't 1–4 asks again (as `get()` does).
4. **Choices with a way past** (M9, L4, L5).
   - `decal new --to stick:LABEL|PATH` picks the stick without asking; the "several sticks" message names it.
   - `decal usb --yes` without `--to` refuses ("--yes needs --to: which drive to write") instead of guessing.
   - The menu shows **USB** (not "Usb") and its keys read 1–6 in order.
5. **Tests wait for what they expect, not for time** (L9, L10).
   - `test_ui.sh` flows that rely on quiet gaps use `UNTIL:` steps; "anything but remove cancels" asserts that the
     question was shown before checking nothing was removed.
   - `test_auth.sh`'s `sleep 1; kill -INT` waits for the prompt instead.
   - New coverage: `usb.py` write failure, `start.sh` offline with a saved key, the menu's update-check timeout.

Then: full suite, a fresh whole-branch review, fix, merge.
