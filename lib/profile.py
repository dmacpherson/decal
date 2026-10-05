#!/usr/bin/env python3
"""profile.toml reader for decal: validate against modules/<m>/schema.json, emit shell vars.

Tags: a sub-table of a section that isn't one of the module's own (e.g. [apps.dev] next to [apps.defaults]) holds
extra settings for machines given that tag (./decal --tags dev). They are laid over the section: lists add on, other
values replace. A section that only has tag sub-tables (e.g. just [docker.dev]) is only in the profile with that tag.
DECAL_TAGS (comma-separated; "all" = every tag) picks the tags; none = the untagged settings only."""
import argparse, copy, json, os, re, shlex, sys, tomllib


class ProfileError(Exception):
    pass


# what a value may look like when it becomes an argument or a path (CLAUDE.md → Security: treat input as untrusted)
NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+:@~=-]*(/[A-Za-z0-9._+:@~=-]+)*(//[A-Za-z0-9._+:@~=-]+)?")
FORMULA_RE = re.compile(r"[a-z0-9][a-z0-9._+@-]*(/[a-z0-9._+@-]+){0,2}")
REF_RE = re.compile(r"[A-Za-z0-9._/-]+")
RULES = {
    "name": "a name (letters, digits and . _ + : @ ~ = -; no spaces, no leading -, no ..)",
    "formula": "a Homebrew formula (name, or user/tap/name)",
    "theme": "a name without / (and not starting with -)",
    "relpath": "a folder inside the source (relative, no ..)",
    "ref": "a git branch, tag or commit",
    "glob": "a file name pattern (no /, not starting with -)",
    "font": "a font and size, like 'FiraCode Nerd Font 10'",
}
FONT_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._+-]* [0-9]{1,3}(\.[0-9]{1,2})?")


def expected(t, v):
    """What T expects, said for V (a package group, provide or wildcard gets told so)."""
    if t == "name" and isinstance(v, str) and (v.startswith("@") or "(" in v or "*" in v or "?" in v):
        return RULES[t] + "; package groups (@…), provides (…(…)) and wildcards aren't supported: list each package by name"
    return RULES[t]


def rule_ok(t, v):
    if not isinstance(v, str) or v == "" or any(ord(c) < 32 for c in v):
        return False
    if t == "name":   # a trailing - asks apt to remove the package
        return bool(NAME_RE.fullmatch(v)) and ".." not in v and not v.endswith("-")
    if t == "formula":
        return bool(FORMULA_RE.fullmatch(v)) and ".." not in v
    if t == "theme":
        return "/" not in v and v not in (".", "..") and not v.startswith("-")
    if t == "relpath":
        parts = v.split("/")
        return not v.startswith(("/", "-")) and ".." not in parts and "\\" not in v
    if t == "ref":
        return bool(REF_RE.fullmatch(v)) and not v.startswith("-") and ".." not in v
    if t == "glob":
        return "/" not in v and not v.startswith("-")
    if t == "font":
        return bool(FONT_RE.fullmatch(v))
    return False


SOURCE_RE = re.compile(r"^(git\+(https|ssh|file)://\S+|github-release:[\w.-]+/[\w.-]+|https://\S+)$")


def module_names(modules):
    return sorted(d for d in os.listdir(modules) if os.path.isfile(os.path.join(modules, d, "module.sh")))


def load_schema(modules, name):
    p = os.path.join(modules, name, "schema.json")
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def load_profile(pdir):
    p = os.path.join(pdir, "profile.toml")
    if not os.path.exists(p):
        return {}
    try:
        with open(p, "rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise ProfileError(f"profile.toml: {e}")
    except UnicodeDecodeError:
        raise ProfileError("profile.toml isn't UTF-8 text")


def own_tables(schema):
    """The sub-tables a module's settings use themselves (login in "login.blur", defaults in "defaults.*")."""
    return {k.split(".", 1)[0] for k in (schema or {}).get("keys", {}) if "." in k}


def split_tags(sec, data, schema):
    """A section -> (its untagged settings, {tag: settings}) in file order."""
    own = own_tables(schema)
    base, tags = {}, {}
    for k, v in data.items():
        if isinstance(v, dict) and k not in own:
            if k == "all":
                raise ProfileError(f"profile.toml: [{sec}.all]: 'all' is not a tag name (--tags all means every tag)")
            tags[k] = v
        else:
            base[k] = v
    return base, tags


def merge(into, extra):
    """Lay a tag's settings over a section: lists add on (no repeats), tables merge, other values replace.
    A single value and a list add up too (file = "a.ini" with a tag's file = ["b.ini"] -> both)."""
    for k, v in extra.items():
        cur = into.get(k)
        if isinstance(cur, list) != isinstance(v, list) and all(isinstance(x, (list, str)) for x in (cur, v)):
            cur, v = (cur if isinstance(cur, list) else [cur]), (v if isinstance(v, list) else [v])
            into[k] = cur + [x for x in v if x not in cur]
        elif isinstance(cur, list) and isinstance(v, list):
            into[k] = cur + [x for x in v if x not in cur]
        elif isinstance(cur, dict) and isinstance(v, dict):
            merge(cur, v)
        else:
            into[k] = copy.deepcopy(v)


def wanted_tags():
    return [x.strip() for x in os.environ.get("DECAL_TAGS", "").split(",") if x.strip()]


def resolve(sec, data, schema, tags):
    """The settings a section has with these tags -> (settings, present). tags: names, or ["all"]."""
    base, mine = split_tags(sec, data, schema)
    present = bool(base) or not mine          # an empty [section] is in the profile too
    vals = copy.deepcopy(base)
    for t in mine if "all" in tags else [t for t in tags if t in mine]:
        merge(vals, mine[t]); present = True
    return vals, present


def all_tags(prof, modules):
    seen = []
    for sec, data in prof.items():
        if isinstance(data, dict):
            for t in split_tags(sec, data, load_schema(modules, sec))[1]:
                if t not in seen: seen.append(t)
    return seen


def leaves(d, prefix=""):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from leaves(v, f"{prefix}{k}.")
        else:
            yield f"{prefix}{k}", v


def get(d, dotted):
    cur = d
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def empty_for(t):
    return [] if t in ("strings", "string-or-strings", "install", "paths") else ""


def check(sec, key, spec, v, pdir):
    t = spec["type"]

    def bad(msg):
        raise ProfileError(f"profile.toml: [{sec}] {key}: {msg}, got {v!r}")

    if t in RULES:   # name, formula, theme, relpath, ref, glob, font ("" is allowed: it means "not set")
        if v != "" and not rule_ok(t, v): bad(f"expected {expected(t, v)}")
        return v
    if t in ("names", "formulas", "globs"):
        if not (isinstance(v, list) and all(isinstance(x, str) for x in v)): bad("expected a list of strings")
        for x in v:
            if not rule_ok(t[:-1], x):
                raise ProfileError(f"profile.toml: [{sec}] {key}: {x!r}: expected {expected(t[:-1], x)}")
        return v
    if t == "globs-or-glob":
        return check(sec, key, dict(spec, type="globs"), [v] if isinstance(v, str) else v, pdir)
    if t == "url":
        if not (isinstance(v, str) and v.startswith("https://") and " " not in v): bad("expected an https:// link")
        return v
    if t in ("string",):
        if not isinstance(v, str): bad("expected a string")
        return v
    if t == "int":
        if isinstance(v, bool) or not isinstance(v, int): bad("expected an integer")
        if "min" in spec and v < spec["min"]: bad(f"must be >= {spec['min']}")
        if "max" in spec and v > spec["max"]: bad(f"must be <= {spec['max']}")
        return v
    if t == "number":   # integer or decimal, e.g. a display scale of 1.5
        if isinstance(v, bool) or not isinstance(v, (int, float)): bad("expected a number")
        if "min" in spec and v < spec["min"]: bad(f"must be >= {spec['min']}")
        if "max" in spec and v > spec["max"]: bad(f"must be <= {spec['max']}")
        return v
    if t == "bool":
        if not isinstance(v, bool): bad("expected true or false")
        return v
    if t == "enum":
        if v not in spec["values"]: bad("expected one of " + ", ".join(repr(x) for x in spec["values"]))
        return v
    if t == "color":
        if not (isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v)): bad("expected a colour like '#deddda'")
        return v
    if t == "strings":
        if not (isinstance(v, list) and all(isinstance(x, str) for x in v)): bad("expected a list of strings")
        return v
    if t == "string-or-strings":
        return [v] if isinstance(v, str) else check(sec, key, dict(spec, type="strings"), v, pdir)
    if t == "install":   # "all", or the theme names to install
        if v == "all": return ["all"]
        check(sec, key, dict(spec, type="strings"), v, pdir)
        for x in v:
            if not rule_ok("theme", x):
                raise ProfileError(f"profile.toml: [{sec}] {key}: {x!r}: expected {RULES['theme']}")
        return v
    if t == "path":
        if not isinstance(v, str): bad("expected a path")
        if v == "": return ""
        p = v if os.path.isabs(v) else os.path.join(pdir, v)
        if not os.path.exists(p): bad(f"file not found ({p})")
        real, root = os.path.realpath(p), os.path.realpath(pdir)
        if real != root and not real.startswith(root + os.sep):
            bad("must be a file inside the profile folder")
        return os.path.abspath(p)
    if t == "paths":   # one file or a list of them (a tag's list adds files on)
        vs = [v] if isinstance(v, str) else v
        if not (isinstance(vs, list) and all(isinstance(x, str) for x in vs)): bad("expected a path or a list of paths")
        return [check(sec, key, dict(spec, type="path"), x, pdir) for x in vs]
    if t in ("path-or-url", "source"):
        if not isinstance(v, str): bad("expected a string")
        if v == "": return ""
        if v.startswith("https://") or (t == "source" and SOURCE_RE.match(v)): return v
        if t == "source" and v.startswith(("git+", "github-release:")):
            bad("unrecognized source (use git+https://…, github-release:owner/repo, https://…, or a path in the profile)")
        return check(sec, key, dict(spec, type="path"), v, pdir)
    raise ProfileError(f"schema: unknown type {t!r} for [{sec}] {key}")


def section_values(sec, schema, data, pdir, present):
    keys = schema.get("keys", {})
    wild = [k[:-1] for k in keys if k.endswith(".*")]          # "defaults." prefixes
    if present:
        def in_table(path):   # a key of a "name.*" table (it may contain dots itself, e.g. a file name)
            for w in wild:
                tbl = get(data, w[:-1])
                if path.startswith(w) and isinstance(tbl, dict) and path[len(w):] in tbl:
                    return True
            return False
        for path, _ in leaves(data):
            if path in keys or in_table(path):
                continue
            known = ", ".join(sorted(keys))
            raise ProfileError(f"profile.toml: [{sec}] unknown key '{path}' (known: {known})")
        for r in schema.get("required", []):
            if get(data, r) is None:
                raise ProfileError(f"profile.toml: [{sec}] missing required key '{r}'")
    vals = {}
    for k, spec in keys.items():
        if k.endswith(".*"):
            name = k[:-2]
            tbl = (get(data, name) if present else None) or {}
            if not isinstance(tbl, dict):
                raise ProfileError(f"profile.toml: [{sec}] {name} must be a table")
            if spec.get("key"):   # the table's keys themselves (e.g. file names under a config folder)
                for n in tbl:
                    if not rule_ok(spec["key"], n):
                        raise ProfileError(f"profile.toml: [{sec}] {name}: {n!r}: expected {RULES[spec['key']]}")
            vals[name] = {n: check(sec, f"{name}.{n}", spec, v, pdir) for n, v in tbl.items()}
            continue
        v = get(data, k) if present else None
        if v is None:
            d = spec.get("default", empty_for(spec["type"]))
            if spec["type"] in ("string-or-strings", "install", "paths") and isinstance(d, str):
                d = [d]
            vals[k] = d
        else:
            vals[k] = check(sec, k, spec, v, pdir)
    return vals


def sh_name(k):
    return "P_" + re.sub(r"[.-]", "_", k)


def emit(vals, present):
    out = [f"declare -g P__in_profile={'true' if present else 'false'}"]
    for k, v in vals.items():
        n = sh_name(k)
        if isinstance(v, dict):
            items = " ".join(f"[{shlex.quote(a)}]={shlex.quote(str(b))}" for a, b in v.items())
            out.append(f"unset {n}; declare -gA {n}=({items})")
        elif isinstance(v, list):
            out.append(f"declare -ga {n}=({' '.join(shlex.quote(str(x)) for x in v)})")
        elif isinstance(v, bool):
            out.append(f"declare -g {n}={'true' if v else 'false'}")
        else:
            out.append(f"declare -g {n}={shlex.quote(str(v))}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["check", "sections", "shell", "tags"])
    ap.add_argument("module", nargs="?")
    ap.add_argument("--profile", required=True)
    ap.add_argument("--modules", required=True)
    ap.add_argument("--defaults", action="store_true", help="ignore the profile: schema defaults only (remove/status fallback)")
    ap.add_argument("--drop", metavar="TAG", help="shell: only the list items TAG adds (remove --only TAG)")
    a = ap.parse_args()
    try:
        if a.cmd == "check" and not os.path.exists(os.path.join(a.profile, "profile.toml")):
            raise ProfileError(f"no profile.toml in {a.profile}")
        prof = {} if a.defaults else load_profile(a.profile)
        names = module_names(a.modules)
        with_schema = [n for n in names if load_schema(a.modules, n) is not None]
        for sec, data in prof.items():
            # only `check` (the gate the runner calls before add/apply) rejects unknown sections;
            # shell/sections read a single module and must not depend on the others
            if sec not in with_schema and a.cmd == "check":
                raise ProfileError(f"profile.toml: unknown section [{sec}] (modules: {', '.join(with_schema)})")
            if not isinstance(data, dict):
                raise ProfileError(f"profile.toml: [{sec}] must be a table")
        tags = wanted_tags()
        if a.cmd == "check":
            # every tag is checked, whichever are picked: the untagged settings, and each tag laid over them
            for sec, data in prof.items():
                schema = load_schema(a.modules, sec)
                base, mine = split_tags(sec, data, schema)
                if base or not mine:
                    section_values(sec, schema, base, a.profile, True)
                for t in mine:
                    section_values(f"{sec}.{t}", schema, resolve(sec, data, schema, [t])[0], a.profile, True)
            for t in tags:
                if t != "all" and t not in all_tags(prof, a.modules):
                    known = ", ".join(all_tags(prof, a.modules)) or "none"
                    raise ProfileError(f"no section of the profile has the tag '{t}' (tags in the profile: {known})")
        elif a.cmd == "sections":
            for n in names:
                if n in prof and resolve(n, prof[n], load_schema(a.modules, n), tags)[1]:
                    print(n)
        elif a.cmd == "tags":
            # tags MODULE: the tags that section has; tags: every tag in the profile
            if a.module:
                print("\n".join(split_tags(a.module, prof.get(a.module, {}), load_schema(a.modules, a.module))[1]))
            else:
                print("\n".join(all_tags(prof, a.modules)))
        else:
            schema = load_schema(a.modules, a.module)
            if schema is None:
                print("declare -g P__in_profile=true")
                return
            data = prof.get(a.module, {})
            if a.drop:
                # remove --only TAG: just what the tag adds to the section's lists (what to take away again)
                base, mine = split_tags(a.module, data, schema)
                which = list(mine) if a.drop == "all" else [t for t in [a.drop] if t in mine]
                added = resolve(a.module, data, schema, which)[0]
                drop = {k: [x for x in v if x not in base.get(k, [])] for k, v in added.items()
                        if isinstance(v, list) and any(k in mine[t] for t in which)}
                vals = section_values(a.module, schema, {}, a.profile, False)   # defaults, then the lists
                vals.update({k: check(a.module, k, schema["keys"][k], v, a.profile) for k, v in drop.items()})
                print(emit(vals, True))
                return
            vals, present = resolve(a.module, data, schema, tags) if a.module in prof else ({}, False)
            print(emit(section_values(a.module, schema, vals, a.profile, present), present))
    except ProfileError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
