# Phase16-Step3-Fix2: 水・溶岩セルの段差側面（滝・溶岩滝）の追加

## 症状

川や溶岩に高低差があると、段差の垂直面に緑の帯が表示される。

## 原因

`scripts/map/voxel_map.gd` の `_create_cliff_sides()` 冒頭で
`if cell.terrain in ["water", "lava"]: return` としているため、
水・溶岩セルは隣接セルより高くても側面ジオメトリを一切生成しない。
段差の垂直面が穴になり、奥の背景が透けて緑の帯に見えている。

## 方針

穴を崖テクスチャで塞ぐのではなく、**水・溶岩専用の側面パネル（滝・溶岩滝）**を
生成する。既存の水・溶岩スクロールシェーダーを縦流し設定で流用する。

## 作業内容

### 1. 滝用シェーダーパラメータの追加

`water.gdshader` / `lava.gdshader` に流れ方向の uniform を追加する
（別シェーダーを作らず1本で兼用する）。

```glsl
uniform vec2 flow_dir = vec2(1.0, 0.3);  // 平面用デフォルト。滝は vec2(0.0, 1.0) 等
```

既存の `TIME * scroll_speed` 系の移動をこの `flow_dir` ベースに置き換える。
水面用.tscnは従来の見た目を維持するパラメータを設定すること。

### 2. 側面パネルシーンの作成

- `assets/terrain/water_side.tscn` / `assets/terrain/lava_side.tscn`
- 構成: Node3Dルート + QuadMesh(1.0×1.0) の MeshInstance3D
- 向き・原点は cliff_side GLB と同じ規格（パネル中心原点、cliff同様に
  yaw回転で4方向に対応できる向き）
- マテリアル: 上記シェーダー。`flow_dir` を下方向に、スクロール速度は
  水面より速め（滝らしさ）。溶岩滝はさらに遅く重く
- EMISSION（溶岩滝）は lava_plane と同値

### 3. MapVisualTheme の拡張

```gdscript
@export var water_side: PackedScene
@export var lava_side: PackedScene
```

`theme_default.tres` に上記2シーンを登録する。

### 4. voxel_map.gd の修正

`_create_cliff_sides()` を以下のように変更する。

- 冒頭の `if cell.terrain in ["water", "lava"]: return` を**削除**
- side_scene の選択分岐に水・溶岩を追加:
  - terrain == "water" → `visual_theme.water_side`
  - terrain == "lava" → `visual_theme.lava_side`
  - 未設定時は従来どおり cliff_side にフォールバック
- 水・溶岩の側面は cliff_side_top（草垂れ）分岐の**対象外**とする
- **最上段パネルの高さ調整**: 水面・溶岩面は上面から SURFACE_OFFSET(0.08) 沈んで
  いるため、最上段（is_top_level）の水・溶岩側面パネルはそのままだと水面より
  0.08 突き出る。最上段のみ `side.position.y -= 0.08` する
  （またはスケールで縮める。位置ずらしの方が単純で歪みも出ない）
- 生成レイヤー: 水・溶岩側面は CLIFF_LAYER ではなく WATER_LAYER に追加する
  （流体表現の一部として扱い、将来の流体システムで一括制御できるようにする）

### 5. 動作確認

- [ ] 川の段差の垂直面が水テクスチャ（下方向スクロール）で表示される
- [ ] 溶岩の段差の垂直面が溶岩テクスチャで表示され、発光している
- [ ] 緑の帯が完全に消えている（マップ外周に接する水・溶岩セルも確認）
- [ ] 側面パネルが水面・溶岩面より上に突き出ていない
- [ ] 水セルの隣が同じ高さの水セルの場合、間に余計なパネルが出ていない
- [ ] 草・土・石セルの崖表示に退行がない（early return削除の影響確認）
- [ ] 水と草が同じ高さで接する箇所の見た目に異常がない

## 完了条件

- 上記チェックリストがすべて通る
- theme_default.tres に water_side / lava_side が登録されている
- 修正内容が docs/asset/map_asset_standard.md の慣例に反していない
  （新規シーンは.tscn+シェーダー方式 = Step3の水・溶岩方針と同じ）

## 備考（将来接続）

この側面パネルは environment_systems.md の流体システム実装時に
「侵食で新たに生まれた段差」へも動的に適用される。今回の実装で
water_side/lava_side がテーマ経由で解決される構造にしておけば、
流体システム側は同じ生成関数を呼ぶだけで済む。
