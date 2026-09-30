#!/usr/bin/env python3
"""profile.toml reader for decal: validate against modules/<m>/schema.json, emit shell vars."""
import argparse, json, os, re, shlex, sys, tomllib


class ProfileError(Exception):
    pass


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
    return [] if t in ("strings", "string-or-strings", "install") else ""


def check(sec, key, spec, v, pdir):
    t = spec["type"]

    def bad(msg):
        raise ProfileError(f"profile.toml: [{sec}] {key}: {msg}, got {v!r}")

    if t in ("string",):
        if not isinstance(v, str): bad("expected a string")
        return v
    if t == "int":
        if isinstance(v, bool) or not isinstance(v, int): bad("expected an integer")
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
    if t == "install":
        if v == "all": return ["all"]
        return check(sec, key, dict(spec, type="strings"), v, pdir)
    if t == "path":
        if not isinstance(v, str): bad("expected a path")
        if v == "": return ""
        p = v if os.path.isabs(v) else os.path.join(pdir, v)
        if not os.path.exists(p): bad(f"file not found ({p})")
        return os.path.abspath(p)
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
        for path, _ in leaves(data):
            if path in keys or any(path.startswith(w) and "." not in path[len(w):] for w in wild):
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
            vals[name] = {n: check(sec, f"{name}.{n}", spec, v, pdir) for n, v in tbl.items()}
            continue
        v = get(data, k) if present else None
        if v is None:
            d = spec.get("default", empty_for(spec["type"]))
            if spec["type"] in ("string-or-strings", "install") and isinstance(d, str):
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
    ap.add_argument("cmd", choices=["check", "sections", "shell"])
    ap.add_argument("module", nargs="?")
    ap.add_argument("--profile", required=True)
    ap.add_argument("--modules", required=True)
    ap.add_argument("--defaults", action="store_true", help="ignore the profile: schema defaults only (remove/status fallback)")
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
        if a.cmd == "check":
            for sec, data in prof.items():
                section_values(sec, load_schema(a.modules, sec), data, a.profile, True)
        elif a.cmd == "sections":
            for n in names:
                if n in prof:
                    print(n)
        else:
            schema = load_schema(a.modules, a.module)
            if schema is None:
                print("declare -g P__in_profile=true")
                return
            present = a.module in prof
            print(emit(section_values(a.module, schema, prof.get(a.module, {}), a.profile, present), present))
    except ProfileError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
