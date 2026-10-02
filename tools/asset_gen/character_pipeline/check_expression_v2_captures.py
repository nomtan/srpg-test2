"""Check deterministic fixture hair occlusion after capture_expression_v2.gd."""
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[3]
folder = ROOT / "artifacts/phase5_fixture_captures"
normal = Image.open(folder / "front_normal.png").convert("RGB")
# Interior of the authored Hair rectangle, away from antialiased boundaries.
hair_region = (90, 100, 310, 285)
for preset in ("angry", "smile", "sad", "surprised"):
    current = Image.open(folder / f"front_{preset}.png").convert("RGB")
    if ImageChops.difference(normal.crop(hair_region), current.crop(hair_region)).getbbox() is not None:
        raise AssertionError(f"Expression leaked into Hair: {preset}")
    if ImageChops.difference(normal, current).getbbox() is None:
        raise AssertionError(f"Visible Head expression did not change: {preset}")
    print(f"PASS: {preset}: Hair unchanged, visible Head changes")
