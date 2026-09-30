"""Build transparent vector atlases for the three independent face channels.

Each 256x256 row is a complete face-space overlay. SVG imports as Texture2D in
Godot; rows and their order are the public ExpressionController asset contract.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DESTINATION = ROOT / "assets/characters/_shared/face/expression"
INK = "#291b25"
LIGHT = "#f6f0e9"


def path(d, width=6, color=INK, fill="none"):
    return f'<path d="{d}" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" fill="{fill}"/>'


def eyes(style):
    if style in ("blink", "closed_strong", "happy"):
        curve = "M58 104 Q80 112 99 102 M157 102 Q177 112 198 104"
        if style == "happy":
            curve = "M58 108 Q78 83 99 108 M157 108 Q177 83 198 108"
        return path(curve, 7 if style == "closed_strong" else 5)
    if style == "narrow":
        return path("M59 96 Q78 105 98 96 M158 96 Q178 105 197 96", 7)
    if style == "angry":
        return path("M56 91 L100 102 M156 102 L200 91", 9) + path("M66 101 Q78 112 94 104 M162 104 Q178 112 190 101", 4)
    if style == "sad":
        return path("M58 102 Q72 84 99 100 M157 100 Q184 84 198 102", 5)
    radius = 16 if style == "surprised" else 12
    centers = (78, 178)
    return "".join(
        f'<ellipse cx="{x}" cy="100" rx="{radius}" ry="{radius + 7}" fill="{LIGHT}" stroke="{INK}" stroke-width="5"/>'
        f'<ellipse cx="{x}" cy="102" rx="7" ry="11" fill="{INK}"/>'
        f'<circle cx="{x - 3}" cy="95" r="3" fill="white"/>'
        for x in centers
    )


EYEBROW_PATHS = {
    "normal": "M56 59 Q78 49 101 59 M155 59 Q178 49 200 59",
    "angry": "M55 53 L102 71 M154 71 L201 53",
    "sad": "M55 69 L101 52 M155 52 L201 69",
    "worried": "M55 65 Q79 43 102 58 M154 58 Q179 43 201 65",
    "surprised": "M56 48 Q78 34 101 48 M155 48 Q178 34 200 48",
    "confident": "M55 55 Q77 53 101 60 M155 60 Q179 53 201 55",
}


def mouth(style):
    if style == "open" or style == "laugh":
        width, height = (17, 25) if style == "open" else (31, 22)
        return f'<ellipse cx="128" cy="177" rx="{width}" ry="{height}" fill="{INK}"/>' + (
            '<path d="M108 174 Q128 184 148 174" stroke="white" stroke-width="5" fill="none"/>' if style == "laugh" else ""
        )
    shapes = {
        "normal": "M115 177 Q128 181 141 177",
        "smile": "M101 167 Q128 200 155 167",
        "angry": "M108 185 Q128 168 148 185",
        "sad": "M107 190 Q128 165 149 190",
        "smirk": "M105 180 Q130 187 155 166",
    }
    return path(shapes[style], 6)


def write_atlas(kind, names, draw):
    rows = [f'<g transform="translate(0 {index * 256})">{draw(name)}</g>' for index, name in enumerate(names)]
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="{len(names) * 256}" '
        f'viewBox="0 0 256 {len(names) * 256}">\n' + "\n".join(rows) + "\n</svg>\n"
    )
    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / f"{kind}_atlas.svg").write_text(svg, encoding="utf-8")


def main():
    write_atlas("eyes", ["normal", "blink", "closed_strong", "angry", "sad", "surprised", "narrow", "happy"], eyes)
    write_atlas("eyebrows", list(EYEBROW_PATHS), lambda name: path(EYEBROW_PATHS[name], 7))
    write_atlas("mouth", ["normal", "smile", "laugh", "open", "angry", "sad", "smirk"], mouth)


if __name__ == "__main__":
    main()
