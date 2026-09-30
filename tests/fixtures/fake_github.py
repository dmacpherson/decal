#!/usr/bin/env python3
"""Fake github.com for tests: serves files from ROOT as release v1 assets of o/r, and ROOT/files/* at /files/*."""
import http.server, os, sys

ROOT = sys.argv[1]


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, body, code=200):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path
        rel = os.path.join(ROOT, "release")
        if p == "/o/r/releases/latest":
            self.send_response(302); self.send_header("Location", "/o/r/releases/tag/v1"); self.end_headers(); return
        if p == "/o/r/releases/tag/v1":
            return self.send(b"<html>v1</html>")
        if p == "/o/r/releases/expanded_assets/v1":
            links = "".join(f'<a href="/o/r/releases/download/v1/{n}">{n}</a>' for n in sorted(os.listdir(rel)))
            return self.send(links.encode())
        for prefix, base in (("/o/r/releases/download/v1/", rel), ("/files/", os.path.join(ROOT, "files"))):
            if p.startswith(prefix):
                f = os.path.join(base, p[len(prefix):])
                if os.path.isfile(f):
                    return self.send(open(f, "rb").read())
        self.send(b"not found", 404)


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
