# GitHub sign-in (part 1 of 4)

Part of a four-part feature: **1. GitHub sign-in** → 2. profile browser → 3. USB maker → 4. save back from a stick.
Each part gets its own spec, plan and implementation; later parts build on earlier ones. This spec covers part 1 only.

## Goal

Anyone can give decal access to a private profile on GitHub without knowing what a token is, on a machine that has
nothing set up yet, and without decal ever storing a key that can write. Power users keep what works today:
`GITHUB_TOKEN`, a `gh` login, or pasting a token they made themselves.

Success looks like:

- On a fresh machine, applying a private profile takes: scan a QR code with a phone (or open a link), type an
  8-character code, click Authorize. No copy-paste of secrets.
- A key that can write to GitHub is never written to disk by decal.
- Every failure says in plain words what's wrong and what to do, with the one link that fixes it where there is one.
- Existing setups keep working unchanged (`GITHUB_TOKEN`, `GH_TOKEN`, `gh auth login`, a pasted token, the current
  USB stick with `decal-token.txt`).

## Naming

User-facing names use **Decal**; commands and files use **decal**. The GitHub Apps are **Decal Profile** and
**Decal Profile Write** ("Decal" itself is taken by a GitHub account).

## How decal gets a key

Whenever decal needs GitHub access it knows two things: the repo, and whether it needs **read** or **write**.
It then tries, in order:

1. **A key that's already there:** `GITHUB_TOKEN`, then `GH_TOKEN`, then `gh auth token`. (On a USB stick, parts 3
   and 4 add the stick's saved read key here.)
2. **Otherwise it asks**, on the terminal (also when started from the menu, as today):
   - **Sign in with GitHub** (default): the sign-in screen below, using the **Decal Profile** app for read and the
     **Decal Profile Write** app for write.
   - **Make a token myself:** asks how long it should last (30 days / 90 days (default) / 1 year / never expires),
     opens GitHub's new fine-grained token page pre-filled (name `Decal`, that expiry, `contents=read` or
     `contents=write&administration=write`, since a first stamp creates the repo), says which repo to pick under "Only select repositories" (GitHub can't pre-fill that), and
     reads the pasted token (hidden typing).
   - Cancel.
3. **It checks the key** can do what's needed on that repo before carrying on (see Errors).

A key obtained by signing in lives only in memory for that decal run, and one sign-in covers the whole run (the
`decal` script hands it to its child processes the way it does `GITHUB_TOKEN` today). Nothing is written to the
machine.

Where nothing decides read vs write for the caller, read is used. In part 1 the callers are: applying / fetching a
private `github:` profile (read) and `decal stamp --github` (write).

## The two GitHub Apps

| | **Decal Profile** | **Decal Profile Write** |
|---|---|---|
| Used for | applying, browsing, keys saved on sticks | stamping, saving back, making new profiles |
| Repository permissions | Contents: read (Metadata: read is implied) | Contents: read & write, Administration: read & write |
| User key lifetime | never expires ("Expire user authorization tokens" off) | 8 hours (expiry on; decal never refreshes or stores them) |
| Installed on | repos the person picks (normally just their profile) | all repos, or picked ones |
| Settings | Public; device flow on; no callback URL; webhook off | same |

Administration write is what creating a repo needs. If Decal Profile Write is installed on picked repos only, a newly
created repo isn't covered; decal then sends the person to GitHub's new-repo page with the name filled in and to the
app's install page for that repo, instead of creating it itself. (Making new profiles is part 2; part 1 only needs
`stamp --github` to handle "repo exists but the app can't see it" with that install link.)

**Registration** is a one-time maintainer task, done by hand on github.com (Settings → Developer settings → GitHub
Apps → New), following a short checklist in the README's In depth section (the settings in the table above). The
apps' public client IDs go into `lib/auth.py`. Device flow needs no client secret, so nothing private is committed.

**Overrides** for forks, self-hosting and tests: `DECAL_GITHUB_APP_READ` / `DECAL_GITHUB_APP_WRITE` (client ID and
app slug, e.g. `Iv23abc…:decal`), and the existing `DECAL_GITHUB` (web) and `DECAL_GITHUB_API` (API) base URLs.

## The sign-in screen

Shown on the terminal. Two columns, so someone can sign in on this machine or with their phone:

```
 Sign in to GitHub so decal can read dmacpherson/decal-profile

 On this computer                         On your phone
 ────────────────                         ─────────────
 1. Open  github.com/login/device         ▄▄▄▄▄▄▄ ▄ ▄▄  ▄▄▄▄▄▄▄
    (opened in your browser)              █ ▄▄▄ █ ▀█▄▀█ █ ▄▄▄ █
 2. Enter WDJB-MJHT                       █ ███ █ ▄▀ ▀▄ █ ███ █
    (copied to your clipboard)            █▄▄▄▄▄█ █▀▄▀█ █▄▄▄▄▄█
                                          ...
                                          Scan, then enter WDJB-MJHT

 Waiting for GitHub...   Esc cancel · t paste a token instead
```

- The QR code encodes `https://github.com/login/device` (GitHub's device flow has no link that carries the code, so
  the code is shown in both columns). It's drawn with half-block characters, dark modules on a light quiet zone so
  phones read it on dark terminals.
- QR generation is built in: Nayuki's qrcodegen (MIT, one Python file) vendored as `lib/qrcodegen.py` with its
  licence header. No `qrencode` or pip package needed.
- Below about 76 columns the phone column moves under the other one.
- The browser is opened with `xdg-open` only when there's a desktop session (`DISPLAY`/`WAYLAND_DISPLAY`); the code is
  copied with `wl-copy` / `xclip` / `xsel` when one is installed. "(opened in your browser)" / "(copied to your
  clipboard)" show only when that actually happened.
- `t` switches to "make a token myself"; Esc cancels back to the key choice.

## Errors

| Situation | What decal does |
|---|---|
| Approved, but the app isn't installed on the repo (the repo answers 404 to the new key) | "Decal Profile can't see decal-profile yet: install it on that repo", the app's install link (account preselected where GitHub allows), then re-checks every few seconds and carries on once it can see the repo. No new code needed. |
| Code expired (GitHub's 15 minutes) | "The code expired" and a new code is shown. |
| Denied on GitHub, or Esc | Back to the key choice (sign in / make a token / cancel). |
| No internet / GitHub unreachable | Says so plainly and stops before changing anything. |
| Pasted token rejected | Says which: not a valid token (401) / no access to this repo (404) / expired, and asks again. |
| Write needed but the key can only read | Says the key can only read and offers to sign in with Decal Profile Write. |
| Repo doesn't exist (and the key is good) | Says the name may be misspelled or the repo deleted. |
| `slow_down` from GitHub | Polls less often, as GitHub asks. |
| No terminal (non-interactive run) | Fails as today: set `GITHUB_TOKEN` or log in with `gh auth login`. |

## Components

- **`lib/auth.py`** (new): command-line helper called by the `decal` script.
  - `auth.py get REPO --need read|write` runs the key order above (from "otherwise it asks" on; the script checks
    existing keys first, as today) and prints the key on stdout for the script to keep in memory. Prompts and the
    sign-in screen go to `/dev/tty`.
  - `auth.py check REPO --need read|write` checks the key in `GITHUB_TOKEN` and exits with a distinct code per
    error from the table, so callers can explain it.
  - `auth.py token-url --need read|write --days N|never` prints the pre-filled token page URL (also used by part 3).
  - Internals split into small functions: device-code request and polling, install-link building, the screen
    layout (pure function: code, URL, width → lines), the QR renderer (matrix → lines).
- **`lib/qrcodegen.py`**: vendored as published, licence header kept.
- **`decal`**: `gh_token` / `gh_ask` become one `gh_auth REPO read|write` that tries existing keys, then calls
  `auth.py get`, then exports the key for the rest of the run. `gh_tarball` (apply) and `do_stamp` (`--github`) call
  it. The existing wording about creating tokens is replaced by the flow above.
- **`lib/github.py`**: unchanged, apart from reporting "the app can't see this repo" distinctly so `stamp --github`
  can show the install link.
- **`.gitattributes`**: `docs/ export-ignore`, so specs stay out of the release download.
- **README**: In depth gains "Signing in to GitHub" (what the two apps can do, how to revoke: GitHub → Settings →
  Applications → Decal Profile → Revoke) and the maintainer registration checklist.

## Testing

All against a fake GitHub (a small local HTTP server in the tests, as `test_stamp.sh` and `test_fetch.sh` already
do), pointed at with `DECAL_GITHUB` / `DECAL_GITHUB_API` / `DECAL_GITHUB_APP_*`. No test touches the network.

- Device flow: pending → approved; `slow_down`; expired → new code; denied; the fake server records the client ID
  so read vs write app selection is checked.
- App not installed: repo 404 until the fake "installs" it, then the flow carries on without a new code.
- Pasted token: valid, invalid (401), no access (404), read-only key for a write need.
- Key order: `GITHUB_TOKEN` / `GH_TOKEN` / a stubbed `gh` are used before anything is asked; nothing is written
  under `$HOME` after a sign-in.
- Token URL: the exact pre-filled URL for read/write and each expiry.
- Screen layout: two columns at 100 columns, stacked at 60; "(opened…)"/"(copied…)" only when stubs succeed.
- QR: the rendered code decodes back to the URL (checked against qrcodegen's own matrix, not a scanner).
- Existing suites (`test_stamp.sh`, `test_fetch.sh`, apply) keep passing with `GITHUB_TOKEN` set as today.

## Out of scope (later parts)

- Profile browser, making new profiles (part 2).
- USB maker, keys saved on sticks, the stick's start screen (part 3).
- Saving back from a stick (part 4).
- Refreshing expiring keys, OAuth Apps, storing keys on the machine.
