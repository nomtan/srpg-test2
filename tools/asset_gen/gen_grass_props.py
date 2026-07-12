"""prop用 草テクスチャ生成 v2 (32x32 RGBA, アルファ2値)
改良点:
- 葉を2〜4px幅のテーパー形状に(根本太く穂先細く)
- 暗/中間/明の3段階シェーディング(左=暗、右=明で疑似ライティング)
- 根本中心から扇状に広がる「株」シルエット
- 短草/中草/長草 × 各2シードの6バリアント
"""
import argparse
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "grass"
SIZE = 32

DARK = ["#36552b", "#3d6030"]
MID = ["#4a7038", "#568042", "#63904b"]
LIGHT = ["#4a7038", "#568042", "#63904b"]  # 穂先・ハイライト

def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def gen(path, seed, blade_count, h_min, h_max, base_w):
    rng = Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()

    def put(x, y, color):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            px[x, y] = (*hex2rgb(color), 255)

    def blade(x0, height, lean):
        """テーパー付きの1葉。leanで曲がり方向と強さを指定"""
        drift = 0.0
        for step in range(height + 1):
            t = step / max(height, 1)          # 0=根本, 1=穂先
            drift += lean * 0.35 + rng.uniform(-0.25, 0.25)
            cx = int(round(x0 + drift))
            y = SIZE - 1 - step
            w = max(1, round(base_w * (1.0 - t * 0.75)))
            # 3段階シェーディング: 左端=暗 / 中央=中間 / 右端=明
            for i in range(w):
                x = cx + i - w // 2
                if t > 0.8:                     # 穂先は明色
                    c = rng.choice(LIGHT)
                elif w >= 3:
                    c = DARK[step % 2] if i == 0 else (rng.choice(LIGHT) if i == w - 1 else rng.choice(MID))
                elif w == 2:
                    c = rng.choice(DARK) if i == 0 else rng.choice(MID + LIGHT)
                else:
                    c = rng.choice(MID)
                put(x, y, c)

    # 株シルエット: 根本を中心付近に集め、外側の葉ほど外に倒す
    center = SIZE // 2
    for k in range(blade_count):
        offset = rng.randint(-6, 6)
        x0 = center + offset
        lean = (offset / 6.0) * rng.uniform(0.5, 1.0)   # 外側ほど外向きに曲がる
        h = rng.randint(h_min, h_max)
        # 外側の葉は少し低く(ドーム状の株形)
        h = max(h_min, h - abs(offset))
        blade(x0, h, lean)

    img.save(path)
    print("wrote", path)

VARIANTS = {
    # name: (seed, blades, h_min, h_max, base_w)
    "prop_grass_short_01": (11, 13, 8, 14, 3),
    "prop_grass_short_02": (12, 13, 8, 14, 3),
    "prop_grass_short_03": (13, 13, 8, 14, 3),
    "prop_grass_mid_01":   (21, 8, 14, 21, 3),
    "prop_grass_mid_02":   (22, 8, 14, 21, 3),
    "prop_grass_mid_03":   (23, 8, 14, 21, 3),
    "prop_grass_tall_01":  (31, 7, 20, 29, 4),
    "prop_grass_tall_02":  (32, 7, 20, 29, 4),
}

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main():
    args = parse_args()
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, (seed, bc, h0, h1, bw) in VARIANTS.items():
        gen(out_dir / f"{name}.png", seed, bc, h0, h1, bw)


if __name__ == "__main__":
    main()
