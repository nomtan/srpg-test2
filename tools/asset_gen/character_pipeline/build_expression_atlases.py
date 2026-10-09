"""Build transparent vector atlases for the three independent face channels.

Each 256x256 row is a complete face-space overlay. SVG imports as Texture2D in
Godot; rows and their order are the public ExpressionController asset contract.

The art follows the chibi anime finish of the Tripo reference head
`assets/characters/tripo/paical/sample/model.glb`: tall rounded warm-gray irises
split into a dark upper and light lower tone with tiny catch-lights, a thick
near-flat dark-brown upper lash hooking down at the outer corner, white corners
fading into the skin (no lower lid line), a faint lid crease, faint thin brows,
and a tiny soft mouth. Proportions are measured against the eye spacing (100).
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DESTINATION = ROOT / "assets/characters/_shared/face/expression"
LASH = "#3f2a29"
CREASE = "#c98a72"
BROW = "#a8735f"
MOUTH = "#b06e5c"
MOUTH_INSIDE = "#7a3633"
TONGUE = "#d9817c"
SCLERA = "#fdf1ea"
PUPIL = "#45394a"
IRIS_RIM = "#463a43"
# Two-tone cel iris: dark band under the lash, mid tone, hard step to the light lower half.
IRIS_STOPS = (
    ("0.15", "#3a2f35"),
    ("0.32", "#54474e"),
    ("0.54", "#5f535a"),
    ("0.58", "#8d8385"),
    ("1", "#a69c9a"),
)
# Features are authored on the 256 grid below, then shrunk toward FEATURE_ANCHOR
# so they sit inside the skin area instead of spanning the full head width.
FEATURE_SCALE = 0.72
FEATURE_ANCHOR = (128, 128)
# Strokes shrink less than the shapes (effective width = authored * sqrt(scale))
# so lines stay legible at SRPG camera distance.
STROKE = FEATURE_SCALE ** -0.5
# The left eye is authored around EYE_X; the right one is its mirror about x=128.
EYE_X = 78
EYE_Y = 132
BROW_Y = 84
MOUTH_Y = 181
# Our faces are wider than the reference head, so eyes scale up about their centre.
EYE_SIZE = 1.1


def path(d, width=6, color=LASH, fill="none", opacity=1.0):
    alpha = f' opacity="{opacity}"' if opacity < 1.0 else ""
    return (
        f'<path d="{d}" stroke="{color}" stroke-width="{width * STROKE:.2f}" stroke-linecap="round" '
        f'stroke-linejoin="round" fill="{fill}"{alpha}/>'
    )


def fill(d, color, opacity=1.0):
    alpha = f' opacity="{opacity}"' if opacity < 1.0 else ""
    return f'<path d="{d}" fill="{color}"{alpha}/>'


def mirrored(left, size=1.0):
    if size != 1.0:
        left = f'<g transform="translate({EYE_X} {EYE_Y}) scale({size}) translate({-EYE_X} {-EYE_Y})">{left}</g>'
    return f"<g>{left}</g><g transform=\"translate(256 0) scale(-1 1)\">{left}</g>"


def gradient(name, y1, y2, stops):
    return (
        f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1:.1f}" x2="0" y2="{y2:.1f}">'
        + "".join(f'<stop offset="{o}" stop-color="{c}"{"" if a == 1 else f" stop-opacity=\"{a}\""}/>' for o, c, a in stops)
        + "</linearGradient>"
    )


def open_eye(row, inner=0.0, outer=0.0, top=0.0, bottom=0.0, iris_scale=1.0):
    """Left eye with lid offsets in authored units (positive = down).

    inner/outer move the lid corners, top lowers the lid apex (narrowing the
    opening) and bottom moves the lower edge. iris_scale < 1 shows more white.
    """
    x, y = EYE_X, EYE_Y
    ix, iy = x + 20, y - 20 + inner  # inner corner (toward the nose)
    ox, oy = x - 24, y - 21 + outer  # outer corner
    apex = y - 30 + top + (inner + outer) / 2
    low = y + 20 + bottom
    # The opening's top edge is the lash's bottom edge so the iris tucks under it.
    opening = (
        f"M{ix} {iy} Q{x - 1} {apex} {ox} {oy} "
        f"C{ox} {low - 19} {x - 14} {low} {x + 3} {low} C{x + 14} {low} {ix} {low - 16} {ix} {iy} Z"
    )
    iris_w, iris_h = 28 * iris_scale, 54 * iris_scale
    cx = x + 3
    bottom_y = low - (0 if iris_scale >= 1 else 6)
    top_y = bottom_y - iris_h
    # Surprised eyes keep solid whites; otherwise they fade into the skin below.
    sclera_fade = 1.0 if iris_scale < 1 else 0.0
    defs = (
        f'<defs><clipPath id="eye{row}"><path d="{opening}"/></clipPath>'
        + gradient(f"iris{row}", top_y, bottom_y, [(o, c, 1) for o, c in IRIS_STOPS])
        + gradient(f"sclera{row}", min(iy, oy), low - 6, [("0", SCLERA, 1), ("0.55", SCLERA, 0.9), ("1", SCLERA, sclera_fade)])
        + "</defs>"
    )
    iris = (
        f'<rect x="{cx - iris_w / 2:.1f}" y="{top_y:.1f}" width="{iris_w:.1f}" height="{iris_h:.1f}" '
        f'rx="{iris_w / 2 - 1:.1f}" fill="url(#iris{row})" stroke="{IRIS_RIM}" stroke-width="1.6" stroke-opacity="0.75"/>'
        f'<ellipse cx="{cx}" cy="{top_y + iris_h * 0.45:.1f}" rx="{4.5 * iris_scale:.1f}" ry="{8 * iris_scale:.1f}" fill="{PUPIL}" opacity="0.85"/>'
        f'<circle cx="{cx - 6 * iris_scale:.1f}" cy="{top_y + iris_h * 0.33:.1f}" r="{1.7 * iris_scale:.1f}" fill="white" opacity="0.9"/>'
        f'<circle cx="{cx + 6 * iris_scale:.1f}" cy="{top_y + iris_h * 0.62:.1f}" r="1.1" fill="white" opacity="0.6"/>'
    )
    lash_top = apex - 16
    # Thick near-flat lash: lid curve, a downward hook past the outer corner,
    # then back along the upper edge to a tapered inner end.
    lash = (
        f"M{ix + 1} {iy + 1} Q{x - 1} {apex} {ox} {oy} "
        f"L{ox - 2} {oy + 7} Q{ox - 4} {oy + 2} {ox - 6} {oy - 1} "
        f"Q{x - 2} {lash_top} {ix + 3} {iy - 6} Q{ix + 4} {iy - 2} {ix + 1} {iy + 1} Z"
    )
    crease = f"M{x + 10} {apex - 13} Q{x - 4} {apex - 18} {x - 16} {apex - 11}"
    return defs + mirrored(
        fill(opening, f"url(#sclera{row})")
        + f'<g clip-path="url(#eye{row})">{iris}</g>'
        + fill(lash, LASH)
        + path(crease, 1.5, CREASE, opacity=0.6),
        EYE_SIZE,
    )


def closed_eye(curve):
    """A thick lash-coloured closing line."""
    return mirrored(path(curve, 5.5, LASH), EYE_SIZE)


def eyes(style, row):
    x, y = EYE_X, EYE_Y
    if style == "normal":
        return open_eye(row)
    if style == "surprised":
        return open_eye(row, top=-4, bottom=2, iris_scale=0.8)
    if style == "angry":
        return open_eye(row, inner=10, outer=-2, top=7)
    if style == "sad":
        return open_eye(row, inner=-6, outer=9, top=5)
    if style == "narrow":
        return open_eye(row, inner=8, outer=8, top=15, bottom=-4)
    if style == "blink":
        return closed_eye(f"M{x + 20} {y - 4} Q{x} {y + 6} {x - 24} {y - 6} L{x - 28} {y}")
    if style == "closed_strong":
        # Tightly shut: ">" / "<" chevrons pointing toward the nose.
        return closed_eye(f"M{x - 17} {y - 14} L{x + 15} {y - 2} L{x - 17} {y + 10}")
    if style == "happy":
        return closed_eye(f"M{x + 20} {y + 2} Q{x} {y - 20} {x - 24} {y} L{x - 28} {y + 5}")
    raise ValueError(style)


# Left brow (outer end first); long, thin and faint like the reference.
EYEBROW_PATHS = {
    "normal": f"M54 {BROW_Y + 2} Q78 {BROW_Y - 3} 100 {BROW_Y - 2}",
    "angry": f"M54 {BROW_Y - 5} Q80 {BROW_Y - 3} 100 {BROW_Y + 8}",
    "sad": f"M54 {BROW_Y + 7} Q80 {BROW_Y + 1} 99 {BROW_Y - 8}",
    "worried": f"M54 {BROW_Y + 5} Q82 {BROW_Y - 9} 99 {BROW_Y - 4}",
    "surprised": f"M54 {BROW_Y - 3} Q78 {BROW_Y - 14} 100 {BROW_Y - 9}",
    "confident": f"M54 {BROW_Y} Q78 {BROW_Y - 4} 100 {BROW_Y + 2}",
}


def eyebrows(style, row):
    return mirrored(path(EYEBROW_PATHS[style], 2.6, BROW, opacity=0.9))


def mouth(style, row):
    y = MOUTH_Y
    if style == "laugh":
        shape = f"M118 {y - 3} Q128 {y} 138 {y - 3} Q137 {y + 11} 128 {y + 12} Q119 {y + 11} 118 {y - 3} Z"
        return (
            f'<defs><clipPath id="m{row}"><path d="{shape}"/></clipPath></defs>'
            + fill(shape, MOUTH_INSIDE)
            + f'<g clip-path="url(#m{row})"><ellipse cx="128" cy="{y + 13}" rx="7" ry="5" fill="{TONGUE}"/></g>'
        )
    if style == "open":
        return fill(f"M128 {y - 4} C133 {y - 4} 134 {y + 8} 128 {y + 8} C122 {y + 8} 123 {y - 4} 128 {y - 4} Z", MOUTH_INSIDE) + (
            f'<ellipse cx="128" cy="{y + 5}" rx="3" ry="2" fill="{TONGUE}"/>'
        )
    # The neutral mouth is a tiny, slightly turned-down stroke like the reference.
    shapes = {
        "normal": f"M123.5 {y + 1} Q128 {y - 1.5} 132.5 {y + 1}",
        "smile": f"M120 {y - 2} Q128 {y + 6} 136 {y - 2}",
        "angry": f"M121 {y + 3} Q124.5 {y - 1} 128 {y + 1} Q131.5 {y - 1} 135 {y + 3}",
        "sad": f"M121 {y + 3} Q128 {y - 4} 135 {y + 3}",
        "smirk": f"M122 {y + 1} Q130 {y + 3} 136 {y - 3}",
    }
    return path(shapes[style], 2.4, MOUTH)


def write_atlas(kind, names, draw):
    ax, ay = FEATURE_ANCHOR
    shrink = f"translate({ax} {ay}) scale({FEATURE_SCALE}) translate({-ax} {-ay})"
    rows = [
        f'<g transform="translate(0 {index * 256}) {shrink}">{draw(name, index)}</g>' for index, name in enumerate(names)
    ]
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="{len(names) * 256}" '
        f'viewBox="0 0 256 {len(names) * 256}">\n' + "\n".join(rows) + "\n</svg>\n"
    )
    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / f"{kind}_atlas.svg").write_text(svg, encoding="utf-8")


def main():
    write_atlas("eyes", ["normal", "blink", "closed_strong", "angry", "sad", "surprised", "narrow", "happy"], eyes)
    write_atlas("eyebrows", list(EYEBROW_PATHS), eyebrows)
    write_atlas("mouth", ["normal", "smile", "laugh", "open", "angry", "sad", "smirk"], mouth)


if __name__ == "__main__":
    main()
