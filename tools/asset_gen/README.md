# tools/asset_gen

## Windows setup

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-asset-gen.txt
```

`bpy` and `bmesh` are bundled with Blender and are intentionally not included in the requirements file.

## Grass props

```powershell
python tools\asset_gen\gen_grass_props.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_grass_props.py -- `
  --tex assets\texture\grass --out assets\props\grass
```

Both output directories are created automatically. `--out` may be supplied to the PNG generator to choose another directory.

## Jungle log block

```powershell
python tools\asset_gen\gen_jungle_log_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_jungle_log_block.py -- `
  --tex assets\texture\jungle_log --out assets\props\log
```

This creates `jungle_log_end_01.png`, `jungle_log_side_01.png`, and a one-cell
`prop_jungle_log_block_01.glb`. The top and bottom use the end-grain texture; all
four vertical faces use the bark texture.

## Oak log block

```powershell
python tools\asset_gen\gen_oak_log_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_oak_log_block.py -- `
  --tex assets\texture\oak_log --out assets\props\log
```

This creates `oak_log_end_01.png`, `oak_log_side_01.png`, and
`prop_oak_log_block_01.glb`. Oak uses a lighter palette and vertical bark grain
to remain visually distinct from `jungle_log`.

## Acacia log block

```powershell
python tools\asset_gen\gen_acacia_log_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_acacia_log_block.py -- `
  --tex assets\texture\acacia_log --out assets\props\log
```

This creates `acacia_log_end_01.png`, `acacia_log_side_01.png`, and
`prop_acacia_log_block_01.glb`. Acacia uses terracotta-orange heartwood and
dark gray-brown vertical bark.

## Stone brick family

```powershell
python tools\asset_gen\gen_stone_brick_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_stone_brick_assets.py -- `
  --tex assets\texture\stone_bricks --out assets\props\stone_bricks
```

This generates `stone_brick`, `infested_cracked_stone_bricks`, and
`chiseled_stone_brick` cube GLBs plus the two-step `stone_brick_stairs` GLB.

## Bricks and cobblestone

```powershell
python tools\asset_gen\gen_brick_cobblestone_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_brick_cobblestone_assets.py -- `
  --tex assets\texture\masonry --out assets\props\masonry
```

This generates `bricks`, `brick_stairs`, `cobblestone`, and
`cobblestone_stairs` as one-cell GLB assets.

## Leaf blocks

```powershell
python tools\asset_gen\gen_leaves_textures.py

& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
  --python tools\asset_gen\build_leaves_blocks.py -- `
  --tex assets\texture\leaves --out assets\props\leaves
```

This generates alpha-clipped `oak_leaves` and `acacia_leaves` cube GLBs.

Phase16-Step2の地形アセット生成パイプライン。`palette.json` の色定義だけを唯一の
真実とし、テクスチャ・GLBのどちらもコマンド一発で再生成できる。

## 実行コマンド

```bash
python tools/asset_gen/gen_terrain_textures.py

"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/asset_gen/build_terrain_glb.py -- --tex assets/terrain/textures --out assets/terrain
```

1. `gen_terrain_textures.py`: `palette.json` を読み込み、32×32のシームレスな地形テクスチャ
   （grass / dirt / stone / water / lava）を `assets/terrain/textures/` に出力する。
2. `build_terrain_glb.py`: 生成済みテクスチャを読み込み、`docs/asset/map_asset_standard.md`
   / `docs/dev/phase16-step2.md` の原点・厚み規格に沿ったGLBを `assets/terrain/` に出力する。

## パレットを変更したい場合

`palette.json` の色コードを編集して上記2コマンドを再実行するだけでよい。個別テクスチャの
手修正はしない（規格書のポリシーに合わせる）。

## 出力後の確認

Godotエディタで各GLBをインポートし、`docs/asset/map_texture_standard.md` 6章の通り
Filter: Nearest / Mipmaps: OFF / Compress: Lossless になっているか目視確認すること。
