#!/usr/bin/env python3
"""A tiny stand-in for GitHub's REST API and device sign-in (what lib/github.py and lib/auth.py call), for tests:
python3 fake_github_api.py STATE_DIR. Serves on 127.0.0.1 (port written to STATE_DIR/port). Accepts one token
(STATE_DIR/token). Repos live in memory; each ref update writes STATE_DIR/<owner>_<repo>.json with the commit's files
(path -> text) and count. Optional STATE_DIR files: seed (repos that exist: owner/name per line), hidden (owner/name N:
404 for the next N lookups, N=forever never), readonly (no push permission), device_script (one of pending, slow,
expired, denied, ok per poll; hold: pending for good), device_fail (the code request fails). Device requests are logged to device_log."""
import base64, hashlib, json, os, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = sys.argv[1]
TOKEN = open(os.path.join(STATE, "token")).read().strip()
USER = "tester"
repos, blobs, trees, commits = {}, {}, {}, {}
hidden = {}   # owner/name -> lookups still answered 404 (None: forever)


def sha(x):
    return hashlib.sha1(json.dumps(x, sort_keys=True).encode()).hexdigest()


def state(name):
    p = os.path.join(STATE, name)
    return open(p).read().splitlines() if os.path.exists(p) else None


for line in state("seed") or []:
    if line.strip():
        c = sha({"seed": line.strip()})
        repos[line.strip()] = {"private": True, "default_branch": "main", "head": c, "commits": 1}
for line in state("hidden") or []:
    if line.strip():
        name, n = line.split()
        hidden[name] = None if n == "forever" else int(n)


def next_poll():
    lines = state("device_script") or []
    word = lines[0].strip() if lines else "ok"
    if word == "hold":   # pending until the test changes the script
        return "pending"
    with open(os.path.join(STATE, "device_script"), "w") as f:
        f.write("\n".join(lines[1:]))
    return word or "ok"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body=None):
        data = json.dumps(body or {}).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

    def handle_any(self, method):
        with open(os.path.join(STATE, "log"), "a") as f:
            f.write(f"{method} {self.path} auth={self.headers.get('Authorization', '')}\n")
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        if self.path.startswith("/login/"):
            form = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode()).items()}
            return self.device(form)
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            return self.reply(401, {"message": "Bad credentials"})
        body = json.loads(raw) if raw else None
        p = self.path.strip("/").split("/")
        if p == ["user"]:
            return self.reply(200, {"login": USER})
        if method == "POST" and p == ["user", "repos"]:
            full = f"{USER}/{body['name']}"
            c = sha({"init": full}); commits[c] = {"tree": None, "parents": []}
            repos[full] = {"private": body.get("private"), "default_branch": "main", "head": c, "commits": 1}
            return self.reply(201, {"full_name": full, "default_branch": "main", "private": body.get("private")})
        if p[0] == "repos" and len(p) >= 3:
            full = f"{p[1]}/{p[2]}"
            r = repos.get(full)
            if full in hidden:
                left = hidden[full]
                if left is None or left > 0:
                    if left is not None:
                        hidden[full] = left - 1
                    return self.reply(404, {"message": "Not Found"})
            if r is None:
                return self.reply(404, {"message": "Not Found"})
            rest = p[3:]
            if not rest:
                push = not os.path.exists(os.path.join(STATE, "readonly"))
                return self.reply(200, {"full_name": full, "default_branch": r["default_branch"],
                                        "permissions": {"pull": True, "push": push}})
            if rest[:3] == ["git", "ref", "heads"]:
                return self.reply(200, {"object": {"sha": r["head"]}})
            if rest == ["git", "blobs"]:
                s = sha(body); blobs[s] = base64.b64decode(body["content"]); return self.reply(201, {"sha": s})
            if rest == ["git", "trees"]:
                s = sha(body); trees[s] = body["tree"]; return self.reply(201, {"sha": s})
            if rest == ["git", "commits"]:
                assert body["parents"] == [r["head"]], "commit not on top of the branch"
                s = sha(body); commits[s] = body; return self.reply(201, {"sha": s})
            if rest[:3] == ["git", "refs", "heads"] and method == "PATCH":
                r["head"] = body["sha"]; r["commits"] += 1
                files = {t["path"]: blobs[t["sha"]].decode("utf-8", "replace") for t in trees[commits[body["sha"]]["tree"]]}
                json.dump({"private": r["private"], "commits": r["commits"], "files": files,
                           "message": commits[body["sha"]]["message"]},
                          open(os.path.join(STATE, full.replace("/", "_") + ".json"), "w"))
                return self.reply(200, {"object": {"sha": body["sha"]}})
        return self.reply(404, {"message": "Not Found"})

    def device(self, form):
        cid = form.get("client_id", "")
        kind = "code" if self.path.startswith("/login/device/code") else "poll"
        with open(os.path.join(STATE, "device_log"), "a") as f:
            f.write(f"{kind} client_id={cid}\n")
        if kind == "code":
            if os.path.exists(os.path.join(STATE, "device_fail")):
                return self.reply(500, {"message": "Server Error"})
            host = f"http://127.0.0.1:{self.server.server_address[1]}"
            return self.reply(200, {"device_code": "dev123", "user_code": "WDJB-MJHT", "interval": 0,
                                    "verification_uri": host + "/login/device", "expires_in": 900})
        word = next_poll()
        if word == "ok":
            return self.reply(200, {"access_token": TOKEN, "token_type": "bearer"})
        err = {"pending": "authorization_pending", "slow": "slow_down", "expired": "expired_token",
               "denied": "access_denied"}[word]
        return self.reply(200, {"error": err, "interval": 0})

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PATCH(self): self.handle_any("PATCH")


srv = HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(STATE, "port"), "w").write(str(srv.server_address[1]))
srv.serve_forever()
