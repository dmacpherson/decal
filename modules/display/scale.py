#!/usr/bin/env python3
"""scale.py get | plan STATE SCALE | apply CONFIG
Set every monitor's scale through Mutter's DisplayConfig D-Bus API (what GNOME Settings and gdctl use).
  get                 print the current state as JSON
  plan STATE SCALE    print the layout with every monitor at SCALE (or the closest scale it supports),
                      keeping the arrangement (rows side by side, rows stacked); {"unchanged": true} if nothing to do
  apply CONFIG        apply a layout persistently (like Settings' "Apply")
DECAL_DISPLAY_FAKE=FILE (tests): get reads FILE, apply writes FILE.applied instead of talking to Mutter."""
import json, os, sys

FAKE = os.environ.get("DECAL_DISPLAY_FAKE")
NAME, PATH = "org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig"


def bus():
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    return Gio, GLib, Gio.bus_get_sync(Gio.BusType.SESSION)


def get():
    if FAKE:
        with open(FAKE) as f:
            return json.load(f)
    Gio, GLib, b = bus()
    serial, monitors, logical, props = b.call_sync(NAME, PATH, NAME, "GetCurrentState", None, None, 0, -1, None).unpack()
    mons = {}
    for spec, modes, _ in monitors:
        for m in modes:
            if m[6].get("is-current"):
                mons[spec[0]] = {"mode": m[0], "w": m[1], "h": m[2], "scales": list(m[5])}
    lms = [{"x": x, "y": y, "scale": s, "transform": t, "primary": p, "monitors": [c[0] for c in ms]}
           for x, y, s, t, p, ms, _ in logical]
    return {"serial": serial, "layout_mode": props.get("layout-mode", 1), "monitors": mons, "logical": lms}


def plan(state, want):
    mons, out, notes = state["monitors"], [], []
    def size(lm, scale):
        m = mons[lm["monitors"][0]]
        w, h = (m["h"], m["w"]) if lm["transform"] % 2 else (m["w"], m["h"])
        return (w, h) if state.get("layout_mode", 1) == 2 else (round(w / scale), round(h / scale))
    rows = {}
    for lm in sorted(state["logical"], key=lambda l: (l["y"], l["x"])):
        rows.setdefault(lm["y"], []).append(lm)
    y = 0
    for _, row in sorted(rows.items()):
        x, height = 0, 0
        for lm in row:
            ok = set.intersection(*(set(round(s, 4) for s in mons[c]["scales"]) for c in lm["monitors"]))
            exact = [s for s in mons[lm["monitors"][0]]["scales"] if round(s, 4) in ok]
            scale = min(exact, key=lambda s: abs(s - want))
            if abs(scale - want) > 0.01:
                notes.append(f"{'+'.join(lm['monitors'])} can't do {want}: using {round(scale, 4)}")
            w, h = size(lm, scale)
            out.append(dict(lm, x=x, y=y, scale=scale))
            x += w; height = max(height, h)
        y += height
    unchanged = all(abs(a["scale"] - b["scale"]) < 1e-6 and a["x"] == b["x"] and a["y"] == b["y"]
                    for a, b in zip(sorted(state["logical"], key=lambda l: (l["y"], l["x"])), out))
    for n in notes:
        print(n, file=sys.stderr)
    return {"unchanged": True} if unchanged else {"serial": state["serial"], "logical": out}


def apply(cfg, state):
    if FAKE:
        with open(FAKE + ".applied", "w") as f:
            json.dump(dict(cfg, persistent=True), f)
        return
    Gio, GLib, b = bus()
    missing = [c for lm in cfg["logical"] for c in lm["monitors"] if c not in state["monitors"]]
    if missing:
        sys.exit(f"monitors not connected: {', '.join(missing)}")
    lms = [(lm["x"], lm["y"], lm["scale"], lm["transform"], lm["primary"],
            [(c, state["monitors"][c]["mode"], {}) for c in lm["monitors"]]) for lm in cfg["logical"]]
    args = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (state["serial"], 2, lms, {}))
    b.call_sync(NAME, PATH, NAME, "ApplyMonitorsConfig", args, None, 0, -1, None)


def main():
    cmd = sys.argv[1]
    try:
        state = get()
    except Exception as e:
        sys.exit(f"no GNOME display information ({e})")
    if cmd == "get":
        print(json.dumps(state))
    elif cmd == "plan":
        with open(sys.argv[2]) as f:
            print(json.dumps(plan(json.load(f), float(sys.argv[3]))))
    elif cmd == "apply":
        with open(sys.argv[2]) as f:
            apply(json.load(f), state)


if __name__ == "__main__":
    main()
