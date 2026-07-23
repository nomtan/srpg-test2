# フラットシェーディング仕様（Phase17 Step1）

> **状態: 暫定（PROVISIONAL）。** 本ドキュメントの数値は
> [phase17-step1.md](phase/phase17-step1.md) T9 の検証シーンで実際に見比べて
> 決定した値ではなく、実装時点のデフォルト値をそのまま記載したプレースホルダーです。
> **A案/B案の選択も未確定**です。
>
> [phase17-step1-fix.md](phase/phase17-step1-fix.md) のブロッカー
> （F1: パレット全地形種対応 / F2: 植生プロップのフラット化）は解消済みです。
>
> **運用ルール（phase17-step1-fix.md）: 検証シーン左上の「未定義タイル: N件」が
> `N > 0` の状態でA/B判断を行ってはならない。** 現状 `N = 0`（実機確認済み）。
>
> **完了条件を満たすには:**
> 1. Godotエディタで `res://scenes/dev/flat_validation.tscn` を開いて実行する
> 2. 左上の「未定義タイル: N件」が `0件` であることを確認する
>    （`N > 0` なら判断に進む前に `TERRAIN_ASSET_TO_PALETTE_KEY` と
>    `palette.json` の `colors` を修正すること）
> 3. `F1`（A: ベタ色）/ `F2`（B: ピクセルテクスチャ）で即時切替して見比べる。
>    **実ゲームのカメラ距離（デフォルトのSRPGカメラ）で評価すること。**
>    近づいて見るとA案が有利に見えすぎる
> 4. 右側のスライダーで `face_top` 等を微調整して方向性を決定する
> 5. `F3` で `docs/dev/assets/flat_ab_solid.png` / `flat_ab_tex.png` を撮り、
>    どちらを採用するか判断する
> 6. `Ctrl+S` を押す → `res://scenes/dev/flat_preset_export.json` に現在値が
>    書き出される
> 7. その内容を本ドキュメントの「確定値」節に転記し、冒頭の状態表記を
>    「確定」に変更する
>
> 転記されるまで、以下の数値・A/B選択は変更される前提で参照すること。

## 採用した地形方式

**未決定。** 現状の実装のデフォルトは A案（ベタ色）だが、これは判断ではなく
起動時の初期状態に過ぎない。

| 案 | 内容 | 実装ファイル |
|---|---|---|
| A: ベタ色 | 1面1色。タイル単位の色ゆらぎ＋崖の高さバンドで変化 | `shaders/flat/flat_terrain_solid.gdshader` |
| B: ピクセルテクスチャ | 既存32×32テクスチャ維持（比較時は`assets/terrain/flattened/`の後処理版を使用） | `shaders/flat/flat_terrain_tex.gdshader` |

判断理由: (ここにA/Bを選んだ理由を記入すること)

## 確定値（暫定 = 実装時点のデフォルト）

### 面方向係数
| パラメータ | 値 |
|---|---|
| `face_top` | 1.00 |
| `face_side_x` | 0.92 |
| `face_side_z` | 0.84 |
| `face_bottom` | 0.68 |
| キャラ用 `face_top` 倍率 | ×1.15（地形の`face_top`に対する倍率） **※A/B確定後に要再調整（下記F5参照）** |

### 色ゆらぎ（タイル単位）
| パラメータ | 値 |
|---|---|
| `tile_size` | 1.0 |
| `hue_jitter` | 0.04 |
| `sat_jitter` | 0.08 |
| `val_jitter` | 0.02 |

### 高さ方向カラーバンド（崖の縞）
| パラメータ | 値 |
|---|---|
| `strata_enabled` | true |
| `strata_height` | 0.5 |
| `strata_hue_jitter` | 0.03 |
| `strata_val_jitter` | 0.03 |

### 明度レンジ・彩度スケール（`tools/asset_gen/palette.json` の `flat_params`）
| パラメータ | 値 |
|---|---|
| `value_range.min` | 0.15 |
| `value_range.max` | 0.45 |
| `saturation_scale` | 0.72 |

## 新規マテリアル作成時の遵守事項

1. **`render_mode unshaded;` を必ず使用すること。** `light()` を実装しない。
   ライティング計算は本方式では一切行わない
2. 必ず `shaders/flat/flat_core.gdshaderinc` を `#include` し、
   `face_factor()` / `apply_variation()` / `apply_strata()` を通すこと。
   個別マテリアルで独自の陰影計算を書かない
3. 変化は**色相**で作る。**明度で変化を付けない**（`val_jitter`系のデフォルトが
   小さいのは意図的。上げる場合も他の色相ジッターより十分小さく保つこと）
4. 新しい `vertex()` を書く場合、必ず `FLAT_VERTEX_SETUP` マクロを呼ぶこと
   （理由は下記「実装メモ」参照）:
   ```glsl
   void vertex() {
       FLAT_VERTEX_SETUP
   }
   ```
   **括弧を付けないこと**（`FLAT_VERTEX_SETUP()` ではなく `FLAT_VERTEX_SETUP`）。
   このプロジェクトのGodotビルドは関数マクロ（`#define NAME() ...`）を
   正しく処理できず、`#include` 自体が壊れる。オブジェクト形式マクロとして
   定義・呼び出しすること
5. 輪郭線・リムライト・リアルタイム影は実装しない（本方式では不採用）。
   接地感が必要なキャラには `battle_unit.gd` の `_create_blob_shadow()` が
   自動で付与するブロブシャドウ（`Decal`）を使うこと
6. Environment 側で暗さ・陰影を作らない。Tonemap Linear固定、SSAO/SSIL/
   SDFGI無効、Ambient無効、背景は単色
7. **植生（クロスクワッド系）は `flat_terrain_*.gdshader` ではなく
   `shaders/flat/flat_vegetation.gdshader` を使うこと。**
   - `cull_disabled` 必須（クワッドの裏面が消えるのを防ぐ）
   - `face_factor()` を通さず、`face_top` を直接乗算すること
     （房を構成する複数クワッドの明るさを揃え、房がバラけて見えるのを防ぐ）
   - 色ゆらぎは株（インスタンス）単位。`flat varying vec3 flat_instance_origin`
     に `MODEL_MATRIX[3].xyz` を入れ、`floor(flat_instance_origin.xz / tile_size)`
     を `apply_variation()` のタイルIDとして使う
   - 高さ方向カラーバンド（`apply_strata()`）は適用しない
   - A/B切替の対象外。Plan A/Bどちらでも常にこのシェーダーを使う
8. **地形タイルの色は必ず `palette.json` の `colors` に定義し、
   `flat_validation.gd` の `TERRAIN_ASSET_TO_PALETTE_KEY` に明示的に
   マッピングを追加すること。** ファイル名の部分一致などの暗黙的な
   推測は行わない。マッピングが無い/`palette.json`に色が無いアセットは
   マゼンタ（`#ff00ff`）で描画され、検証シーンの「未定義タイル」カウンタが
   増える。**このカウンタが0でない状態でA/B判断を行ってはならない**

## 実装メモ（仕様書からの実装上の乖離）

- **`INV_VIEW_MATRIX` は使っていない。** phase17-step1.md T1 は
  `world_normal()`/`world_pos()` を `INV_VIEW_MATRIX` ベースで実装する例を
  示しているが、本プロジェクトが使う **GL Compatibility レンダラー**では
  `fragment()` 内で `INV_VIEW_MATRIX` が参照できず、シェーダーコンパイルが
  失敗した（実機検証で確認済み）。代わりに `vertex()` で `MODEL_MATRIX` から
  ワールド法線/座標を計算し、`varying` で `fragment()` に渡す方式に変更した
- **`flat` 修飾子の使い分け（phase17-step1-fix.md F3）**:
  `flat_world_normal` は `varying flat vec3` — 面内で一定の値（法線）なので
  補間不要かつ将来のスムース法線混在に備えて `flat` を付ける。
  `flat_world_pos` は **`flat` を付けない** 通常の `varying` —
  `apply_variation()`/`apply_strata()` がフラグメントごとのワールド座標に
  依存するため、`flat` にするとポリゴン全体が単一タイルIDに潰れて模様が消える。
  **修飾子の順序は `varying flat`（`flat varying` ではない）。**
  逆順で書くと `"Expected constant, function, uniform or varying"` で
  パースエラーになることを実機確認済み
- **`FLAT_VERTEX_SETUP` はオブジェクト形式マクロ（括弧なし）
  （phase17-step1-fix.md F4）**: 当初 `#define FLAT_VERTEX_SETUP() ...` という
  関数形式マクロで実装したが、このプロジェクトのGodotビルドでは
  関数形式マクロを定義した時点で（呼び出し側ではなく）**そのシェーダーを
  `#include` している側のシェーダー全てで `#include` 行自体が
  `"Unknown character '#'"` としてトークナイズに失敗する**現象を
  二分探索で確認した。オブジェクト形式マクロ（括弧なしで定義・呼び出し）に
  変更することで解消した。今後もこのファイルに関数形式マクロを追加しないこと
- `flat_validation.gd` は `voxel_map.gd` を変更せず、検証シーン内で地形の
  `MeshInstance3D` を直接走査して `flat_terrain_solid`/`flat_terrain_tex`/
  `flat_vegetation` の `ShaderMaterial` に差し替えている。**本番の地形描画
  （`voxel_map.gd`）は未変更** — A/B決定後、選ばれた方式を本番にも適用する
  のはstep2の作業
- 同様に **`assets/environment/battle_atmosphere.tres` と `Main.tscn` の
  `DirectionalLight3D` も意図的に未変更。** 本番の地形がまだ通常の
  PBRライティングを受けている状態でAmbientを無効化すると地形が
  不自然に暗くなるため、T8のEnvironment設定は検証シーン内のみに限定した
- **キャラクター（`battle_unit.gd`）は本番にも適用済み。** A/B比較の対象では
  ないため、`flat_character.gdshader` への切替と輪郭線/リムライトの削除は
  即座に本番へ反映した。ブロブシャドウ (`Decal`) も全ユニットに追加済み
  （`update_blob_shadow()` はジャンプ/浮遊時の縮小・薄化用フックのみ用意し、
  実際の移動・スキルシステムへの結線は未実施）
- **地形タイルの色マッピングはファイル名ヒューリスティックを廃止し、
  `docs/dev/terrain_tile_inventory.md` を正本とした明示マッピングに
  置き換え済み**（phase17-step1-fix.md F1）。`palette.json` の `colors` は
  検証シーンに出現する全アセット（grass/dirt/stone/cliff_side/
  cliff_side_top/cliff_stone/water/lava/bridge/stone_brick/
  infested_cracked_stone_bricks/chiseled_stone_brick/bricks/cobblestone）分を
  定義済み。水・溶岩は元々専用の`ShaderMaterial`（`water.gdshader`/
  `lava.gdshader`）を使っており`flat_terrain_*`へは変換されない
  （A/B比較の対象外）が、色ハードコード全廃の原則に合わせて
  `palette.json`側に色定義を移した
- **植生プロップ（`grass_short`/`grass_mid_*`/`grass_tall`）は
  `flat_vegetation.gdshader`で描画**（phase17-step1-fix.md F2）。
  以前は「変換対象から除外し元のPBRマテリアルのまま表示」だったが、
  専用シェーダーを実装し常時適用するよう変更した
- **草→土の地形遷移は `VoxelMap` の8近傍オートタイルで生成する。**
  `flat_grass_transition.gdshader`を使う薄いオーバーレイを土／forestセル上に
  1枚だけ置き、同じ高さのgrass／high_ground隣接セルから4辺＋4角のマスクを
  決定する。境界は32px単位に量子化し、決定的な1〜3pxの揺らぎを付ける。
  本番へ未確定の見た目を波及させないため`VoxelMap.grass_transitions_enabled`の
  デフォルトはfalse、検証シーンのみtrue。A/B比較ではB案だけ表示する
- 水・溶岩のフラット化は本stepのスコープ外（step2でセル化ではなくフラット化として実施）

## F5: キャラ `face_top` 倍率の再調整（保留）

キャラ用 `face_top` 倍率 ×1.15 は本fixでは変更していない。本来「確定した
地形の上でユニットが埋もれないか」を見て決めるべき値だが、現在は本番の
地形がまだPBRライティングのままであり、この値はプレースホルダーのまま
本番へ適用されている。**A/B判断後、検証シーン上で地形が確定した状態で
改めて詰めること。**

## 完了条件チェックリスト

### phase17-step1.md T9
- [x] `flat_validation.tscn` が起動し、`F1`/`F2` でA/B即時切替が動作する（実機検証済み）
- [x] 両案とも同一の面方向シェーディングを通っており、差分がアルベド供給元のみである
- [ ] 崖面に高さ方向のカラーバンドが出ており、単調な壁になっていない（要目視確認）
- [ ] 草地のタイルに個体差が出ており、かつ明度ではなく色相で変化している（要目視確認）
- [x] キャラが地形に埋もれず、ブロブシャドウで接地している
- [ ] **A案 / B案のいずれかを選択済み**
- [ ] `flat_preset_export.json` を出力済み
- [ ] **確定値を本ドキュメントに転記済み**

### phase17-step1-fix.md
- [x] `docs/dev/terrain_tile_inventory.md` に全タイル種が列挙されている
- [x] 検証シーンに出現する全タイル種が `palette.json` に定義済み
- [x] 水・溶岩の色定義がコードから消え、`palette.json` に移っている
- [x] ファイル名ヒューリスティックが明示マッピング（`TERRAIN_ASSET_TO_PALETTE_KEY`）に置き換わっている
- [x] 未定義タイルがエラー色（マゼンタ）＋警告ログで即座に判別できる
- [x] 検証シーンに `未定義タイル: N件` が常時表示され、**N = 0 である**（実機確認済み）
- [x] 草プロップが `flat_vegetation.gdshader` で描画され、black cutout が発生していない（実機確認済み）
- [x] 草の房が1つの塊として読め（`face_factor()`を通さずface_topを直接乗算）、3枚のクワッドがバラけて見えない
  （※実際のクロスクワッドは0/60/120度3枚ではなく45/135度2枚構成。挙動は同一のため対応不要）
- [x] 隣接する株どうしで色に個体差が出ている（`flat_instance_origin`単位のハッシュ）
- [x] `flat_world_normal` に `flat` が付き（`varying flat`順）、`flat_world_pos` には付いていない
- [x] 全シェーダーの `vertex()` が `FLAT_VERTEX_SETUP` 呼び出しに統一されている（括弧なし）
- [x] `flat_shading_spec.md` に上記5項目が反映されている（本更新）
