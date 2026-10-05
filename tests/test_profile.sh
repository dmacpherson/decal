#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
M="$T_TMP/mods"; mkdir -p "$M/demo" "$M/other" "$M/plain"; touch "$M/demo/module.sh" "$M/other/module.sh" "$M/plain/module.sh"
cat > "$M/demo/schema.json" <<'EOF'
{"keys": {
  "name": {"type": "string", "default": "x"},
  "size": {"type": "int", "default": 24, "min": 1},
  "zoom": {"type": "number", "default": 1, "min": 0.5, "max": 4},
  "on": {"type": "bool", "default": true},
  "mode": {"type": "enum", "values": ["a", "b"], "default": "a"},
  "color": {"type": "color", "default": "#deddda"},
  "list": {"type": "strings", "default": []},
  "asset": {"type": "string-or-strings", "default": "one-*.tar.gz"},
  "install": {"type": "install", "default": "all"},
  "file": {"type": "path"},
  "image": {"type": "path-or-url", "default": ""},
  "source": {"type": "source", "default": "git+https://example.com/r"},
  "ref": {"type": "string"},
  "login.blur": {"type": "int", "default": 24},
  "defaults.*": {"type": "string"}
}, "required": ["file"]}
EOF
echo '{"keys": {"word": {"type": "string", "default": "hi"}}}' > "$M/other/schema.json"
P="$T_TMP/p"; mkdir -p "$P"; echo hi > "$P/f.txt"
prof() { cat > "$P/profile.toml"; }
emit() { python3 "$REPO/lib/profile.py" shell "$1" --profile "$P" --modules "$M"; }
chk() { python3 "$REPO/lib/profile.py" check --profile "$P" --modules "$M" 2>&1; }

# no profile.toml: nothing present, defaults still emitted
assert_eq "$(python3 "$REPO/lib/profile.py" sections --profile "$P" --modules "$M")" "" "no profile: no sections"
eval "$(emit other)"; assert_eq "$P__in_profile" "false" "absent section"; assert_eq "$P_word" "hi" "default when absent"

prof <<'EOF'
[demo]
file = "f.txt"
size = 32
list = ["a b", "c"]
install = ["X", "Y Z"]
image = "https://example.com/w.jpg"
[demo.login]
blur = 0
[demo.defaults]
browser = "com.brave.Browser"
text-editor = "org.gnome.TextEditor"
EOF
eval "$(emit demo)"
assert_eq "$P__in_profile" "true" "present"
assert_eq "$P_size" "32" "int"; assert_eq "$P_name" "x" "default string"; assert_eq "$P_on" "true" "bool default"
assert_eq "$P_login_blur" "0" "nested key flattened"
assert_eq "${#P_list[@]}" "2" "array length"; assert_eq "${P_list[0]}" "a b" "array keeps spaces"
assert_eq "${P_asset[0]}" "one-*.tar.gz" "string-or-strings default becomes array"
assert_eq "${P_install[1]}" "Y Z" "install list"
assert_eq "$P_file" "$P/f.txt" "path made absolute"
assert_eq "$P_image" "https://example.com/w.jpg" "url kept"
assert_eq "$P_ref" "" "optional without default -> empty"
assert_eq "${P_defaults[text-editor]}" "org.gnome.TextEditor" "wildcard table -> assoc array"
# a table key may contain dots (e.g. a file name like "profiles/decal.conf")
prof <<'EOF'
[demo]
file = "f.txt"
[demo.defaults]
"profiles/decal.conf" = "x"
EOF
out=$(python3 "$REPO/lib/profile.py" shell demo --profile "$P" --modules "$M" 2>&1); assert_eq "$?" "0" "dotted table key accepted"
eval "$out"; assert_eq "${P_defaults[profiles/decal.conf]}" "x" "dotted table key kept whole"
assert_eq "$(python3 "$REPO/lib/profile.py" sections --profile "$P" --modules "$M")" "demo" "sections"
eval "$(emit plain)"; assert_eq "$P__in_profile" "true" "module without schema is always in"
assert_eq "$(chk)" "" "valid profile passes check"

bad() { prof; local out; out=$(chk); assert_contains "$out" "$1" "$2"; python3 "$REPO/lib/profile.py" check --profile "$P" --modules "$M" >/dev/null 2>&1; assert_eq "$?" "2" "$2 (exit 2)"; }
bad "[demo] unknown key 'sise'" "unknown key" < <(printf '[demo]\nfile = "f.txt"\nsise = 3\n')
bad "expected an integer" "wrong type" < <(printf '[demo]\nfile = "f.txt"\nsize = "big"\n')
bad "must be >= 1" "min" < <(printf '[demo]\nfile = "f.txt"\nsize = 0\n')
bad "expected a number" "number type" < <(printf '[demo]\nfile = "f.txt"\nzoom = "big"\n')
bad "must be <= 4" "number max" < <(printf '[demo]\nfile = "f.txt"\nzoom = 5.5\n')
prof <<'EOF'
[demo]
file = "f.txt"
zoom = 1.5
EOF
eval "$(python3 "$REPO/lib/profile.py" shell demo --profile "$P" --modules "$M")"; assert_eq "$P_zoom" "1.5" "number accepted (decimal)"
bad "missing required key 'file'" "required" < <(printf '[demo]\nsize = 3\n')
bad "file not found" "missing file" < <(printf '[demo]\nfile = "nope.txt"\n')
bad "expected a colour" "colour" < <(printf '[demo]\nfile = "f.txt"\ncolor = "purple"\n')
bad "expected one of" "enum" < <(printf '[demo]\nfile = "f.txt"\nmode = "c"\n')
bad "unrecognized source" "bad source" < <(printf '[demo]\nfile = "f.txt"\nsource = "github-release:bad"\n')
bad "unknown section [nosuch]" "unknown section" < <(printf '[nosuch]\nx = 1\n')
bad "profile.toml" "toml syntax error" < <(printf '[demo\n')
# value rules (CLAUDE.md → Security: treat input as untrusted): names can't be options or paths, links are https,
# paths stay inside the profile
G="$T_TMP/gm"; mkdir -p "$G/guard"; : > "$G/guard/module.sh"
cat > "$G/guard/schema.json" <<'EOF'
{"keys": {"pkgs": {"type": "names", "default": []}, "one": {"type": "name", "default": "x"},
 "brew": {"type": "formulas", "default": []}, "theme": {"type": "theme", "default": "t"},
 "sub": {"type": "relpath", "default": ""}, "ref": {"type": "ref", "default": ""},
 "asset": {"type": "globs", "default": []}, "url": {"type": "url", "default": "https://x.org"},
 "file": {"type": "path", "default": ""}, "files.*": {"type": "path", "key": "relpath"},
 "font": {"type": "font", "default": "Mono 10"}}}
EOF
GP="$T_TMP/gp"; mkdir -p "$GP/in"; echo x > "$GP/in/f"; echo secret > "$T_TMP/outside"
ok()  { printf '[guard]\n%s\n' "$1" > "$GP/profile.toml"; python3 "$REPO/lib/profile.py" check --profile "$GP" --modules "$G" >/dev/null 2>&1; echo $?; }
bad() { printf '[guard]\n%s\n' "$1" > "$GP/profile.toml"; python3 "$REPO/lib/profile.py" check --profile "$GP" --modules "$G" 2>&1; }
for v in 'pkgs = ["-oDPkg::Pre-Invoke::=sh -c id"]' 'pkgs = ["--nogpgcheck"]' 'pkgs = ["../x"]' 'pkgs = ["a b"]' \
         'one = "-x"' 'brew = ["jq\"; system(\"id\"); \""]' 'brew = ["-x"]' 'theme = "../../etc/profile.d"' 'theme = "a/b"' \
         'theme = ".."' 'theme = "-x"' 'sub = "../x"' 'sub = "/etc"' 'sub = "a/../../x"' 'ref = "--upload-pack=id"' \
         'ref = "a..b"' 'asset = ["../x"]' 'asset = ["-x"]' 'url = "http://x.org/r"' 'file = "../outside"' \
         'pkgs = ["network-manager-"]' 'font = "Fira x\nshell sh -c id 10"' 'font = "Fira 10;os.execute(1)"' \
         'file = "/etc/passwd"' '[guard.files]
"../.bashrc" = "in/f"'; do
  out=$(bad "$v"); [[ $out == *"profile.toml: [guard]"* ]] || _t_fail "rejected with a plain message: $v → $out"; T_COUNT=$((T_COUNT+1))
done
for v in 'pkgs = ["org.gnome.Platform//47", "llama3:8b", "g++", "python3.12", "com.discordapp.Discord", "a@b.c"]' \
         'brew = ["jq", "user/tap/formula", "python@3.12"]' 'theme = "Demo Spaced Icons"' 'theme = "Bibata-Modern Classic"' \
         'sub = "pack_1"' 'sub = "a/b"' 'ref = "v1.2"' 'ref = "feature/x"' 'asset = ["bibata-*.tar.gz"]' \
         'url = "https://dl.flathub.org/repo/flathub.flatpakrepo"' 'file = "in/f"' 'pkgs = ["g++", "gcc-c++"]' \
         'font = "FiraCode Nerd Font 10"' 'font = "JetBrainsMono Nerd Font Mono 11.5"' '[guard.files]
"gtk-4.0/gtk.css" = "in/f"'; do
  assert_eq "$(ok "$v")" "0" "accepted: $v"
done
ln -s "$T_TMP/outside" "$GP/in/link"; assert_contains "$(bad 'file = "in/link"')" "must be a file inside the profile folder" "a link out of the profile: rejected"
# every real profile still validates
for d in "$REPO/examples/profile" "$REPO/tests/fixtures/profile"; do
  python3 "$REPO/lib/profile.py" check --profile "$d" --modules "$REPO/modules" >/dev/null 2>&1; assert_eq "$?" "0" "still valid: $d"
done
t_done
