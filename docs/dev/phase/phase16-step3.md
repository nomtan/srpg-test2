# Phase16-Step3: 崖・階段の本番アセット化と水・溶岩シェーダー

## 目的

Step2で本番化した上面アセットに続き、フォールバック実装のまま残っている
崖側面・階段を本番アセットに置き換え、水・溶岩を動くシェーダー表現にする。
これによりマップの「地形」の見た目要素が一通り本番品質になる。

## 前提

- Phase16-Step2が完了している（tools/asset_gen/ が稼働、上面5アセットが表示済み）
- テクスチャ規格は `docs/asset/map_asset_standard.md` に従う
- レンダラーは GL Compatibility（シェーダーはこの制約内で書く）

## 現行コードの崖仕様（アセットはこれに合わせる）

`scripts/map/voxel_map.gd` の `_create_cliff_sides()` より:

- 崖パネルは高低差1段ごとに1枚生成される（`for level in cell.height - neighbor_height`）
- 配置: セル中心 + 面法線 × 0.495、Y = neighbor_height + level + 0.5（=パネル中心が段の中央）
- 回転: `direction.yaw` によるY軸回転のみ
- フォールバックは 0.96 × 0.96 × 厚み0.08 のBox

したがって **cliff_side GLBの規格**:

- サイズ: 幅1.0 × 高さ1.0 × 厚み0.06〜0.08
- 原点: パネル中心（幅・高さ・厚みすべて中央）
- 向き: フォールバックBoxと同じ向きになるよう、DIRECTIONS定義のyaw値と突き合わせて確認すること
- テクスチャ: 32×32、上下左右シームレス（縦に積まれるため上下の連続が特に重要）

## 作業内容

### 1. 崖テクスチャの追加生成

`texture_request_template.md` の形式で以下を追加する。

- `terrain_cliff_side_01`: 土の地層風。dirtパレットベース + 横方向の層状ノイズ
- `terrain_cliff_side_top_01`: 最上段用。上端に草の垂れ（grass_side同様の処理）、下は地層
- `terrain_cliff_stone_01`: 岩肌。stoneパレット + ひび

palette.json への追加が必要なら行う。

### 2. cliff_side GLBの生成

- `build_terrain_glb.py` のASSETSに、既存の `box` / `plane` に加えて `panel` kindを新設し、
  上記規格のパネルを実装する
- 出力: `terrain_cliff_side_01.glb` / `terrain_cliff_side_top_01.glb` / `terrain_cliff_stone_01.glb`
- マテリアル命名は既存GLBの慣例（`MAT_<name>`）に合わせる

### 3. 最上段だけ草垂れ崖にするコード変更（推奨）

- `MapVisualTheme` に `@export var cliff_side_top: PackedScene` を追加
- `_create_cliff_sides()` のループで、最上段（`level == cell.height - neighbor_height - 1`）のみ
  `cliff_side_top` を使うよう分岐を追加
- cliff_side_top未設定時はcliff_sideにフォールバックすること

### 4. cliff_corner の扱いを決める

- 現行コードで `cliff_corner` スロットが実際に使用されているか確認する
- 未使用であれば本Stepでは対象外とし、status.mdにその旨を記録する（凸角の隙間が
  目視で気になる場合のみ対応を検討）

### 5. 階段の本番化

現行のフォールバック（薄板+5段の小Box、向き固定）を置き換える。

- `terrain_stair_01.glb`: 1.0×1.0フットプリント、上面Y=0原点、下方向に1.0mを
  5段のステップで降りる形状。stoneパレットのテクスチャ
- 注意: 現行実装は階段の向きデータを持たない可能性がある。`MapCellVisualData` を確認し、
  向き情報が無い場合は本Stepでは固定向きのまま置き換え、向き対応は課題として記録する

### 6. 水・溶岩のシェーダー化

水・溶岩はGLBをやめ、**PlaneMesh + ShaderMaterialの.tscn** に変更する
（板ポリにBlenderは不要なため。Step2のGLBは削除して良い）。

- `assets/terrain/materials/water.gdshader`:
  - Step2で生成した water テクスチャを2枚重ねで異速度UVスクロール + 軽い歪み
  - 半透明（alpha 0.8前後）、`render_mode blend_mix`
  - 頂点の上下動はしない（盤面の読みやすさ優先）
- `assets/terrain/materials/lava.gdshader`:
  - lavaテクスチャの低速UVスクロール + 発光（`EMISSION`）
  - EMISSIONはグロー（Step4で有効化）で光らせる前提で 1.5〜2.5 程度
- `water_plane.tscn` / `lava_plane.tscn` を作成し、`assets/terrain/theme_default.tres` の
  `water_plane` / `lava_plane` スロットの参照をGLBから.tscnへ差し替える
- 差し替え後、`terrain_water_plane_01.glb` / `terrain_lava_plane_01.glb` と対応する
  build_terrain_glb.py のplane定義を削除する（planeはBlender経由にしない方針へ変更）
- 現行実装では water は WATER_LAYER、lava は TOP_LAYER に配置される
  （`voxel_map.gd` L34）。lavaもWATER_LAYER相当の扱いにすべきか確認し、
  問題があれば水と同様の分岐を追加する
- GL Compatibilityで動作することを実機確認する

### 6.5. 未使用リソースの掃除

- `assets/map/themes/phase16_theme.tres`（Step1時点のもの）が現在未参照であれば削除する
  （使用中のテーマは `assets/terrain/theme_default.tres`）

### 7. 動作確認

- [ ] 高低差1〜3段の崖が本番テクスチャで表示され、最上段に草垂れが出る
- [ ] 崖パネルの向きが4方向すべて正しい（テクスチャが裏返っていない）
- [ ] 縦に積んだ崖パネルの継ぎ目が目立たない
- [ ] マップ外周のセルで崖が正しく生成されている（空洞が見えない）
- [ ] 階段が本番形状で表示され、ユニットの移動と干渉しない
- [ ] 水面が揺らぎ、溶岩がゆっくり流動して見える
- [ ] FPSが従来と同等（シェーダー起因の低下がない）

## 完了条件

- フォールバック描画（_make_fallback_cliff / _create_fallback_top）が通常マップで使われなくなる
- 崖・階段・水・溶岩がすべて本番アセット/シェーダーで表示される
- 追加アセットがすべて tools/asset_gen/ から再生成可能

## 対象外（次Step以降）

- 色味・トーンの最終調整（Step4）
- prop系アセットの本番化（Step5で最低限、量産は後続）
- 階段の向き対応（データ構造の拡張が必要な場合）
