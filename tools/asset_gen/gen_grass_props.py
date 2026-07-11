"""Generate the two 32x32 RGBA grass prop textures."""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "grass"
SIZE = 32

PROPS = (
    ("prop_grass_short_01.png", 11, 22, 8, 17, 0.10),
    ("prop_grass_tall_01.png", 23, 14, 20, 30, 0.18),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def generate_grass(
    path: Path,
    grass: list[str],
    tips: list[str],
    seed: int,
    blade_count: int,
    h_min: int,
    h_max: int,
    offshoot_p: float,
) -> None:
    rng = Random(seed)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()

    def put(x: int, y: int, color: str) -> None:
        if 0 <= x < SIZE and 0 <= y < SIZE:
            pixels[x, y] = (*hex_to_rgb(color), 255)

    def blade(x: int, height: int) -> None:
        y = SIZE - 1
        top = SIZE - 1 - height
        while y >= top:
            t = (SIZE - 1 - y) / max(height, 1)
            if t > 0.75 and rng.random() < 0.5:
                color = rng.choice(tips)
            elif t > 0.45:
                color = rng.choice(grass[1::2])
            else:
                color = rng.choice(grass[::2])
            put(x, y, color)
            if t < 0.3 and rng.random() < 0.6:
                put(x + rng.choice([-1, 1]), y, rng.choice(grass[::2]))
            if rng.random() < 0.22:
                x += rng.choice([-1, 1])
            if rng.random() < offshoot_p and t > 0.3:
                put(x + rng.choice([-1, 1]), y - 1, rng.choice(grass))
            y -= 1

    for _ in range(blade_count):
        x = rng.randint(2, SIZE - 3)
        x = (x + SIZE // 2) // 2 if rng.random() < 0.4 else x
        blade(x, rng.randint(h_min, h_max))

    image.save(path)


def main() -> None:
    args = parse_args()
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    grass = palette["grass"]
    tips = palette["grass_prop_tip"]

    for filename, seed, count, h_min, h_max, offshoot_p in PROPS:
        output_path = out_dir / filename
        generate_grass(output_path, grass, tips, seed, count, h_min, h_max, offshoot_p)
        try:
            display_path = output_path.relative_to(Path.cwd())
        except ValueError:
            display_path = output_path
        print(f"wrote {display_path}")


if __name__ == "__main__":
    main()
