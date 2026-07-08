# Phase16-Step2: 手続き生成アセットパイプラインのGodot組み込み

## 目的

テクスチャ手続き生成（32×32ピクセル）＋ヘッドレスBlenderによるGLB量産のパイプラインを
リポジトリに組み込み、生成した本番アセット（grass / dirt / stone / water / lava）を
既存のMapVisualTheme / VoxelMap経由で表示できるようにする。

## 前提

- Phase15のジオラマ表示基盤（MapRenderer / VoxelMap / MapVisualTheme）が動作している
- 生成スクリプトの雛形が存在する:
  - `gen_terrain_textures_32.py`（32×32テクスチャ生成）
  - `build_terrain_glb.py`（GLB量産・ヘッドレスBlender用）
- テクスチャ規格は `docs/asset/map_texture_standard.md` に従う

## 重要: 現行コードとの規格すり合わせ（最初に必ず行う）

`scripts/map/voxel_map.gd` の実装を確認した結果、アセット規格は以下に合わせる必要がある。

| 項目 | 現行コードの仕様 | 対応 |
|---|---|---|
| 1セル | 1.0m × 1.0m（`GridSystem.CELL_SIZE`） | スクリプトの `CELL = 1.0` のままで良い |
| 1段の高さ | **1.0m**（`top.position.y = float(cell.height)`） | `STEP_H = 1.0` に修正する |
| 上面パーツの原点 | **上面がY=0**（cell.heightの高さに上面が来る。フォールバック実装は薄板を原点から下方向に配置） | build_terrain_glb.py を「上面がZ=0、メッシュは下方向に伸びる」原点に修正する |
| 上面パーツの厚み | フォールバックは0.12〜0.2の薄板＋崖側面は別パーツ | 上面キューブの厚みは `TOP_THICKNESS = 0.2` とする（フルキューブにしない。崖はcliff_sideの仕事） |
| 水面 | `WATER_LAYER` に配置、上面から沈む | water/lavaプレーンは上面から` SURFACE_OFFSET = 0.08` 下げた位置（原点基準で Z = -0.08） |
| 崖側面 | 1.0×1.0の縦パネルを面法線方向 `normal * 0.495` に配置 | 本Stepでは対象外（Step3で実装）。当面は既存フォールバック崖を使用 |

## 作業内容

### 1. ツール類の設置

```
tools/asset_gen/
├── palette.json              # 色定義（新規作成。規格書5章の形式）
├── gen_terrain_textures.py   # 雛形から移植し、palette.json読み込みに変更
├── build_terrain_glb.py      # 雛形から移植し、上記規格すり合わせを反映
└── README.md                 # 実行コマンドを記載
```

実行コマンド（README.mdに記載する）:

```bash
python tools/asset_gen/gen_terrain_textures.py
blender --background --python tools/asset_gen/build_terrain_glb.py -- \
    --tex assets/terrain/textures --out assets/terrain
```

### 2. スクリプト修正

- `gen_terrain_textures.py`: 色定義を palette.json 読み込みに変更。出力先を `assets/terrain/textures/` に変更
- `build_terrain_glb.py`:
  - `STEP_H = 1.0`、上面原点（上面がZ=0、下方向に `TOP_THICKNESS` 分伸びる）に修正
  - side面のUVは薄板の厚み分だけ見えるため、テクスチャ上端0.2分を使うようVを調整
  - 出力対象: `terrain_grass_top_01` / `terrain_dirt_top_01` / `terrain_stone_top_01` / `terrain_water_plane_01` / `terrain_lava_plane_01`

### 3. 生成とインポート

- 上記コマンドでテクスチャ→GLBを生成し `assets/terrain/` に配置
- Godotエディタで各GLBのインポート設定を確認:
  - テクスチャFilterがNearestであること（規格書6章）
  - Mipmaps OFF / Compress Lossless
- 各GLBをPackedScene化する（インポート時のシーン設定のままで良い。ルートはNode3D）

### 4. MapVisualThemeの拡張

- `scripts/map/map_visual_theme.gd` に `@export var lava_plane: PackedScene` を追加
- `top_scene_for()` に `"lava": return lava_plane if lava_plane else water_plane` の分岐を追加
- `scripts/map/voxel_map.gd` のlava関連処理を確認し、水面と同様にWATER_LAYER（または専用レイヤー）へ配置されることを確認

### 5. テーマリソースの作成と登録

- `assets/terrain/theme_default.tres`（MapVisualTheme）を作成し、生成した5アセットを登録
- 既存のマップシーンのVoxelMapに `theme_default.tres` を設定

### 6. 動作確認（Phase16AssetPreview）

`Phase16AssetPreview.tscn` を作成（Step1計画のもの）し、以下を確認:

- [ ] 1セルサイズが既存グリッド・ユニット移動とズレていない
- [ ] 高さ1段=1.0mでcell.heightに上面が一致する
- [ ] grass / dirt / stone の上面が正しいテクスチャで表示される
- [ ] water / lava プレーンが上面より僅かに沈んで表示される
- [ ] 高低差のあるセルで既存フォールバック崖と違和感なく接続する
- [ ] ゲーム内カメラ距離でテクスチャのノイズ粒度が適切（粗すぎ/細かすぎの場合は
      palette.json / fbm octavesを調整して再生成）
- [ ] Phase15のサンプルマップが壊れていない

## 完了条件

- `tools/asset_gen/` 一式がリポジトリに存在し、コマンド1発で全アセットを再生成できる
- 生成した5種の本番GLBがMapVisualTheme経由で表示される
- lava地形が専用プレーンで表示される
- Phase16AssetPreviewシーンで上記チェックリストが全て通る
- docs/asset/ に規格書・テンプレートが配置されている

## 本Stepの対象外（次Step候補）

- cliff_side / cliff_corner / stair の本番GLB化（Step3）
- 水・溶岩のUVスクロールシェーダー（Step3）
- prop系アセット（Step4）
