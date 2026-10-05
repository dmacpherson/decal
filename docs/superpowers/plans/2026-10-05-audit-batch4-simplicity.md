# Audit batch 4: simplicity

> Executed with superpowers:executing-plans (native). Spec: the 2026-10-05 compliance audit against CLAUDE.md →
> Keep it simple; build it once, Logic in small pure functions, Prefer what's already there (simplicity findings H2–H5,
> M1, M3–M6, the low-payoff list and dead code; H1 and M2 were closed in batch 1).

**Goal:** each job is done by one piece of code that every caller shares; `decal` and the menu are split by job;
no behaviour changes (the existing suites are the safety net, new shared pieces get their own tests).

## Tasks (each test-first where there's a new interface; otherwise the suite stays green)

1. **One GitHub request helper** (H2). `lib/gh.py`: `API`, `WEB`, `Offline`, `request(method, path, token=None,
   body=None, timeout=30) -> (status, data)` (JSON or `{}`; a non-JSON answer or a dropped line → `Offline`).
   `github.call`, `auth.api_get`, `auth.stick_ok` and `source.public` use it; `github.push` reads `/user` once.
2. **decal downloads from GitHub without curl** (H2). `source.py github OWNER/REPO [REF] OUT`: the tarball with the
   key from `GITHUB_TOKEN` (never the command line), via the safe downloader; exit 4 = not found or not allowed,
   3 = GitHub out of reach. `gh_tarball` keeps only the sign-in-and-retry loop and the messages.
3. **One release download** (H3). `install.sh --fetch-to DIR`: resolve the channel's release, download, verify,
   unpack into DIR, no swap. `usb_bin` uses it (so it follows the channel and `DECAL_REPO`, and needs no curl).
4. **Theme modules share their steps** (H4). `lib/common.sh`: `rec_has`/`rec_add`, `rec_remove_all`,
   `install_owned`, `gs_save`/`gs_restore`, `stamp_theme`; cursor, icons, gtk-theme, tools and wallpaper use them.
5. **`decal` split by job** (H5). `lib/stage.sh` (sources, trust, activation), `lib/cmd_stamp.sh`, `lib/cmd_new.sh`,
   `lib/cmd_usb.sh`; one `gh_write_key`, `save_profile`, `copy_profile`, `have_tty`; `INSTALL_URL` at the top.
6. **The menu split and deduplicated** (M1, M3, M4, M5, dead code). Pure helpers → `lib/menu_logic.py`; `GROUPS`
   and `tilde` once (profiles.py); the stick menu reads `stick.conf` with `usb.read_conf`; `profiles.py active` is
   the one answer to "which profile is active" (decal uses it); `stamp_modules` asks decal instead of grepping;
   dead code goes (`public = False`, unused `preview` args, identical branches, `pick_row`'s double work, the
   constant `stick_header` argument).
7. **Tests and small repeats** (M6, low payoff). `fake_github DIR` in tests/lib.sh (start, wait, export, stop) used
   by every suite that starts the fake; one `EXT_BASES`; one default stamp location.

Then: full suite, a fresh whole-branch review, fix, merge.
