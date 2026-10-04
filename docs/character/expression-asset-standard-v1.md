# Expression Asset Standard v1

## Channels and Presets

Face は `ExpressionController` から Eyes / Eyebrows / Mouth を独立変更できる。

- required presets: `normal`, `angry`, `smile`
- existing presets: `sad`, `surprised`
- individual examples: `eyes=blink`, `eyebrows=confident`, `mouth=open`

同じ Face resource を使う個体でも expression state は独立する。Mesh、base texture、shader は共有し、表情 parameter を持つ Face `ShaderMaterial` のみ個体ごとに複製する。表情変更時に mesh / texture / shader を再生成しない。

## Atlas Contract

| atlas | rows | resolution | cell |
|---|---:|---|---|
| `eyes_atlas.svg` | 8 | 256×2048 | 256×256 |
| `eyebrows_atlas.svg` | 6 | 256×1536 | 256×256 |
| `mouth_atlas.svg` | 7 | 256×1792 | 256×256 |

- transparent alpha
- padding 0（各 feature は cell 内側へ十分な余白を持つ）
- Godot import: lossless、mipmap off、linear filtering
- atlas row order と `ExpressionController` の定数配列順を一致させる。

## Hair Isolation

サイズ統一後のlegacy Face001〜006は、GLBに記録した`legacy_size007_NNN` profileで
投影範囲も同じ倍率へ変換する。[顎幅基準](face-size-jaw.md)を参照。

新規Faceの専用UV／mask契約は [Face Expression Rendering v2](face-expression-rendering-v2.md)。UV0はbase color、UV2は表情、COLOR.rは許可mask。Legacy profile／APIは保持する。

新規 Face は `Head*` material のみに expression atlas を設定し、`Hair*` material を除外する。これにより前髪へ目・眉・口が投影される問題を構造的に防ぐ。001〜006 の combined surface は legacy compatibility として従来の正面・法線・depth mask を使う。

## Toon Look

- shared shader: `assets/characters/_shared/materials/character_toon.gdshader`
- metallic 0、roughness 1、specular 0
- source base color は sRGB
- source normal map は現行 toon runtime では使用しない。
- outline / shadow / expression の最終判定は SRPG camera distance で行う。

