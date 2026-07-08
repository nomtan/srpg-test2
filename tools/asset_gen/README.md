# tools/asset_gen

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
