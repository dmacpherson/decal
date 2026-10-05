#!/usr/bin/env python3
"""fetch.py SOURCE [...] : materialize a decal source into the cache and print its local path."""
import argparse, fnmatch, hashlib, os, re, shutil, subprocess, sys, tempfile, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import source  # noqa: E402  (https only, no downgrade, safe unpacking: one place for all of decal)


class FetchError(Exception):
    pass


GITHUB = os.environ.get("DECAL_GITHUB", "https://github.com").rstrip("/")
ARCHIVES = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tar", ".zip")


def cache_dir():
    base = os.environ.get("DECAL_CACHE") or os.path.join(
        os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "decal", "sources")
    os.makedirs(base, exist_ok=True)
    return base


def key(*parts):
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()[:16]


def http_get(url):
    """URL's final address and body: https only (redirects to http refused), at most source.LIMIT bytes."""
    if not source.allowed(url):
        raise FetchError(f"download refused: {url}: use an https:// link")
    req = urllib.request.Request(url, headers={"User-Agent": "decal"})
    try:
        with urllib.request.build_opener(source._NoDowngrade).open(req, timeout=120) as r:
            data = r.read(source.LIMIT + 1)
            if len(data) > source.LIMIT:
                raise FetchError(f"download refused: {url} is larger than {source.LIMIT // (1024 * 1024)} MB")
            return r.geturl(), data
    except FetchError:
        raise
    except source.Bad as e:
        raise FetchError(f"download refused: {e}")
    except Exception as e:
        raise FetchError(f"download failed: {url}: {e}")


def extract(path, name, dest):
    """Unpack an archive (by its name) with source.unpack: links only when they stay inside (themes use them)."""
    if not name.lower().endswith(ARCHIVES):
        return False
    try:
        source.unpack(path, dest, links="inside")
    except source.Bad as e:
        raise FetchError(f"{name}: {e}")
    return True


def cached(out, err):
    """An update check failed: fall back to the copy already in the cache (e.g. offline after ./decal fetch)."""
    print(f"fetch: {err}; using the cached copy", file=sys.stderr)
    return out


KEEP_DAYS = 30


def mark(d, ident):
    """Remember which source a cache entry belongs to (versions of one source share it) and that it was just used."""
    f = os.path.join(d, ".decal-source")
    if not os.path.exists(f):
        with open(f, "w") as fh:
            fh.write(ident + "\n")
    os.utime(d)
    return d


def prune(cache):
    """Keep one version per source (the last used); drop what's unused for KEEP_DAYS and half-finished downloads."""
    now, newest, entries = time.time(), {}, []
    for n in os.listdir(cache):
        p = os.path.join(cache, n)
        if n.endswith(".tmp"):
            shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.unlink(p)
            continue
        age = now - os.path.getmtime(p)
        if age > KEEP_DAYS * 86400:
            shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.unlink(p)
            continue
        f = os.path.join(p, ".decal-source")
        if os.path.isdir(p) and os.path.isfile(f):
            ident = open(f).read().strip()
            entries.append((ident, p))
            if ident not in newest or os.path.getmtime(p) > os.path.getmtime(newest[ident]):
                newest[ident] = p
    for ident, p in entries:
        if newest[ident] != p:
            shutil.rmtree(p, ignore_errors=True)


def swap_in(tmp, final):
    shutil.rmtree(final, ignore_errors=True)
    os.rename(tmp, final)


def fetch_git(src, path, ref, cache):
    url = src[len("git+"):]
    d = os.path.join(cache, "git-" + key(url, path, ref))
    out = os.path.join(d, path) if path else d
    ident = f"git {url} {path}"
    if ref and os.path.isdir(os.path.join(d, ".git")) and os.path.exists(out):
        mark(d, ident)
        return out
    try:
        out = _git_refresh(url, d, out, path, ref)
    except FetchError as e:
        if os.path.isdir(os.path.join(d, ".git")) and os.path.exists(out):
            mark(d, ident)
            return cached(out, e)
        raise
    mark(d, ident)
    return out


def _git_refresh(url, d, out, path, ref):
    tmp = d + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)

    def git(*a):
        r = subprocess.run(["git", "-C", tmp, *a], capture_output=True, text=True)
        if r.returncode:
            raise FetchError(f"git {a[0]} failed for {url}: {r.stderr.strip()[-300:]}")

    git("init", "-q")
    git("remote", "add", "origin", url)
    filt = [] if url.startswith("file://") else ["--filter=blob:none"]
    git("fetch", "-q", "--depth", "1", *filt, "origin", ref or "HEAD")
    if path:
        git("sparse-checkout", "set", "--no-cone", f"/{path.strip('/')}/")
    git("checkout", "-q", "FETCH_HEAD")
    if path and not os.path.exists(os.path.join(tmp, path)):
        shutil.rmtree(tmp, ignore_errors=True)
        raise FetchError(f"{path!r} not found in {url}")
    swap_in(tmp, d)
    return out


def fetch_release(src, assets, version, cache):
    repo = src.split(":", 1)[1]
    if not assets:
        raise FetchError(f"{src}: no --asset pattern given")
    ident = f"rel {repo} {' '.join(assets)}"
    tag = version
    last = os.path.join(cache, "rel-latest-" + key(repo, *assets))   # the tag "latest" last resolved to
    if not tag or tag == "latest":
        try:
            final, _ = http_get(f"{GITHUB}/{repo}/releases/latest")
        except FetchError as e:
            prev = open(last).read().strip() if os.path.isfile(last) else ""
            pd = os.path.join(cache, "rel-" + key(repo, prev, *assets))
            if prev and os.path.isfile(os.path.join(pd, ".complete")):
                return cached(mark(pd, ident), e)
            raise
        m = re.search(r"/releases/tag/([^/?#]+)", final)
        if not m:
            raise FetchError(f"{src}: could not find the latest release (got {final})")
        tag = urllib.parse.unquote(m.group(1))
        with open(last, "w") as f:
            f.write(tag)
    d = os.path.join(cache, "rel-" + key(repo, tag, *assets))
    if os.path.isfile(os.path.join(d, ".complete")):
        return mark(d, ident)
    _, page = http_get(f"{GITHUB}/{repo}/releases/expanded_assets/{tag}")
    pat = rf'/{re.escape(repo)}/releases/download/{re.escape(tag)}/([^"?#<\s]+)'
    names = sorted({urllib.parse.unquote(n) for n in re.findall(pat, page.decode(errors="replace"))})
    tmp = d + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    for glob in assets:
        hits = [n for n in names if fnmatch.fnmatch(n, glob)]
        if not hits:
            shutil.rmtree(tmp, ignore_errors=True)
            raise FetchError(f"{src} {tag}: no asset matches {glob!r} (available: {', '.join(names) or 'none'})")
        for n in hits:
            _, data = http_get(f"{GITHUB}/{repo}/releases/download/{tag}/{urllib.parse.quote(n)}")
            with tempfile.NamedTemporaryFile(delete=False, dir=cache) as f:
                f.write(data)
            try:
                if not extract(f.name, n, tmp):
                    shutil.move(f.name, os.path.join(tmp, n))
            finally:
                if os.path.exists(f.name):
                    os.unlink(f.name)
    open(os.path.join(tmp, ".complete"), "w").close()
    swap_in(tmp, d)
    return mark(d, ident)


def fetch_url(url, cache):
    name = os.path.basename(urllib.parse.urlparse(url).path) or "download"
    d = os.path.join(cache, "url-" + key(url))
    if not os.path.isfile(os.path.join(d, ".complete")):
        _, data = http_get(url)
        tmp = d + ".tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp)
        p = os.path.join(tmp, name)
        with open(p, "wb") as f:
            f.write(data)
        if extract(p, name, tmp):
            os.unlink(p)
        open(os.path.join(tmp, ".complete"), "w").close()
        swap_in(tmp, d)
    mark(d, f"url {url}")
    items = [x for x in os.listdir(d) if x not in (".complete", ".decal-source")]
    if len(items) == 1 and os.path.isfile(os.path.join(d, items[0])):
        return os.path.join(d, items[0])
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?")
    ap.add_argument("--prune", action="store_true", help="tidy the cache (see prune()) and exit")
    ap.add_argument("--path", default="")
    ap.add_argument("--ref", default="")
    ap.add_argument("--asset", action="append", default=[])
    ap.add_argument("--version", default="")
    ap.add_argument("--profile", default=".")
    a = ap.parse_args()
    if a.prune:
        prune(cache_dir())
        return
    if not a.source:
        ap.error("a source is needed")
    try:
        src, cache = a.source, cache_dir()
        if src.startswith("git+"):
            print(fetch_git(src, a.path.strip("/"), a.ref, cache))
            return
        if src.startswith("github-release:"):
            out = fetch_release(src, a.asset, a.version, cache)
        elif src.startswith(("https://", "http://")):
            out = fetch_url(src, cache)
        else:
            out = src if os.path.isabs(src) else os.path.join(a.profile, src)
            if not os.path.exists(out):
                raise FetchError(f"not found: {out}")
            out = os.path.abspath(out)
        if a.path:
            out = os.path.join(out, a.path)
            if not os.path.exists(out):
                raise FetchError(f"{a.path!r} not found in {src}")
        print(out)
    except FetchError as e:
        print(f"fetch: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
