#!/usr/bin/env python3
"""Merge settings into a Brave (Chromium) Preferences file, and take them out again.

  prefs.py apply   PREFS SETTINGS PREV  write SETTINGS' values into PREFS; PREV keeps each one's value from
                                        before decal (recorded the first time only)
  prefs.py status  PREFS SETTINGS       exit 0 if PREFS already has every value
  prefs.py restore PREFS PREV           put PREV's values back; settings that weren't there are removed

SETTINGS is a partial Preferences tree: objects are merged key by key, everything else (numbers, strings,
lists) is a value of its own, so the rest of PREFS is never touched.
"""
import json, os, sys

def leaves(tree, path=()):
    for k, v in tree.items():
        if isinstance(v, dict) and v: yield from leaves(v, path + (k,))
        else: yield path + (k,), v

def get(d, path):
    for k in path:
        if not isinstance(d, dict) or k not in d: return False, None
        d = d[k]
    return True, d

def put(d, path, value):
    for k in path[:-1]: d = d.setdefault(k, {})
    d[path[-1]] = value

def drop(d, path):
    ok, parent = get(d, path[:-1])
    if ok and isinstance(parent, dict): parent.pop(path[-1], None)

def load(p): return json.load(open(p))

def save(p, d):   # atomic, keeps the file's permissions
    tmp = p + '.decal-tmp'
    with open(tmp, 'w') as f: json.dump(d, f, separators=(',', ':'))
    os.chmod(tmp, os.stat(p).st_mode & 0o7777); os.replace(tmp, p)

cmd, prefs_path = sys.argv[1], sys.argv[2]
prefs = load(prefs_path)
if cmd == 'status':
    sys.exit(0 if all(get(prefs, p) == (True, v) for p, v in leaves(load(sys.argv[3]))) else 1)
if cmd == 'apply':
    settings, prev_path = load(sys.argv[3]), sys.argv[4]
    prev = load(prev_path) if os.path.exists(prev_path) else []
    seen = {tuple(r['path']) for r in prev}
    for p, v in leaves(settings):
        if p not in seen:
            had, old = get(prefs, p)
            prev.append({'path': list(p), 'value': old} if had else {'path': list(p), 'absent': True})
        put(prefs, p, v)
    json.dump(prev, open(prev_path, 'w'), indent=1); save(prefs_path, prefs)
elif cmd == 'restore':
    for r in load(sys.argv[3]):
        if r.get('absent'): drop(prefs, tuple(r['path']))
        else: put(prefs, tuple(r['path']), r['value'])
    save(prefs_path, prefs)
else:
    sys.exit(f'unknown command {cmd}')
