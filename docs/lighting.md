# 実装指示書: WorldEnvironment による雰囲気ライティング

## 目的

戦闘マップに、マインクラフト・ダンジョンズ風の暗めで立体感のあるジオラマ的雰囲気を与える。テクスチャは作らず、**ライティングとポストプロセスだけ**で空気感を出す。

現状 `Main.tscn` の `WorldEnvironment` ノードは存在するが `environment` リソースが未設定で、環境光・トーンマップ・グロー・フォグがすべて無効になっている。これを設定し、ディレクショナルライトを寒暖コントラストが出る向きに調整する。

## 前提・制約（必ず守ること）

- レンダラーは **GL Compatibility**（`project.godot` の `renderer/rendering_method="gl_compatibility"`）。
  - **SSAO / SSIL / ボリューメトリックフォグ / SDFGI は使用不可**。これらのプロパティは追加しないこと。
  - 使用可能なのは、環境光・**深度フォグ（depth fog）**・グロー・トーンマップ・色調補正（adjustments）。
- カメラは正投影（`camera_controller.gd` の `PROJECTION_ORTHOGONAL`, `size=14`）。この設定は**変更しない**。
- SRPG のため**盤面の可読性が最優先**。フォグと彩度を上げすぎて「歩けるマス・高さの段数」が読めなくなってはいけない。
- 既存のゲームロジック（`voxel_map.gd`, `battle_unit.gd`, グリッド/ターン系）には**一切手を加えない**。今回は `Main.tscn` の2ノードのみの変更。

## 対象ファイル

- `Main.tscn`（唯一の編集対象）

## 作業内容

### 1. Environment サブリソースを追加

`Main.tscn` の `[ext_resource ...]` 群の直後（`[node name="Main" type="Node3D"]` の前）に、以下の `sub_resource` を追加する。

```gdscript
[sub_resource type="Environment" id="Environment_atmo"]
background_mode = 1
background_color = Color(0.043, 0.055, 0.078, 1)
ambient_light_source = 2
ambient_light_color = Color(0.29, 0.35, 0.47, 1)
ambient_light_energy = 0.35
tonemap_mode = 4
glow_enabled = true
glow_intensity = 0.5
glow_bloom = 0.05
glow_hdr_threshold = 1.0
fog_enabled = true
fog_light_color = Color(0.05, 0.063, 0.09, 1)
fog_density = 0.015
adjustment_enabled = true
adjustment_contrast = 1.05
adjustment_saturation = 1.15
```

各プロパティの意図と対応する数値：

| プロパティ | 値 | 意図 |
|---|---|---|
| `background_mode = 1` | Custom Color | 空を出さず暗い無地背景に |
| `background_color` | `#0b0e14` | 盤面を背景から浮かせる暗い青黒 |
| `ambient_light_source = 2` | Color | 環境光を手動制御 |
| `ambient_light_color` | 寒色 `#4a5978` | 影側を真っ黒にせず青く沈める |
| `ambient_light_energy` | `0.35` | 影の暗さ調整ノブ |
| `tonemap_mode = 4` | AgX | フィルミックな階調（`3`=ACES） |
| `glow_*` | Intensity 0.5 / Bloom 0.05 / Threshold 1.0 | 水面・選択エミッションだけ光らせる。地形をブルームで溶かさないため Threshold は 1.0 必須 |
| `fog_density = 0.015` | 薄い深度フォグ | 盤面の端を背景に溶かしてジオラマ感 |
| `fog_light_color` | 背景寄り `#0d1017` | 遠景が背景に馴染む |
| `adjustment_*` | Contrast 1.05 / Saturation 1.15 | マイクラの鮮やかパレットを活かす |

> 注: `tonemap_mode = 4` は AgX（Godot 4.6 以降）。暗すぎる場合は `3`（ACES）に変更してよい。

### 2. WorldEnvironment ノードに environment を割り当て

既存の `WorldEnvironment` ノードに `environment` 行を追加する。

**変更前:**
```gdscript
[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
```

**変更後:**
```gdscript
[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_atmo")
```

### 3. DirectionalLight3D を暖色・寒暖コントラスト向けに調整

環境光を寒色にした対として、直射光を暖色にする。既存の `DirectionalLight3D` ノードを以下に置き換える。

**変更前:**
```gdscript
[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-52, -35, 0)
light_energy = 1.2
shadow_enabled = true
```

**変更後:**
```gdscript
[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-52, -35, 0)
light_color = Color(1, 0.949, 0.839, 1)
light_energy = 1.3
shadow_enabled = true
shadow_bias = 0.05
```

- `light_color` = 暖色 `#fff2d6`。環境光の寒色 `#4a5978` と分かれることで日向・日陰の色が出て立体感が生まれる。
- `rotation_degrees` は既存値を維持。

### 4. load_steps について

ファイル先頭の `[gd_scene load_steps=54 format=3]` は、`sub_resource` を1つ追加したら本来 `55` になる。**Godot で開いて保存すれば自動修正されるため、手動で書き換えなくてよい**（書き換える場合は 55 にする）。

## 受け入れ基準（完了条件）

1. Godot 4.6 でプロジェクトを開き、`F5` で実行してもエラー・警告が出ない。
2. 実行画面が、変更前より明確に暗く・立体的になっている（影側が青く沈み、日向が暖色）。
3. マップの端が背景（暗い青黒）に向かって薄くフェードしている。
4. ユニット選択時のエミッション（`battle_unit.gd` の `set_selected`）や水面が、うっすら発光して見える。
5. **盤面のマス目・高さの段差・歩行可能範囲が問題なく判読できる**（フォグ・彩度で潰れていない）。
6. 変更は `Main.tscn` のみ。他ファイルに差分がない。

## 調整ノブ（基準を満たした上で微調整する場合）

- 暗すぎる → `ambient_light_energy` を 0.35 → 0.5、または `light_energy` を上げる
- 端のフェードを調整 → `fog_density` を 0.01〜0.03 の範囲で
- 鮮やかさ → `adjustment_saturation` を 1.1〜1.3 の範囲で
- 可読性が落ちたら → フォグと彩度を下げる方向で戻す

## やらないこと（スコープ外）

- テクスチャの追加・`voxel_map.gd` の変更
- キャラクターモデルの差し替え・`battle_unit.gd` の変更
- カメラ設定の変更
- レンダラーの Forward+ への変更（今回は Compatibility のまま）
- SSAO / ボリューメトリックフォグ等、Compatibility 非対応機能の追加