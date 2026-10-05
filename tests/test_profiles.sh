#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
P="$REPO/lib/profiles.py"
export DECAL_MEDIA="$T_TMP/media" DECAL_PROFILE_HOME="$T_TMP/active"; mkdir -p "$DECAL_MEDIA"
M="$T_TMP/mods"; for n in apps wallpaper; do mkdir -p "$M/$n"; echo '{"keys": {}}' > "$M/$n/schema.json"; : > "$M/$n/module.sh"; done
export DECAL_MODULES_DIR="$M"
TOML=$'[apps]\n[wallpaper]\n[notamodule]\n'

assert_eq "$(python3 -c "import sys; sys.path.insert(0,'$REPO/lib'); import profiles; print(profiles.count('''$TOML'''))")" "2" "count: module sections only"
assert_eq "$(python3 -c "import sys; sys.path.insert(0,'$REPO/lib'); import profiles; print(profiles.ago('2000-01-01T00:00:00+00:00'))")" "26 years ago" "ago: years"

# this machine: stamp files and folders; strays left out
mkdir -p "$T_TMP/s"; printf '%s' "$TOML" > "$T_TMP/s/profile.toml"
tar -czf "$HOME/decal-me.tar.gz" -C "$T_TMP/s" .; cp "$HOME/decal-me.tar.gz" "$HOME/decal-me.tar.gz.old"
echo junk > "$HOME/decal-broken.tar.gz"; mkdir -p "$HOME/decal-work"; cp "$T_TMP/s/profile.toml" "$HOME/decal-work/"; : > "$HOME/decal-work/.decal-stamp"
mkdir -p "$HOME/decal-notastamp"; cp "$T_TMP/s/profile.toml" "$HOME/decal-notastamp/"
# a stick, and recently used
mkdir -p "$DECAL_MEDIA/Ventoy/.Decal/profile"; cp "$T_TMP/s/profile.toml" "$DECAL_MEDIA/Ventoy/.Decal/profile/"
python3 "$REPO/lib/source.py" remember github:friend/setup
J=$(python3 "$P" list --json --only local)
q() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($2)" "$J"; }
assert_eq "$(q x "sorted(e['name'] for e in d['entries'] if e['kind']=='file')")" "['~/decal-me.tar.gz', '~/decal-work']" "local: the stamp file and stamp folder; .old, broken and non-stamp folders left out"
assert_eq "$(q x "[e['modules'] for e in d['entries'] if e['kind']=='file']")" "[2, 2]" "local: module counts"
assert_eq "$(q x "[(e['name'], e['label']) for e in d['entries'] if e['kind']=='stick']")" "[('Ventoy: .Decal', 'Ventoy')]" "stick: found"
assert_eq "$(q x "[e['source'] for e in d['entries'] if e['kind']=='recent']")" "['github:friend/setup']" "recent: listed"
assert_eq "$(q x "d['signed_in']")" "None" "--only local: GitHub not looked at"
# the active profile is marked
mkdir -p "$DECAL_PROFILE_HOME"; echo "$HOME/decal-me.tar.gz" > "$DECAL_PROFILE_HOME/.decal-source"
J=$(python3 "$P" list --json --only local)
assert_eq "$(q x "[e['name'] for e in d['entries'] if e['active']]")" "['~/decal-me.tar.gz']" "active: marked"
# no key: a sign-in row instead of GitHub
out=$(python3 "$P" list); assert_contains "$out" "Sign in to see your GitHub profiles" "no key: says how to see GitHub profiles"
assert_contains "$out" "On this machine" "text: grouped"; assert_contains "$out" "← active" "text: the active mark"

# GitHub: topic, names, full scan; each confirmed by profile.toml
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"
printf 'tester/decal-profile\ntester/oddname topic\ntester/handmade public\ntester/decal-notes\nother/decal-x\n' > "$G/seed"
for r in decal-profile oddname handmade; do mkdir -p "$G/contents/tester/$r"; printf '%s' "$TOML" > "$G/contents/tester/$r/profile.toml"; done
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
J=$(GITHUB_TOKEN=s3cret python3 "$P" list --json --only github)
assert_eq "$(q x "sorted(e['name'] for e in d['entries'])")" "['tester/decal-profile', 'tester/handmade', 'tester/oddname']" "github: profiles found three ways; decal-notes (no profile.toml) and others' repos left out"
assert_eq "$(q x "[e['private'] for e in d['entries'] if e['name']=='tester/handmade']")" "[False]" "github: public/private"
echo 120 > "$G/many"; kill "$GHPID"; wait "$GHPID" 2>/dev/null; rm -f "$G/port"
python3 "$REPO/tests/fixtures/fake_github_api.py" "$G" & GHPID=$!
for _ in $(seq 50); do [[ -s $G/port ]] && break; sleep 0.1; done
export DECAL_GITHUB="http://127.0.0.1:$(cat "$G/port")" DECAL_GITHUB_API="http://127.0.0.1:$(cat "$G/port")"
J=$(GITHUB_TOKEN=s3cret python3 "$P" list --json --only github)
assert_eq "$(q x "sorted(e['name'] for e in d['entries'])")" "['tester/decal-profile', 'tester/oddname']" "over 100 repos: no full scan; topic and names still found"
J=$(GITHUB_TOKEN=s3cret DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$P" list --json)
assert_eq "$(q x "d['notes']")" "[\"couldn't reach GitHub\"]" "GitHub down: a note"
assert_eq "$(q x "len([e for e in d['entries'] if e['kind']=='file'])")" "2" "...and local profiles still listed"
# decal profiles: the key it finds (GITHUB_TOKEN here), never on a command line
out=$(GITHUB_TOKEN=s3cret "$REPO/decal" profiles 2>&1); assert_contains "$out" "tester/decal-profile" "decal profiles lists GitHub"
assert_contains "$out" "~/decal-work" "...and this machine"
# stamp tags the repo with the topic
J2=$(GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" push "$T_TMP/s" tester/fresh --message t 2>&1)
assert_contains "$(cat "$G/topics.log" 2>/dev/null)" "tester/fresh decal-profile" "push: the decal-profile topic set"
GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" exists tester/fresh; assert_eq "$?" "0" "exists: yes"
GITHUB_TOKEN=s3cret python3 "$REPO/lib/github.py" exists tester/nope; assert_eq "$?" "1" "exists: no"
# decal whoami: the login of whatever key decal would use (GITHUB_TOKEN, GH_TOKEN, gh)
assert_eq "$(GH_TOKEN=s3cret "$REPO/decal" whoami 2>/dev/null)" "tester" "whoami: from GH_TOKEN too"
stub gh 'case "$*" in "auth token") echo s3cret ;; *) exit 1 ;; esac'
assert_eq "$("$REPO/decal" whoami 2>/dev/null)" "tester" "whoami: from a gh login"
stub gh 'exit 1'
"$REPO/decal" whoami >/dev/null 2>&1; assert_eq "$?" "1" "whoami: no key: fails quietly"
stub gh 'case "$*" in "auth token") echo s3cret ;; *) exit 1 ;; esac'
DECAL_STICK="$T_TMP" GH_TOKEN=s3cret "$REPO/decal" whoami >/dev/null 2>&1; assert_eq "$?" "1" "from a stick: the PC's gh login and GH_TOKEN are never used"
stub gh 'exit 1'
kill "$GHPID" 2>/dev/null
# GitHub answering with a web page (a Wi-Fi login) or hanging up: a plain message, no traceback (audit batch 3)
gh_odd() { python3 - "$1" <<'EOF'
import os, sys, threading, http.server
sys.path.insert(0, os.path.join(os.environ["REPO"], "lib")); import github
if sys.argv[1] == "bare":   # a timeout with no words of its own
    def no(*a, **k): raise TimeoutError()
    github.urllib.request.urlopen = no
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if sys.argv[1] == "drop":
            self.close_connection = True; return   # no answer at all
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(b"<html>Sign in to this Wi-Fi</html>")
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); threading.Thread(target=s.serve_forever, daemon=True).start()
github.API = f"http://127.0.0.1:{s.server_port}"; os.environ["GITHUB_TOKEN"] = "s3cret"
try:
    github.call("GET", "/repos/tester/x"); print("no error")
except github.Fail as e:
    print("Fail:", e)
EOF
}
export REPO
assert_contains "$(gh_odd html 2>&1)" "Fail: couldn't reach GitHub" "a web page instead of GitHub: plain failure"
assert_contains "$(gh_odd drop 2>&1)" "Fail: couldn't reach GitHub" "GitHub hangs up: plain failure"
assert_contains "$(gh_odd bare 2>&1)" "couldn't reach GitHub (TimeoutError)" "a failure with no message: still says what"
# a stick or stamp whose profile.toml isn't text: skipped, the rest still listed, no traceback (review)
mkdir -p "$DECAL_MEDIA/Bad/.Decal/profile" "$HOME/decal-bad"; printf 'a = "\xff"\n' > "$DECAL_MEDIA/Bad/.Decal/profile/profile.toml"
printf 'a = "\xff"\n' > "$HOME/decal-bad/profile.toml"; : > "$HOME/decal-bad/.decal-stamp"
out=$(python3 "$P" list --json --only local 2>&1); assert_eq "$?" "0" "a profile that isn't text: listing still works"
assert_not_contains "$out" "Traceback" "...without a traceback"; assert_contains "$out" "decal-work" "...the others still listed"
assert_not_contains "$out" "\"Bad\"" "a stick profile that isn't text: left out"
assert_contains "$out" "Ventoy" "...the other stick still listed"
rm -rf "$DECAL_MEDIA/Bad" "$HOME/decal-bad"
t_done
