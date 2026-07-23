"""Resolve palette.json's "colors" section into the flat-shading value/
saturation band described in docs/dev/phase/phase17-step1.md T6.

Usage:
    python tools/asset_gen/gen_palette_flat.py

Writes tools/asset_gen/palette_resolved.json. palette.json stays the single
hand-edited source; palette_resolved.json is a generated artifact and must
not be hand-edited.

Replaces the earlier ramp-based gen_palette_ramps.py (discarded along with
the cel-shading approach - see the "前提の変更" section at the top of
phase17-step1.md). Only "colors" is resolved here; every other top-level
key (grass, dirt, stone, jungle_log, ...) is copied through unchanged since
those still feed the noise-based texture generators in this step.
"""

import colorsys
import json
from pathlib import Path

PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
RESOLVED_PATH = Path(__file__).resolve().parent / "palette_resolved.json"


def _hex_to_rgb(hex_color: str) -> tuple:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _rgb_to_hex(rgb: tuple) -> str:
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in rgb)


def flatten_color(base_hex: str, saturation_scale: float, value_min: float, value_max: float) -> str:
    r, g, b = _hex_to_rgb(base_hex)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    s = max(0.0, min(1.0, s * saturation_scale))
    v = value_min + v * (value_max - value_min)
    return _rgb_to_hex(colorsys.hsv_to_rgb(h, s, v))


def resolve_colors(colors: dict, flat_params: dict) -> dict:
    saturation_scale = flat_params["saturation_scale"]
    value_min = flat_params["value_range"]["min"]
    value_max = flat_params["value_range"]["max"]
    resolved = {}
    for name, entry in colors.items():
        base = entry["base"]
        resolved[name] = {
            "base": base,
            # Validation palettes may opt specific surfaces out of the common
            # dark value band while keeping the original source color. This is
            # used for the bright grass/dirt art direction; all other buckets
            # continue through the deterministic flattening rule.
            "resolved": entry.get(
                "resolved",
                flatten_color(base, saturation_scale, value_min, value_max),
            ),
        }
    return resolved


def main() -> None:
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    resolved = dict(palette)
    resolved["colors"] = resolve_colors(palette["colors"], palette["flat_params"])
    RESOLVED_PATH.write_text(
        json.dumps(resolved, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"wrote {RESOLVED_PATH}")


if __name__ == "__main__":
    main()
