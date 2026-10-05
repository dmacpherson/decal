# Audit batch 2: your data and clean removal

> Executed with superpowers:executing-plans (native). Spec: the 2026-10-05 compliance audit against CLAUDE.md →
> Peel it off cleanly, Write new then swap, Every platform or a clear skip, Nothing changes without a preview.

**Goal:** `remove` takes away exactly what `add` did and nothing the person had; no file decal writes can be left
half-written by a crash or Ctrl+C; a module that can't apply on this machine skips with a warning instead of
stopping the run.

## Tasks (each test-first)

1. **apps records only what it installed.** Flatpaks already present aren't recorded as decal's, so remove leaves
   them; the Flathub remote is recorded only when decal added it (and removed with the module); `--unused` only runs
   for runtimes that our uninstall left behind (skip it when nothing of ours was removed).
2. **Write new, then swap, everywhere.**
   - `swrite` and `etc_restore` (`lib/common.sh`): write `PATH.decal-new`, then `mv -f` (covers /etc files, hooks,
     units, and every state record).
   - `dconf_tool.py save_prev`, terminal's `~/.bashrc` hook edit, apps' `mimeapps.list`, gnome-extensions'
     `gtk.css`: temp file + `os.replace`.
   - `install.sh`: unpack beside the install (same filesystem) so the swap is a rename.
   - `activate_staged`: stage beside `$PROFILE_HOME`; rename the old aside, the new in, then delete the old.
   - `do_stamp` to a folder: write `DEST.new`, then swap.
3. **Skip, don't stop.** gnome-extensions without GNOME Shell, ollama without Homebrew, the wallpaper login
   background without its build tools (checked before any hook is installed), terminal adapters that can't install
   here (checked before step 1): `warn …; return 0`.
4. **Dry runs never crash.** claude's apt key/list writes skip under `--dry-run`; its repo record is written before
   the files it records.
5. **Undo restores the right thing.** brave records the Preferences path at add time and restores to it; terminal
   removes the Homebrew it installed (marker) or says it's kept and how to remove it, and restores
   `/home/linuxbrew` ownership; claude and docker use backend functions instead of `apt-get`/`apt-cache` directly.

Then: full suite, a fresh whole-branch review, fix, merge.
