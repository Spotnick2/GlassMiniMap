"""Generate Glass MiniMap's own textures into Media/ (never hand-edit the outputs).

    python Tools/make_art.py

The panel and disc material belong to LibGlass-1.0 (its Media/, its
generator). Only this addon's own art is made here, with the library
generator's primitives (SDF, bands, TGA writer) from the LibGlass checkout
($LIBGLASS, else ../LibGlass), so it is the same material:

  orb_mask / orb_rim / orb_dark / orb_shadow   the drawer's round buttons
                                               (Glass MiniMap Bar's orb, unchanged)
  ring_rim / ring_dark   the lit lip around the map: the outer edge of the
                         glass ring and a fine line where it meets the map.
                         Perimeter only: the centre is clear, because these
                         draw ABOVE the map (g.top is host level + 10).
  notch_mask / notch_rim the glass tab at 12 o'clock that carries the "N"
  sun / moon / magnifier icons, white with the shape in alpha (tinted in game)

Conventions (LibGlass's): overlays are one RGB colour with the shape in
alpha, masks are white-on-black in RGB and alpha, power-of-two sizes.
Requires Pillow-free numpy only (the writer is LibGlass's).
"""

import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBGLASS = os.environ.get("LIBGLASS") or os.path.join(os.path.dirname(ROOT), "LibGlass")
sys.path.insert(0, os.path.join(LIBGLASS, "Tools"))
sys.dont_write_bytecode = True   # no __pycache__ in the library checkout (it would read as dirty)
try:
    import make_textures
except ImportError:
    sys.exit(f"LibGlass checkout not found at {LIBGLASS} (no Tools/make_textures.py): "
             "clone github.com/Spotnick2/LibGlass there or set LIBGLASS")
from make_textures import band, black, coverage, mask, normals, rounded_rect_sdf, white, write_tga

# write_tga writes to its module's OUT at call time: point it at our Media/.
make_textures.OUT = os.path.join(ROOT, "Media")

# The ring host is the map plus RING_WIDTH on every side (Ring.lua's numbers):
# where the map's edge falls, as a share of the host's radius.
MAP_SIZE, RING_WIDTH = 198, 10
INNER = MAP_SIZE / (MAP_SIZE + 2 * RING_WIDTH)


def grid(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64) + 0.5
    return xs, ys


# ---------------------------------------------------------------------------
# The orb (Glass MiniMap Bar's Tools/make_orb_textures.py, unchanged)
# ---------------------------------------------------------------------------

ORB = 64


def orb_sdf(inset=0.5):
    return rounded_rect_sdf(ORB, ORB, inset, ORB / 2.0 - inset)


def orb_rim(k, light):
    d = orb_sdf()
    nx, ny = normals(d)
    top, bottom, left = np.maximum(-ny, 0), np.maximum(ny, 0), np.maximum(-nx, 0)
    xs, ys = grid(ORB)
    outer = band(d, -1.4 * k, -0.3 * k, 0.5) * (0.28 + 0.72 * top ** 0.5 + 0.35 * left ** 1.5 + 0.30 * bottom ** 2)
    inner = band(d, -7.6 * k, -6.6 * k, 0.5) * (0.14 + 0.45 * bottom ** 0.7 + 0.18 * top ** 2)
    vert = 1 - ys / ORB
    slab = band(d, -7.0 * k, -0.5 * k, 0.6) * (0.05 + 0.13 * vert ** 1.5 + 0.06 * top)
    glint = np.zeros_like(d)
    c, gr = ORB / 2.0, ORB / 2.0 - 0.5 - 2.0 * k
    for sx in (-1, 1):
        gx, gy = c + sx * gr * 0.7071, c - gr * 0.7071
        glint += np.exp(-(((xs - gx) ** 2 + (ys - gy) ** 2) / (2 * (2.2 * k) ** 2))) * 0.85
    glint *= band(d, -3.5 * k, -0.2 * k, 0.6)
    rim = white(np.clip(np.maximum.reduce([outer, inner, slab, glint]) * light, 0, 1))
    dark = black(np.clip(band(d, -0.6 * k, 0.3 * k, 0.5) * 0.45 + band(d, -8.8 * k, -7.6 * k, 0.6) * 0.18, 0, 1))
    return rim, dark


def orbs():
    write_tga("orb_mask", mask(coverage(orb_sdf())))
    rim, dark = orb_rim(k=1.0, light=0.85)
    write_tga("orb_rim", rim)
    write_tga("orb_dark", dark)
    d = rounded_rect_sdf(ORB, ORB, 12, 20)
    write_tga("orb_shadow", black(0.5 / (1 + np.exp(d / (4.0 * 0.55)))))


# ---------------------------------------------------------------------------
# The ring's lip (512 px; drawn at ~218 px, so 1 texture px ~ 0.43 screen px)
# ---------------------------------------------------------------------------

RING = 512


def ring():
    xs, ys = grid(RING)
    c = RING / 2.0
    R = c - 1.0
    dx, dy = (xs - c) / R, (ys - c) / R           # dy > 0 is DOWN (row 0 = top)
    r = np.hypot(dx, dy)
    light = np.clip((-dx - dy) / math.sqrt(2) / np.maximum(r, 1e-6), 0, 1) ** 0.7   # upper-left
    lower = np.clip(dy / np.maximum(r, 1e-6), 0, 1) ** 2                          # bottom catch
    px = 1.0 / R                                  # one texture pixel, in radius units

    # Outer lip: a crisp lit line just inside the edge, a soft halo under it.
    outer = np.exp(-((r - (1 - 2.5 * px)) / (1.6 * px)) ** 2)
    halo = np.exp(-((r - (1 - 6 * px)) / (6 * px)) ** 2) * 0.12
    # Glints at +-45 degrees from the top, on the outer lip (the mockup's).
    glint = np.zeros_like(r)
    gr = 1 - 4 * px
    for sx in (-1, 1):
        gx, gy = sx * gr * 0.7071, -gr * 0.7071
        glint += np.exp(-(((dx - gx) ** 2 + (dy - gy) ** 2) / (2 * (7 * px) ** 2))) * 0.55
    # Inner lip: a fine line where the glass meets the map, brighter at the
    # bottom (light caught on the far side), so the map reads as set IN the ring.
    inner = np.exp(-((r - (INNER + 1.5 * px)) / (1.3 * px)) ** 2) * (0.22 + 0.55 * lower + 0.2 * light)
    rim = np.clip((outer * (0.18 + 0.82 * light) + halo * (0.3 + 0.7 * light) + glint + inner), 0, 1)
    rim[r > 1.0 + px] = 0
    write_tga("ring_rim", white(rim))

    # Dark hairlines: the outer silhouette, and a soft inset shade on the
    # map's own edge (just inside INNER) so the map sits under the glass.
    dark_outer = np.exp(-((r - (1 - 0.8 * px)) / (1.2 * px)) ** 2) * 0.42
    dark_inner = np.exp(-((r - (INNER - 3 * px)) / (4 * px)) ** 2) * (0.30 + 0.25 * (1 - lower))
    dark = np.clip(dark_outer + dark_inner, 0, 1)
    dark[r > 1.0 + px] = 0
    dark[r < INNER - 14 * px] = 0                 # the map's centre stays untouched
    write_tga("ring_dark", black(dark))


# ---------------------------------------------------------------------------
# The north tab: a peaked glass cap (64x64; the peak at the top)
# ---------------------------------------------------------------------------

NOTCH = 64


def polygon_sdf(xs, ys, pts):
    """Exact signed distance to a convex polygon given clockwise (y down)."""
    inside = np.full(xs.shape, -np.inf)
    outside = np.full(xs.shape, np.inf)
    n = len(pts)
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        ex, ey = x2 - x1, y2 - y1
        L = math.hypot(ex, ey)
        nx, ny = ey / L, -ex / L                   # outward normal
        inside = np.maximum(inside, (xs - x1) * nx + (ys - y1) * ny)
        t = np.clip(((xs - x1) * ex + (ys - y1) * ey) / (L * L), 0, 1)
        outside = np.minimum(outside, np.hypot(xs - (x1 + t * ex), ys - (y1 + t * ey)))
    return np.where(inside <= 0, inside, outside)


def notch():
    """A low peaked roof over the ring's top (64x32), corners rounded."""
    ys, xs = np.mgrid[0:NOTCH // 2, 0:NOTCH].astype(np.float64) + 0.5
    rounding = 3.5
    # The outline shrunk by `rounding`, then grown back: same size, round corners.
    roof = [(3 + rounding * 1.6, 31 - rounding), (32, 3 + rounding * 1.9), (61 - rounding * 1.6, 31 - rounding)]
    d = polygon_sdf(xs, ys, roof) - rounding
    write_tga("notch_mask", mask(coverage(d)))
    nx, ny = normals(d)
    top = np.maximum(-ny, 0)
    lip = band(d, -1.4, -0.3, 0.5) * (0.25 + 0.75 * top ** 0.6)
    slab = band(d, -5, -0.5, 0.7) * 0.07
    # The small solid arrowhead under the peak (the mockup's).
    arrow = coverage(polygon_sdf(xs, ys, [(28.5, 13.5), (32, 8.5), (35.5, 13.5)]) - 0.4, 0.6) * 0.9
    write_tga("notch_rim", white(np.clip(np.maximum.reduce([lip, slab, arrow]), 0, 1)))


# ---------------------------------------------------------------------------
# Icons (64 px, white, shape in alpha)
# ---------------------------------------------------------------------------

ICON = 64


def sun():
    xs, ys = grid(ICON)
    c = ICON / 2.0
    dx, dy = xs - c, ys - c
    r = np.hypot(dx, dy)
    body = coverage(r - 11.5, 0.7)
    ang = np.arctan2(dy, dx)
    rays = np.zeros_like(r)
    for i in range(12):
        a = i * math.pi / 6
        d_ang = np.angle(np.exp(1j * (ang - a)))
        width = 3.2 - 1.8 * np.clip((r - 15) / 13, 0, 1)      # tapering
        ray = coverage(np.abs(d_ang) * r - width / 2, 0.6) * coverage(r - 28.5, 0.7) * (1 - coverage(r - 15, 0.7))
        rays = np.maximum(rays, ray)
    write_tga("sun", white(np.clip(np.maximum(body, rays), 0, 1)))


def moon():
    xs, ys = grid(ICON)
    c = ICON / 2.0
    full = coverage(np.hypot(xs - c, ys - c) - 20, 0.7)
    bite = coverage(np.hypot(xs - (c + 10), ys - (c - 8)) - 17, 0.7)
    write_tga("moon", white(np.clip(full * (1 - bite), 0, 1)))


def magnifier():
    xs, ys = grid(ICON)
    cx, cy, R = 26.0, 26.0, 15.0
    ring = band(np.hypot(xs - cx, ys - cy) - R, -2.6, 2.6, 0.7)
    # Handle: a thick segment from the lens toward the lower right.
    ax, ay = cx + (R + 1) * 0.7071, cy + (R + 1) * 0.7071
    bx, by = 54.0, 54.0
    vx, vy = bx - ax, by - ay
    t = np.clip(((xs - ax) * vx + (ys - ay) * vy) / (vx * vx + vy * vy), 0, 1)
    dist = np.hypot(xs - (ax + t * vx), ys - (ay + t * vy))
    handle = coverage(dist - 4.2, 0.7)
    write_tga("magnifier", white(np.clip(np.maximum(ring, handle), 0, 1)))


def main():
    print("Writing Glass MiniMap textures")
    orbs()
    ring()
    notch()
    sun()
    moon()
    magnifier()


if __name__ == "__main__":
    main()
