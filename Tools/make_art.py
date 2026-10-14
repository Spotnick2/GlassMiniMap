"""Generate Glass MiniMap's own textures into Media/ (never hand-edit the outputs).

    python Tools/make_art.py

The panel and disc material belong to LibGlass-1.0 (its Media/, its
generator). Only this addon's own art is made here, with the library
generator's primitives (SDF, bands, TGA writer) from the LibGlass checkout
($LIBGLASS, else ../LibGlass), so it is the same material:

  orb_mask               the round hover light on the discs and pill buttons
  ring_rim / ring_dark   the lit lip around the map: the outer edge of the
                         glass ring and a fine line where it meets the map.
                         Perimeter only: the centre is clear, because these
                         draw ABOVE the map (g.top is host level + 10).
  ring_runes             optional etched rune band, fitted outside the map
  ring_runes_glow        soft halo around the rune glyphs
  ring_bloom             neutral rim light, tinted by the active theme in game
  ring_fog               broken wisps within the same annulus
  notch_mask / notch_rim the glass tab at 12 o'clock that carries the "N"
  sun / moon / magnifier icons, white with the shape in alpha (tinted in game)

Conventions (LibGlass's): overlays are one RGB colour with the shape in
alpha, masks are white-on-black in RGB and alpha, power-of-two sizes.
Requires Pillow-free numpy only (the writer is LibGlass's).
"""

import math
import os
import random
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
# The round hover light (a full antialiased disc)
# ---------------------------------------------------------------------------

ORB = 64


def orbs():
    write_tga("orb_mask", mask(coverage(rounded_rect_sdf(ORB, ORB, 0.5, ORB / 2.0 - 0.5))))


# ---------------------------------------------------------------------------
# The ring's lip (512 px; drawn at ~218 px, so 1 texture px ~ 0.43 screen px)
# ---------------------------------------------------------------------------

RING = 512
MOVING_RUNE_COUNT = 16  # brighter moving glyphs need more space than the engraving


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


def rune_band(circles=True, count=28, dots=True):
    """Portal Roulette's seed-7 glyphs, fitted to this ring; no Pillow needed.

    Distance-based soft strokes at 2x retain the etched look at minimap size.
    The radial window leaves room for filtering when the client rotates it.
    """
    scale = 2
    xs, ys = grid(RING * scale)
    xs, ys = xs / scale - RING / 2, ys / scale - RING / 2
    radius = np.hypot(xs, ys)
    inner, outer = RING / 2 * INNER + 3.5, RING / 2 - 5
    mid = (inner + outer) / 2
    height = (outer - inner) * 0.62
    alpha = np.zeros_like(radius)

    def stroke(distance, opacity):
        # A soft edge around a 1.8 texture-pixel stroke, like the source art.
        nonlocal alpha
        alpha = np.maximum(alpha, np.clip((1.5 - distance) / 1.2, 0, 1) * opacity)

    if circles:
        for r, opacity in ((inner, 150 / 255), (outer, 150 / 255)):
            stroke(np.abs(radius - r), opacity)
    rng = random.Random(7)
    points = [(x, y) for y in (-0.5, 0, 0.5) for x in (-0.5, 0, 0.5)]
    for i in range(count):
        angle = 2 * math.pi * i / count
        ux, uy = math.cos(angle), math.sin(angle)
        vx, vy = -uy, ux
        for _ in range(rng.randint(3, 5)):
            a, b = rng.sample(points, 2)
            ax = ux * mid + (a[0] * vx * 0.7 + a[1] * ux) * height
            ay = uy * mid + (a[0] * vy * 0.7 + a[1] * uy) * height
            bx = ux * mid + (b[0] * vx * 0.7 + b[1] * ux) * height
            by = uy * mid + (b[0] * vy * 0.7 + b[1] * uy) * height
            dx, dy = bx - ax, by - ay
            t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / (dx * dx + dy * dy), 0, 1)
            stroke(np.hypot(xs - ax - t * dx, ys - ay - t * dy), 230 / 255)
        if dots:
            dot = angle + math.pi / count
            stroke(np.hypot(xs - math.cos(dot) * mid, ys - math.sin(dot) * mid) - 0.7, 170 / 255)
    alpha[(radius < RING / 2 * INNER + 2) | (radius > RING / 2 - 3)] = 0
    return alpha.reshape(RING, scale, RING, scale).mean(axis=(1, 3))


def rune_glow():
    """A tight blue-light halo around glyphs, not the bounding circles."""
    alpha = rune_band(circles=False, count=MOVING_RUNE_COUNT, dots=False)
    offsets = np.arange(-9, 10)
    kernel = np.exp(-0.5 * (offsets / 3.0) ** 2)
    kernel /= kernel.sum()
    for axis in (0, 1):
        alpha = np.apply_along_axis(lambda row: np.convolve(row, kernel, mode="same"), axis, alpha)
    xs, ys = grid(RING)
    radius = np.hypot(xs - RING / 2, ys - RING / 2)
    # Fade before the map and texture edge, including a filtering margin.
    window = np.clip((radius - (RING / 2 * INNER + 2)) / 2, 0, 1)
    window *= np.clip((RING / 2 - 3 - radius) / 2, 0, 1)
    return np.clip(alpha * 7, 0, 1) * window


def ring_fog():
    """Cold vapor outside the glass, fading away over 18 UI pixels."""
    xs, ys = grid(RING)
    dx, dy = xs - RING / 2, ys - RING / 2
    radius, angle = np.hypot(dx, dy), np.arctan2(dy, dx)
    host_size = MAP_SIZE + 2 * RING_WIDTH
    fog_padding = 18  # Ring.FOG_PADDING
    lo = RING / 2 * host_size / (host_size + 2 * fog_padding) + 2
    hi = RING / 2 - 3
    radial = (radius - lo) / (hi - lo)
    # Integer angular frequencies join seamlessly at the texture's left edge.
    bend = radial + 0.2 * np.sin(5 * angle + 3 * radial) + 0.1 * np.sin(9 * angle + 1)
    wisps = np.exp(-((bend - 0.35) / 0.23) ** 2)
    wisps += 0.5 * np.exp(-((bend - 0.65) / 0.16) ** 2)
    gaps = (0.5 + 0.5 * np.sin(7 * angle + 2 * np.sin(3 * angle) + 5 * radial)) ** 2
    window = np.sin(np.pi * np.clip(radial, 0, 1)) ** 2
    window[(radius <= lo) | (radius >= hi)] = 0
    return np.clip(wisps * gaps * window, 0, 1)


def ring_bloom():
    """Uneven light patches and neutral falloff, on a host with 18px padding."""
    xs, ys = grid(RING)
    host_size = MAP_SIZE + 2 * RING_WIDTH
    units = (host_size + 36) / RING
    radius = np.hypot(xs - RING / 2, ys - RING / 2) * units
    rim_radius = host_size / 2 - 1
    distance = radius - rim_radius
    core = np.exp(-(distance / 1.4) ** 2)
    halo = np.exp(-(distance / 8.0) ** 2)
    angle = np.arctan2(ys - RING / 2, xs - RING / 2)
    # Irregular bright sectors travel with the glyphs. A uniform annulus
    # looked like a neon tube in the owner's comparison video.
    lobes = 0.5 + 0.5 * np.sin(3 * angle + 0.7 * np.sin(2 * angle + 0.8))
    patches = 0.08 + 0.92 * lobes ** 3
    detail = 0.7 + 0.3 * (0.5 + 0.5 * np.sin(11 * angle + 2 * np.sin(5 * angle)))
    # Keep the map clear and fade to zero before the square texture boundary.
    window = np.clip((radius - (MAP_SIZE / 2 + 0.75)) / 1.5, 0, 1)
    window *= np.clip(((host_size + 36) / 2 - 1 - radius) / 3, 0, 1)
    return white(np.clip(core * 0.85 + halo * 0.7, 0, 1) * window * patches * detail)


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
    write_tga("ring_runes", white(rune_band()))
    write_tga("ring_runes_moving", white(rune_band(circles=False, count=MOVING_RUNE_COUNT, dots=False)))
    write_tga("ring_runes_glow", white(rune_glow()))
    write_tga("ring_fog", white(ring_fog()))
    write_tga("ring_bloom", ring_bloom())
    notch()
    sun()
    moon()
    magnifier()


if __name__ == "__main__":
    main()
