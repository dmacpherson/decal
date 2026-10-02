"""python3 assets/logo.py assets : decal's logo (an iridescent die-cut Tux sticker, one corner peeling) and the
1280x640 social preview card. The penguin is drawn here from shapes, after Larry Ewing's Tux. Render the card to
assets/social-preview.png with any browser (e.g. headless Chromium --screenshot) after changing it."""
import math, sys
W = 512
# --- Tux, drawn fresh (shapes) -------------------------------------------------
def tux_body(body):
    return f'''
  <ellipse cx="150" cy="300" rx="34" ry="92" transform="rotate(22 150 300)" fill="{body}"/>
  <ellipse cx="362" cy="300" rx="34" ry="92" transform="rotate(-22 362 300)" fill="{body}"/>
  <ellipse cx="256" cy="298" rx="118" ry="148" fill="{body}"/>
  <circle cx="256" cy="168" r="86" fill="{body}"/>'''

def tux_details():
    return '''
  <ellipse cx="256" cy="322" rx="84" ry="116" fill="url(#belly)"/>
  <ellipse cx="229" cy="160" rx="28" ry="38" fill="#ffffff"/>
  <ellipse cx="283" cy="160" rx="28" ry="38" fill="#ffffff"/>
  <ellipse cx="236" cy="168" rx="11" ry="16" fill="#191826"/>
  <ellipse cx="276" cy="168" rx="11" ry="16" fill="#191826"/>
  <circle cx="240" cy="161" r="4" fill="#ffffff"/>
  <circle cx="280" cy="161" r="4" fill="#ffffff"/>
  <ellipse cx="256" cy="219" rx="34" ry="13" fill="#e8890c"/>
  <ellipse cx="256" cy="206" rx="44" ry="17" fill="url(#beak)"/>
  <ellipse cx="192" cy="446" rx="64" ry="26" transform="rotate(-6 192 446)" fill="url(#beak)"/>
  <ellipse cx="320" cy="446" rx="64" ry="26" transform="rotate(6 320 446)" fill="url(#beak)"/>'''

def silhouette(fill, stroke_w):
    s = f'fill="{fill}" stroke="{fill}" stroke-width="{stroke_w}" stroke-linejoin="round"'
    return f'''
  <ellipse cx="150" cy="300" rx="34" ry="92" transform="rotate(22 150 300)" {s}/>
  <ellipse cx="362" cy="300" rx="34" ry="92" transform="rotate(-22 362 300)" {s}/>
  <ellipse cx="256" cy="298" rx="118" ry="148" {s}/>
  <circle cx="256" cy="168" r="86" {s}/>
  <ellipse cx="192" cy="446" rx="64" ry="26" transform="rotate(-6 192 446)" {s}/>
  <ellipse cx="320" cy="446" rx="64" ry="26" transform="rotate(6 320 446)" {s}/>'''

# --- the peel: fold along a line, the cut-off part reflected over the sticker ---
P = (215.0, 540.0); Q = (500.0, 290.0)          # fold line (bottom-right corner of the sticker)
dx, dy = Q[0]-P[0], Q[1]-P[1]; n = math.hypot(dx, dy); ux, uy = dx/n, dy/n
R = [[2*ux*ux-1, 2*ux*uy], [2*ux*uy, 2*uy*uy-1]]
tx = P[0] - (R[0][0]*P[0] + R[0][1]*P[1]); ty = P[1] - (R[1][0]*P[0] + R[1][1]*P[1])
reflect = f"matrix({R[0][0]:.6f} {R[1][0]:.6f} {R[0][1]:.6f} {R[1][1]:.6f} {tx:.3f} {ty:.3f})"
far = 2000
# keep = the side of the line with the sticker's centre; cut = the corner beyond it
keep = f"M {P[0]-ux*far} {P[1]-uy*far} L {P[0]+ux*far} {P[1]+uy*far} L {-far} {-far} Z"
cut = f"M {P[0]-ux*far} {P[1]-uy*far} L {P[0]+ux*far} {P[1]+uy*far} L {far} {far} Z"

holo = '''
    <linearGradient id="holo" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffb3e6"/><stop offset=".22" stop-color="#c9b6ff"/>
      <stop offset=".45" stop-color="#9ff0ff"/><stop offset=".68" stop-color="#c8ffb0"/>
      <stop offset=".85" stop-color="#fff0a8"/><stop offset="1" stop-color="#ffb3e6"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="1" y2=".8">
      <stop offset="0" stop-color="#ff40a0" stop-opacity=".55"/><stop offset=".35" stop-color="#7a5cff" stop-opacity=".45"/>
      <stop offset=".6" stop-color="#22d3ee" stop-opacity=".45"/><stop offset=".85" stop-color="#84ff6a" stop-opacity=".35"/>
      <stop offset="1" stop-color="#ff40a0" stop-opacity=".5"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="1" y2="1">
      <stop offset=".30" stop-color="#fff" stop-opacity="0"/><stop offset=".40" stop-color="#fff" stop-opacity=".55"/>
      <stop offset=".46" stop-color="#fff" stop-opacity="0"/><stop offset=".56" stop-color="#fff" stop-opacity="0"/>
      <stop offset=".60" stop-color="#fff" stop-opacity=".3"/><stop offset=".64" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="back" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#f4f4f8"/><stop offset=".6" stop-color="#dcdce6"/><stop offset="1" stop-color="#b9b9c8"/>
    </linearGradient>
    <linearGradient id="belly" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#eae6f5"/>
    </linearGradient>
    <linearGradient id="beak" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd23f"/><stop offset="1" stop-color="#ff9f1c"/></linearGradient>
    <filter id="drop" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#1a1030" flood-opacity=".35"/></filter>
    <filter id="flapshadow" x="-30%" y="-30%" width="160%" height="160%"><feOffset dx="0" dy="0"/><feGaussianBlur stdDeviation="6"/></filter>'''

def sticker(size_attr=""):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {W} {W}"{size_attr}>
  <defs>{holo}
    <clipPath id="keep"><path d="{keep}"/></clipPath>
    <clipPath id="cut"><path d="{cut}"/></clipPath>
  </defs>
  <g clip-path="url(#keep)">
    <g filter="url(#drop)">{silhouette("url(#holo)", 40)}</g>
    {tux_body("#191826")}
    <g style="mix-blend-mode:screen">{tux_body("url(#sheen)")}</g>
    {tux_details()}
    <g opacity=".75">{silhouette("url(#shine)", 40)}</g>
  </g>
  <!-- the peeled-up corner: the back of the sticker, folded over -->
  <g transform="{reflect}">
    <g clip-path="url(#cut)" filter="url(#flapshadow)" opacity=".5">{silhouette("#1a1030", 40)}</g>
    <g clip-path="url(#cut)">{silhouette("url(#back)", 40)}</g>
  </g>
</svg>
'''

out = sys.argv[1]
open(f"{out}/logo.svg", "w").write(sticker())
# social preview 1280x640: sticker + wordmark on a dark card
card = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640">
  <defs>
    <radialGradient id="bg" cx=".3" cy=".4" r="1"><stop offset="0" stop-color="#2a1745"/><stop offset="1" stop-color="#0d0a18"/></radialGradient>
    <linearGradient id="word" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ff7ac6"/><stop offset=".35" stop-color="#b79cff"/><stop offset=".7" stop-color="#7ee8fa"/><stop offset="1" stop-color="#b8ff9a"/>
    </linearGradient>
  </defs>
  <rect width="1280" height="640" fill="url(#bg)"/>
  {sticker().replace('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox', '<svg x="100" y="70" width="500" height="500" viewBox')}
  <text x="640" y="330" font-family="Inter, Cantarell, 'DejaVu Sans', sans-serif" font-weight="800" font-size="168" fill="url(#word)" letter-spacing="-4">decal</text>
  <text x="646" y="400" font-family="Inter, Cantarell, 'DejaVu Sans', sans-serif" font-size="32" fill="#cfc6e8">Stick your Linux setup onto any machine.</text>
  <text x="646" y="446" font-family="Inter, Cantarell, 'DejaVu Sans', sans-serif" font-size="32" fill="#cfc6e8">Peel it off cleanly.</text>
</svg>
'''
open(f"{out}/social.svg", "w").write(card)
