#!/usr/bin/env python3
"""A tiny stand-in for GitHub's REST API (the calls lib/github.py makes), for tests: python3 fake_github_api.py STATE_DIR
Serves on 127.0.0.1 (port written to STATE_DIR/port). Accepts one token (STATE_DIR/token). Repos live in memory;
each ref update writes STATE_DIR/<owner>_<repo>.json with the commit's files (path -> text) and count."""
import base64, hashlib, json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = sys.argv[1]
TOKEN = open(os.path.join(STATE, "token")).read().strip()
USER = "tester"
repos, blobs, trees, commits = {}, {}, {}, {}


def sha(x):
    return hashlib.sha1(json.dumps(x, sort_keys=True).encode()).hexdigest()


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
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            return self.reply(401, {"message": "Bad credentials"})
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
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
            if r is None:
                return self.reply(404, {"message": "Not Found"})
            rest = p[3:]
            if not rest:
                return self.reply(200, {"full_name": full, "default_branch": r["default_branch"]})
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

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PATCH(self): self.handle_any("PATCH")


srv = HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(STATE, "port"), "w").write(str(srv.server_address[1]))
srv.serve_forever()
