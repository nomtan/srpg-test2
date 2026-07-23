"""Reduce transparent AI-authored tall-grass sprites for Godot runtime use."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE_DIR = Path(__file__).resolve().parent / "grass_overlay_sources"
ASSET_DIR = ROOT / "assets" / "terrain" / "reference"
SIZE = 128
PADDING = 4


def fit_visible_source(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{path} contains no visible grass")
    image = image.crop(bbox)
    available = SIZE - PADDING * 2
    scale = min(available / image.width, available / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x = (SIZE - resized.width) // 2
    y = SIZE - PADDING - resized.height
    canvas.alpha_composite(resized, (x, y))
    return canvas


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for index in range(1, 4):
        source = SOURCE_DIR / f"tall_grass_rgba_{index:02d}.png"
        output = ASSET_DIR / f"tall_grass_{index:02d}.png"
        image = fit_visible_source(source)
        alpha = image.getchannel("A")
        final = image.quantize(
            colors=28,
            method=Image.Quantize.FASTOCTREE,
            dither=Image.Dither.NONE,
        ).convert("RGBA")
        final.putalpha(alpha.point(lambda value: 0 if value < 48 else value))
        final.save(output)
        print(f"wrote {output}")


if __name__ == "__main__":
    main()
