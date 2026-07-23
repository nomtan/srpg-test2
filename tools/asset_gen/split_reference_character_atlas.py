"""Split the generated four-character atlas into pixel-art sprites."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE = ROOT / "assets" / "characters" / "generated" / "reference_character_atlas_rgba.png"
OUT_DIR = SOURCE.parent
NAMES = ["char_mercenary", "char_guard", "char_scout", "char_healer"]
MAX_HEIGHT = 172
PADDING = 6


def main() -> None:
    atlas = Image.open(SOURCE).convert("RGBA")
    cell_width = atlas.width // len(NAMES)
    for index, name in enumerate(NAMES):
        cell = atlas.crop((index * cell_width, 0, (index + 1) * cell_width, atlas.height))
        bounds = cell.getchannel("A").getbbox()
        if not bounds:
            raise RuntimeError(f"No opaque pixels in character cell {index}: {name}")
        sprite = cell.crop(bounds)
        scale = min(MAX_HEIGHT / sprite.height, 1.0)
        sprite = sprite.resize(
            (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
            Image.Resampling.NEAREST,
        )
        rgba = sprite.load()
        for y in range(sprite.height):
            for x in range(sprite.width):
                red, green, blue, alpha = rgba[x, y]
                rgba[x, y] = (red, green, blue, 255 if alpha >= 128 else 0)
        padded = Image.new("RGBA", (sprite.width + PADDING * 2, sprite.height + PADDING * 2))
        padded.alpha_composite(sprite, (PADDING, PADDING))
        output = OUT_DIR / f"{name}.png"
        padded.save(output)
        print(f"wrote {output} ({padded.width}x{padded.height})")


if __name__ == "__main__":
    main()
