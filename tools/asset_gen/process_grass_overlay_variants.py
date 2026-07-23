"""Prepare transparent, low ground-cover grass decals for the terrain renderer.

The source paintings are chroma-keyed before this script runs.  This stage
only reduces them to the game's pixel density, shares a restrained palette,
and preserves their organic alpha silhouettes.  Tall grass is intentionally
not part of these textures; it is placed as separate map decoration assets.
"""

from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parent.parent.parent
ASSET_DIR = ROOT / "assets" / "terrain" / "reference"
SOURCE_DIR = Path(__file__).resolve().parent / "grass_overlay_sources"
SIZE = 32
SOURCE_PATHS = [
    SOURCE_DIR / f"low_grass_rgba_{index:02d}.png"
    for index in range(1, 5)
]
OUTPUT_PATHS = [
    ASSET_DIR / f"grass_overlay_{index:02d}.png"
    for index in range(1, 5)
]


def square_crop(image: Image.Image) -> Image.Image:
    side = min(image.size)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    return image.crop((left, top, left + side, top + side))


def prepare_source(path: Path) -> Image.Image:
    """Reduce a transparent painting while keeping broad, muted brush marks."""
    image = square_crop(Image.open(path).convert("RGBA"))
    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    rgb = ImageEnhance.Color(image.convert("RGB")).enhance(0.90)
    rgb = ImageEnhance.Contrast(rgb).enhance(0.96)
    alpha = image.getchannel("A").point(
        lambda value: (
            0
            if value < 56
            else 255
            if value > 190
            else round((value - 56) / 134 * 255)
        )
    )
    rgb.putalpha(alpha)
    return rgb


def palette_rgb(image: Image.Image) -> Image.Image:
    """Hide irrelevant transparent RGB from the shared-palette calculation."""
    background = Image.new("RGB", image.size, (166, 181, 102))
    background.paste(image.convert("RGB"), mask=image.getchannel("A"))
    return background


def main() -> None:
    missing = [path for path in SOURCE_PATHS if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing transparent grass sources: {missing}")

    prepared = [prepare_source(path) for path in SOURCE_PATHS]
    palette_sources = [palette_rgb(image) for image in prepared]

    strip = Image.new("RGB", (SIZE * len(prepared), SIZE))
    for index, image in enumerate(palette_sources):
        strip.paste(image, (index * SIZE, 0))
    palette = strip.quantize(
        colors=18,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for path, source, rgb_source in zip(OUTPUT_PATHS, prepared, palette_sources):
        final = rgb_source.quantize(
            palette=palette,
            dither=Image.Dither.NONE,
        ).convert("RGBA")
        final.putalpha(source.getchannel("A"))
        final.save(path)

        alpha = final.getchannel("A")
        visible = sum(value >= 107 for value in alpha.get_flattened_data())
        coverage = visible / (SIZE * SIZE)
        assert coverage < 0.80, f"{path.name} no longer exposes enough soil"
        assert coverage > 0.15, f"{path.name} lost too much grass"
        assert alpha.getextrema()[0] == 0, f"{path.name} is not transparent"
        print(f"wrote {path} (visible grass coverage: {coverage:.1%})")

    print("verified four transparent low-grass decals")


if __name__ == "__main__":
    main()
