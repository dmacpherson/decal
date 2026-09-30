#!/usr/bin/env python3
"""Print the canvas layout for the GDM stage: {"width","height","rects":[[x,y,w,h],...]}.
Reads Mutter DisplayConfig (logical layout), or --from-json [{"x","y","w","h","scale"}] (w/h = mode pixels)."""
import json, sys
MAX_W = 16384

def canvas(mons):
    S = max(m["scale"] for m in mons)
    rects = []
    for m in mons:
        lw, lh = m["w"] / m["scale"], m["h"] / m["scale"]
        rects.append([m["x"] * S, m["y"] * S, lw * S, lh * S])
    minx = min(r[0] for r in rects); miny = min(r[1] for r in rects)
    W = max(r[0] + r[2] for r in rects) - minx; H = max(r[1] + r[3] for r in rects) - miny
    k = min(1.0, MAX_W / W)
    out = [[round((r[0] - minx) * k), round((r[1] - miny) * k), round(r[2] * k), round(r[3] * k)] for r in rects]
    return {"width": round(W * k), "height": round(H * k), "rects": out}

def from_mutter():
    from gi.repository import Gio
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    r = bus.call_sync("org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig",
                      "org.gnome.Mutter.DisplayConfig", "GetCurrentState", None, None, 0, -1, None)
    _serial, monitors, logical, _props = r.unpack()
    modes = {}
    for (spec, mlist, _p) in monitors:
        for mode in mlist:
            if mode[6].get("is-current"):
                modes[spec[0]] = (mode[1], mode[2])
    mons = []
    for (x, y, scale, transform, _primary, specs, _p) in logical:
        w, h = modes[specs[0][0]]
        if transform in (1, 3, 5, 7): w, h = h, w
        mons.append({"x": x, "y": y, "w": w, "h": h, "scale": scale})
    return mons

if __name__ == "__main__":
    mons = json.loads(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == "--from-json" else from_mutter()
    print(json.dumps(canvas(mons)))
