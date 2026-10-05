# decal v0.4.0 (draft release notes)

## New

- **decal on a USB stick.** `decal usb` (or USB in the menu) puts a double-clickable `Decal` on a stick, with your
  profile (a read-only key, a sign-in each time, or a copy) and a copy of decal for PCs without internet. On any Linux
  PC: double-click, and decal installs, fetches your profile and opens a menu made for the stick (apply, preview,
  take it all off, save this machine back).
- **Sign in with GitHub.** The Decal Profile apps (read, and write for 8 hours) replace pasting tokens: a code and a
  QR code for your phone. Making a token yourself still works, as do `GITHUB_TOKEN` and `gh`.
- **A profile browser.** `decal profiles` and the menu list your profiles on GitHub, on this machine, on sticks and
  recently used; `decal new` makes one (from this machine, a copy, or a starter).
- **Any source.** GitHub links, `owner/repo`, `.zip`/`.tar.gz` links and git repos all work as profiles. Someone
  else's profile asks first and offers a preview.
- **A dev channel** for trying what's next: `curl -fsSL https://dmacpherson.github.io/decal/dev/install | bash`.

## Changed

- Profiles are checked more strictly: names must look like names (no options, paths or `..`), links must be https,
  files must stay inside the profile. Package groups (`@x`), provides and wildcards aren't supported.
- The menu's keys moved: 1 Apply, 2 Stamp, 3 USB, 4 Remove, 5 Logs (6 Update, when there is one).
- `decal usb --yes` needs `--to`; `decal new --to file:PATH` always makes a `.tar.gz`.
- decal no longer needs `curl` (the installer still uses curl or wget).

## Fixed

- `decal remove apps` no longer uninstalls Flatpaks you had before decal. **Note:** records written by older versions
  list every Flatpak in your profile; before removing apps once after updating, check
  `/var/lib/decal/apps/managed` and delete the lines for apps you want to keep.
- Nothing decal writes can be left half-written by a crash; modules that can't apply on a machine (no GNOME, no
  Homebrew, ...) skip with a warning instead of stopping the run; no Python tracebacks reach you.
