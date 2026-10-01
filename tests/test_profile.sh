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
t_done
