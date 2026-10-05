#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# lib/gh.py: the one way decal talks to GitHub's API (auth.py, github.py, profiles.py, source.py use it)
# G MODE PYTHON: a tiny GitHub on 127.0.0.1 answering every request per MODE, then PYTHON runs with gh pointed at it
G() { REPO="$REPO" python3 - "$1" "$2" <<'PY'
import json, os, sys, threading, http.server
sys.path.insert(0, os.path.join(os.environ["REPO"], "lib")); import gh
mode = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def answer(self):
        if mode == "drop":
            self.close_connection = True; return
        code, ctype, body = {"json": (200, "application/json", json.dumps({"login": "me", "auth": self.headers.get("Authorization", ""), "method": self.command, "sent": self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()})),
                             "empty": (204, "application/json", ""),
                             "missing": (404, "application/json", json.dumps({"message": "Not Found"})),
                             "html": (200, "text/html", "<html>Sign in to this Wi-Fi</html>")}[mode]
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("X-OAuth-Scopes", "repo")
        self.end_headers(); self.wfile.write(body.encode())
    do_GET = do_POST = do_PUT = answer
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); threading.Thread(target=s.serve_forever, daemon=True).start()
gh.API = f"http://127.0.0.1:{s.server_port}"
try:
    exec(sys.argv[2])
except gh.Offline as e:
    print("Offline:", e)
PY
}
assert_eq "$(G json 's, d, h = gh.request("GET", "/user", "s3cret"); print(s, d["login"], d["auth"], h["X-OAuth-Scopes"])')" "200 me Bearer s3cret repo" "an answer: status, JSON, headers; the key as a Bearer header"
assert_eq "$(G json 's, d, h = gh.request("GET", "/user"); print(repr(d["auth"]))')" "''" "no key: no Authorization header"
assert_eq "$(G json 's, d, h = gh.request("POST", "/x", "k", {"a": 1}); print(d["method"], d["sent"])')" 'POST {"a": 1}' "a body goes as JSON"
assert_eq "$(G empty 'print(gh.request("PUT", "/x", "k")[:2])')" "(204, {})" "an empty answer: {}"
assert_eq "$(G missing 'print(gh.request("GET", "/x", "k")[:2])')" "(404, {'message': 'Not Found'})" "an error status: its code and GitHub's message"
assert_contains "$(G html 'gh.request("GET", "/user", "k")')" "Offline: something else answered" "a web page instead of GitHub: Offline"
assert_contains "$(G drop 'gh.request("GET", "/user", "k")')" "Offline:" "GitHub hangs up: Offline"
assert_contains "$(G json 'gh.API = "http://127.0.0.1:9"; gh.request("GET", "/user", "k")')" "Offline:" "nothing there: Offline"
t_done
