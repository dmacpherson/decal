#!/usr/bin/env python3
"""github.py push DIR REPO [--public] [--message MSG] : put a folder in a GitHub repo as one commit, without git.

REPO is NAME (on your account) or OWNER/NAME. A missing repo is created, private unless --public. The repo then
holds exactly the folder (files no longer in it are gone from the new commit; history keeps them). The token comes
from GITHUB_TOKEN (never the command line); DECAL_GITHUB_API points elsewhere (tests, via gh.py). Prints the repo's
OWNER/NAME on success. github.py exists REPO: exit 0 when it exists, 1 when not; github.py whoami: the key's login."""
import argparse, base64, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gh  # noqa: E402


class Fail(Exception):
    pass


def call(method, path, body=None):
    try:
        return gh.request(method, path, os.environ["GITHUB_TOKEN"], body, timeout=60)[:2]
    except gh.Offline as e:
        raise Fail(f"couldn't reach GitHub ({e})")


def need(res, what):
    code, data = res
    if code not in (200, 201):
        hint = " (the token needs permission to create repos and write their contents)" if code in (401, 403, 404) else ""
        raise Fail(f"{what}: HTTP {code} {data.get('message', '')}{hint}".rstrip())
    return data


def push(folder, repo, public, message):
    me = need(call("GET", "/user"), "who is this token for")["login"]
    if "/" not in repo:
        repo = me + "/" + repo
    code, info = call("GET", f"/repos/{repo}")
    if code == 404:
        owner, name = repo.split("/", 1)
        path = "/user/repos" if owner == me else f"/orgs/{owner}/repos"
        info = need(call("POST", path, {"name": name, "private": not public, "auto_init": True,
                                        "description": "My Linux setup, stamped by decal"}), f"create {repo}")
        print(f"created {'public' if public else 'private'} repo {repo}", file=sys.stderr)
    elif code != 200:
        need((code, info), f"look up {repo}")
    branch = info.get("default_branch") or "main"
    head = need(call("GET", f"/repos/{repo}/git/ref/heads/{branch}"), f"{repo} {branch}")["object"]["sha"]
    tree = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for n in sorted(files):
            p = os.path.join(root, n)
            if os.path.islink(p):
                continue
            with open(p, "rb") as f:
                blob = need(call("POST", f"/repos/{repo}/git/blobs",
                                 {"content": base64.b64encode(f.read()).decode(), "encoding": "base64"}), f"upload {n}")
            mode = "100755" if os.access(p, os.X_OK) else "100644"
            tree.append({"path": os.path.relpath(p, folder), "mode": mode, "type": "blob", "sha": blob["sha"]})
    t = need(call("POST", f"/repos/{repo}/git/trees", {"tree": tree}), "write the tree")["sha"]
    c = need(call("POST", f"/repos/{repo}/git/commits", {"message": message, "tree": t, "parents": [head]}), "commit")["sha"]
    need(call("PATCH", f"/repos/{repo}/git/refs/heads/{branch}", {"sha": c}), f"update {branch}")
    topics = info.get("topics") or []
    if "decal-profile" not in topics:   # so decal profiles finds it, whatever its name
        code, _ = call("PUT", f"/repos/{repo}/topics", {"names": sorted(set(topics) | {"decal-profile"})})
        if code != 200:
            print("note: couldn't tag the repo with the decal-profile topic", file=sys.stderr)
    print(repo)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["push", "whoami", "exists"])
    ap.add_argument("folder", nargs="?"); ap.add_argument("repo", nargs="?")
    ap.add_argument("--public", action="store_true"); ap.add_argument("--message", default="decal stamp")
    a = ap.parse_args()
    if not os.environ.get("GITHUB_TOKEN"):
        sys.exit("error: no GitHub token")
    try:
        if a.cmd == "whoami":
            print(need(call("GET", "/user"), "who is this token for")["login"])
        elif a.cmd == "exists":
            code, _ = call("GET", f"/repos/{a.folder}")
            sys.exit(0 if code == 200 else 1 if code == 404 else 2)
        else:
            push(a.folder, a.repo, a.public, a.message)
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
