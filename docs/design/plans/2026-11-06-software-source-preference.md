# Software source preference implementation plan

Implementation plan for software source preference resolution (`prefer = ["flatpak", "distro", "brew"]`).

## Tasks

### Task 1: Update `modules/apps/schema.json`
- Add `"prefer": {"type": "names", "values": ["flatpak", "distro", "brew"], "default": ["flatpak", "distro", "brew"]}`.
- Add `"install": {"type": "names", "default": []}`.

### Task 2: Implement resolution logic in `modules/apps/module.sh`
- `_resolve_app <name>`: iterates over `P_prefer` and checks availability:
  - flatpak: `_fp_present "$name"` or `flatpak remote-info --system -- "$P_remote" "$name"`
  - distro: `_pkg_present "$name"` or `pkg_known "$name"`
  - brew: `have brew` and `brew info "$name"`
- Provenance recording in state files:
  - Flatpak apps added to managed flatpaks list
  - Distro packages installed with `pkg_install apps-prefer`
  - Brew formulas recorded in `$LS_USER_STATE/apps.brew`
- Clean removal:
  - Remove managed flatpaks
  - Call `pkg_remove apps-prefer`
  - Uninstall recorded brew formulas (`brew uninstall`)

### Task 3: Status reporting in `modules/apps/module.sh`
- `module_status` inspects each item in `P_install` and verifies presence in its recorded source.

### Task 4: Review update in `lib/review.py`
- Inspect `apps.install` against `prefer` order.

### Task 5: Hermetic tests in `tests/test_apps.sh`
- Test source resolution when flatpak is first.
- Test fallback to distro when not on flatpak.
- Test fallback to brew when not in distro.
- Test removal peels off from the matching source.
- Test invalid source in `prefer` fails validation.
