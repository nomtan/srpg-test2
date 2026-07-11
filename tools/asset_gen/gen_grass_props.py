"""prop用 草テクスチャ生成 (32x32 RGBA, アルファ2値)
tools/asset_gen/ に統合する想定のプロトタイプ。
パレットは palette.json の grass 系 + 穂先用の明色2色(palette追加提案)。
"""
from random import Random
from PIL import Image

SIZE = 32

# 現行 palette.json の grass + 穂先アクセント(追加提案: grass_prop_tip)
GRASS = ["#3c5c2e", "#476b35", "#2f4a24", "#547a3d", "#284020", "#5c8449"]
TIPS = ["#6b9455", "#7aa661"]  # 穂先のみ使用

def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def gen_grass(path, seed, blade_count, h_min, h_max, offshoot_p):
    rng = Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()

    def put(x, y, color):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            px[x, y] = (*hex2rgb(color), 255)

    def blade(x, height):
        y = SIZE - 1
        top = SIZE - 1 - height
        while y >= top:
            t = (SIZE - 1 - y) / max(height, 1)   # 0=根本, 1=穂先
            if t > 0.75 and rng.random() < 0.5:
                color = rng.choice(TIPS)
            elif t > 0.45:
                color = rng.choice(GRASS[1::2])   # 中間は明るめ寄り
            else:
                color = rng.choice(GRASS[::2])    # 根本は暗め寄り
            put(x, y, color)
            if t < 0.3 and rng.random() < 0.6:    # 根本を太らせる
                put(x + rng.choice([-1, 1]), y, rng.choice(GRASS[::2]))
            if rng.random() < 0.22:               # 折れ(キンク)
                x += rng.choice([-1, 1])
            if rng.random() < offshoot_p and t > 0.3:  # 枝分かれの小葉
                put(x + rng.choice([-1, 1]), y - 1, rng.choice(GRASS))
            y -= 1

    for _ in range(blade_count):
        x = rng.randint(2, SIZE - 3)
        # 中央に寄せる(参考画像の密度分布)
        x = (x + SIZE // 2) // 2 if rng.random() < 0.4 else x
        blade(x, rng.randint(h_min, h_max))

    img.save(path)
    print("wrote", path)

# 背の短い草: 密で低い
gen_grass("/home/claude/props/prop_grass_short_01.png", seed=11,
          blade_count=22, h_min=8, h_max=17, offshoot_p=0.10)
# 背の長い草: 疎で高い、枝分かれ多め
gen_grass("/home/claude/props/prop_grass_tall_01.png", seed=23,
          blade_count=14, h_min=20, h_max=30, offshoot_p=0.18)