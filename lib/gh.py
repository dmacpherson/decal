"""gh.py: the one way decal talks to GitHub's API (auth.py, github.py, profiles.py and source.py use it).
DECAL_GITHUB / DECAL_GITHUB_API point elsewhere (tests)."""
import http.client, json, os, urllib.error, urllib.parse, urllib.request

WEB = os.environ.get("DECAL_GITHUB", "https://github.com").rstrip("/")
API = os.environ.get("DECAL_GITHUB_API", "https://api.github.com").rstrip("/")


class Offline(Exception):
    """No answer, or not GitHub's (a Wi-Fi login page)."""


def _origin(url):
    u = urllib.parse.urlparse(url)
    return u.scheme, u.hostname, u.port or {"https": 443, "http": 80}.get(u.scheme)


class KeyStaysHome(urllib.request.HTTPRedirectHandler):
    """A redirect to another scheme, host or port doesn't take the key along (as curl does)."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and _origin(newurl) != _origin(req.full_url):
            new.remove_header("Authorization")
        return new


def request(method, path, token=None, body=None, timeout=30):
    """(status, data, headers) for API + PATH. DATA is GitHub's JSON answer ({} when empty; {"message": ...} with an
    error status). The key goes in a header, never the URL. Raises Offline when GitHub can't be reached."""
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.build_opener(KeyStaysHome).open(req, timeout=timeout) as r:
            status, headers, raw = r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read()).get("message", "")
        except (ValueError, AttributeError, OSError, http.client.HTTPException):
            msg = ""
        return e.code, {"message": msg}, e.headers
    except urllib.error.URLError as e:
        raise Offline(str(e.reason))
    except (OSError, http.client.HTTPException) as e:   # the connection dropped midway
        raise Offline(str(e) or type(e).__name__)
    try:
        return status, (json.loads(raw) if raw else {}), headers
    except ValueError:
        raise Offline("something else answered: a Wi-Fi login page?")


def get(path, token=None):
    """(status, data) of a GET."""
    return request("GET", path, token)[:2]
