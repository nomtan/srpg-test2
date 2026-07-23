# 地形タイル・プロップ 棚卸し（Phase17 Step1 Fix F1-1）

`scripts/map/map_visual_theme.gd` の `top_scene_for()` / `decoration_scene_for()` と
`assets/terrain/theme_default.tres` の実際の設定値を突き合わせ、検証シーン
（`flat_validation.tscn`）に出現しうる全タイル・プロップを列挙する。

このリストは `tools/asset_gen/palette.json` の `colors` セクション、および
`scripts/dev/flat_validation.gd` の明示マッピングテーブルが「全種をカバーして
いるか」を照合するための正本として、step2以降も更新して使うこと。

## 地形（`top_scene_for` が返すシーン単位）

複数の `terrain` 文字列が同じアセットにマップされる場合は1行にまとめた
（同一メッシュ・同一マテリアルである以上、見た目は区別できないため、
palette色も1つを共有する）。

| palette key | 対応する `terrain` 文字列 | アセット | 備考 |
|---|---|---|---|
| `grass` | `grass`, `high_ground`（default分岐） | `terrain_grass_top_01.glb` | |
| `dirt` | `dirt`, `forest` | `terrain_dirt_top_01.glb` | |
| `stone` | `stone`, `stone_road`, `rock`, `wall`, `stair` | `terrain_stone_top_01.glb` / `terrain_stair_01.glb` | `terrain_stair_01.glb` は `build_terrain_glb.py` で `terrain_stone_top_01.png` を流用しているため同色 |
| `cliff_side` | （高さ差のある非stone地形の側面） | `terrain_cliff_side_01.glb` | dirt系の崖面 |
| `cliff_side_top` | （高さ差のある地形の側面、grass天面あり） | `terrain_cliff_side_top_01.glb` | grass天面+dirt露出の崖面 |
| `cliff_stone` | （高さ差のあるstone系地形の側面） | `terrain_cliff_stone_01.glb` | stone系の崖面 |
| `water` | `water` | `water_plane.tscn` / `water_side.tscn` | 専用`ShaderMaterial`（`water.gdshader`）を使用しており `flat_terrain_*` へは変換されない。A/B比較の対象外。色定義のみ`palette.json`に一本化 |
| `lava` | `lava` | `lava_plane.tscn` / `lava_side.tscn` | 同上（`lava.gdshader`）。EMISSIONで発光しているため、たとえ変換されても実際には目立たない |
| `bridge` | `bridge` | 未設定（`bridge_floor`/`bridge_top`ともnull） | `_create_fallback_top`のBoxMesh(色`#9b6b3f`直書き)にフォールバック。実アセット未整備 |

## 選択可能ブロック（`SELECTABLE_BLOCK_TERRAINS`）

| palette key | 対応する `terrain` 文字列 | アセット |
|---|---|---|
| `stone_brick` | `stone_brick`, `stone_brick_stairs` | `stone_brick.glb` / `stone_brick_stairs.glb` |
| `infested_cracked_stone_bricks` | `infested_cracked_stone_bricks` | `infested_cracked_stone_bricks.glb` |
| `chiseled_stone_brick` | `chiseled_stone_brick` | `chiseled_stone_brick.glb` |
| `bricks` | `bricks`, `brick_stairs` | `bricks.glb` / `brick_stairs.glb` |
| `cobblestone` | `cobblestone`, `cobblestone_stairs` | `cobblestone.glb` / `cobblestone_stairs.glb` |

## 装飾（`decoration_scene_for`）

| kind | アセット | 扱い |
|---|---|---|
| `grass_short` | `prop_grass_short_01/02/03.tscn` | クロスクワッド植生。`flat_vegetation.gdshader`（F2）で描画。palette色は不要（テクスチャ由来） |
| `grass_tall` | `prop_grass_tall_01.tscn` | 同上 |
| （`grass_mid_01/02/03`） | `voxel_map.gd`の`GRASS_MID_VARIANTS`定数から直接preload | `_create_random_grass`専用。同じくvegetation扱い |
| `jungle_log_column` | `prop_jungle_log_column_06.tscn` | 検証シーン未使用（palette.jsonの`jungle_log`は既存の色配列のまま、`colors`セクション対象外） |
| `oak_log_column` | `prop_oak_log_column_06.tscn` | 同上（`oak_log`） |
| `acacia_log_column` | `prop_acacia_log_column_06.tscn` | 同上（`acacia_log`） |
| `grass_patch`, `broken_stone`, `flag_placeholder` | 未設定（null） | `_make_fallback_decoration`のデバッグ用プレースホルダー形状（色直書き）にフォールバック。実アセット未整備につき検証シーン・palette.jsonの対象外 |

## `flat_validation.gd` 側の扱い

- 地形・選択可能ブロックは `scene_file_path` のファイル名で上記表と照合する
  明示マッピングテーブル（`TERRAIN_ASSET_TO_PALETTE_KEY`）を持つ
- マッピングに存在しないシーン資産に遭遇した場合は **マゼンタ
  （`#FF00FF`）** で描画し、`push_warning()` を出し、UI上の
  `未定義タイル: N件` カウンタを加算する（暗黙のフォールバックはしない）
- `grass_short`/`grass_mid_*`/`grass_tall` は上記マッピングとは別経路で
  検出し、常に `flat_vegetation.gdshader` に差し替える（A/B択一の対象外）
- `water`/`lava` は元々 `ShaderMaterial`（`BaseMaterial3D`ではない）のため
  変換ロジックには到達しない。`palette.json`への色定義は
  「コードへの色ハードコード全廃」の原則を満たすために追加した
- `bridge` および `grass_patch`/`broken_stone`/`flag_placeholder` は
  実アセットが存在しない（デバッグ用フォールバック形状のみ）ため、検証
  シーンのグリッドには含めていない。含める場合は
  `_material_for()`/`_make_fallback_decoration()`が使う色を
  `palette.json`に移すこと（本fixのスコープ外）
