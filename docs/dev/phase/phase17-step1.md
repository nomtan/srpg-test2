# Phase 17 - Step 1: フラットシェーディング基盤の確立と質感A/B比較

## 前提の変更（重要）

当初「セルルック化」として進めていたが、目標とする絵は**アニメ調のセルシェーディングではなく、ローポリ・ジオラマ調のフラットシェーディング**であることが判明した。
両者は別系統の表現であり、実装方式が根本的に異なる。本stepは後者を採用する。

### 破棄する要素
- ランプによる NdotL の量子化（`cel_level()` 相当）
- 輪郭線（インバートハル）
- リムライト
- リアルタイム影

### 採用する方式
- **面の向きから固定係数を引くフラットシェーディング**（ライティング計算を一切行わない）
- 色の変化は陰影ではなく**マテリアル色そのもの**で作る
- 明度レンジ・彩度をともに狭く圧縮する

### 呼称の変更
実態と乖離するため `cel_` プレフィックスを廃止し `flat_` に統一する。
- `res://shaders/cel/` → `res://shaders/flat/`
- `docs/dev/cel_shading_spec.md` → `docs/dev/flat_shading_spec.md`

---

## 目的

本stepのゴールは **地形の質感を2案作り、検証シーンで見比べて1つに決めること**。
見た目の完成ではなく、方式決定が成果物である。

### 比較する2案

| 案 | 内容 |
|---|---|
| **A: ベタ色** | 1面1色。タイル個体ごとの色ゆらぎ＋崖の高さ方向カラーバンドで変化を作る |
| **B: ピクセルテクスチャ** | 既存の32×32テクスチャを維持。`NEAREST_WITH_MIPMAPS` 継続 |

両案とも**同一の面方向シェーディングを通す**。差分はアルベドの供給元のみとし、比較の公平性を担保する。

---

## スコープ

### やること
- `flat_core.gdshaderinc`（面方向シェーディングの共通実装）
- 地形シェーダー2種（A案 / B案）
- キャラ・プロップ用シェーダー
- `palette.json` のフラット調整（明度レンジ圧縮・彩度低下）
- B案比較用テクスチャの後処理生成（**生成スクリプト本体は改修しない**）
- ブロブシャドウ（リアルタイム影の代替）
- `WorldEnvironment` の再設定
- 検証シーン `flat_validation.tscn`（A/B切替＋ライブ調整）

### やらないこと
- `gen_terrain_textures.py` 本体の改修 → **B案採用時のみ step2 で実施**
- 水・溶岩シェーダー → step2
- 髪モデル → step3以降
- 輪郭線・リムライト → 本方式では不採用のため、実装しない

---

## 設計方針

### 1. ライティング計算を行わない

`render_mode unshaded;` を使用し、`ALBEDO` に最終色を直接書く。

利点:
- **面ごとに完全に均一**。シャドウマップのちらつきも、閾値付近の不安定さも原理的に発生しない
- ライト計算がゼロなのでモバイルで極めて軽い
- 光源の追加・変更で絵が壊れない

### 2. 面の向きで係数を決める

ワールド空間の法線から、天面 / X側面 / Z側面 / 底面に固定係数を割り当てる。
X側面とZ側面に差を付けることで、太陽方位を仮定した最小限の立体感が出る。

### 3. 変化は色相で作る、明度では作らない

参考画像の草地は黄緑・オリーブ・青緑のパッチが混在しているが、明度差はごくわずか。
**同明度で色相を振る**のが原則。明度で変化を付けると平坦さが崩れる。

### 4. 明度レンジを狭く保つ

参考画像には純白も純黒も存在せず、全体が中間調に圧縮されている。
ダークファンタジー向けに全体を暗く落とすことは可能だが、**レンジは狭いまま**にすること。
暗くしつつコントラストも上げると、目指している静謐で平坦な印象が失われる。

目安: 最終出力の輝度を **0.15〜0.45** の帯に収める。

---

## タスク

### T1. `flat_core.gdshaderinc`

配置: `res://shaders/flat/flat_core.gdshaderinc`

#### 面方向係数

```glsl
group_uniforms facing;
uniform float face_top    : hint_range(0.0, 1.5) = 1.00;
uniform float face_side_x : hint_range(0.0, 1.5) = 0.92;
uniform float face_side_z : hint_range(0.0, 1.5) = 0.84;
uniform float face_bottom : hint_range(0.0, 1.5) = 0.68;
group_uniforms;

float face_factor(vec3 wn) {
    vec3 n = abs(wn);
    float side = mix(face_side_z, face_side_x, step(n.z, n.x));
    float vert = wn.y > 0.0 ? face_top : face_bottom;
    return mix(side, vert, smoothstep(0.55, 0.90, n.y));
}
```

`smoothstep` の閾値はボクセル地形では実質不要（面が軸平行のため）だが、
斜面プロップや将来の非軸平行メッシュのために残しておくこと。

#### ワールド座標・法線の取得ヘルパー

```glsl
vec3 world_normal() { return normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz); }
vec3 world_pos()    { return (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz; }
```

#### HSV変換ヘルパー

色相ゆらぎに必須。`rgb2hsv()` / `hsv2rgb()` を実装して include に含める。

#### タイル単位ハッシュ

```glsl
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
```

**ピクセル単位ではなくタイル単位で量子化すること。**
`floor(world_pos.xz / tile_size)` をハッシュ入力に使う。参考画像のパッチはタイル境界で切り替わっている。

#### 色ゆらぎ

```glsl
group_uniforms variation;
uniform float tile_size : hint_range(0.1, 4.0) = 1.0;
uniform float hue_jitter : hint_range(0.0, 0.15) = 0.04;
uniform float sat_jitter : hint_range(0.0, 0.3) = 0.08;
uniform float val_jitter : hint_range(0.0, 0.1) = 0.02;  // 小さく保つ
group_uniforms;

vec3 apply_variation(vec3 base, vec2 tile_id) {
    float h1 = hash21(tile_id);
    float h2 = hash21(tile_id + vec2(37.0, 91.0));
    float h3 = hash21(tile_id + vec2(11.0, 53.0));
    vec3 hsv = rgb2hsv(base);
    hsv.x = fract(hsv.x + (h1 - 0.5) * hue_jitter);
    hsv.y = clamp(hsv.y + (h2 - 0.5) * sat_jitter, 0.0, 1.0);
    hsv.z = clamp(hsv.z + (h3 - 0.5) * val_jitter, 0.0, 1.0);
    return hsv2rgb(hsv);
}
```

`val_jitter` のデフォルトが極端に小さいのは意図的。方針3の通り。

#### 高さ方向カラーバンド（崖の横縞）

参考画像の崖面には赤茶の横縞が入っており、これが岩壁の情報量をほぼ単独で担っている。
実装コストが低い割に効果が大きいので必ず入れること。

```glsl
group_uniforms strata;
uniform bool  strata_enabled = true;
uniform float strata_height : hint_range(0.1, 4.0) = 0.5;
uniform float strata_hue_jitter : hint_range(0.0, 0.15) = 0.03;
uniform float strata_val_jitter : hint_range(0.0, 0.1) = 0.03;
group_uniforms;
```

側面（`abs(wn.y) < 0.5`）にのみ適用し、天面には適用しない。
バンドIDは `floor(world_pos.y / strata_height)`。

---

### T2. 地形シェーダー A案（ベタ色）

配置: `res://shaders/flat/flat_terrain_solid.gdshader`

```glsl
shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/flat/flat_core.gdshaderinc"

uniform vec3 base_color : source_color;
```

`fragment()` の処理順:
1. `wn = world_normal()`, `wp = world_pos()`
2. `col = base_color`
3. 天面なら `apply_variation(col, floor(wp.xz / tile_size))`
4. 側面かつ `strata_enabled` なら高さバンドの色ずらしを適用
5. `ALBEDO = col * face_factor(wn)`

---

### T3. 地形シェーダー B案（ピクセルテクスチャ）

配置: `res://shaders/flat/flat_terrain_tex.gdshader`

A案との差分は**アルベドの供給元のみ**。

```glsl
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
```

- `col = texture(albedo_tex, UV).rgb`
- 色ゆらぎは適用**する**（テクスチャ全体を色相方向にシフトさせる形。タイル個体差を出すため）
- 高さバンドは適用**しない**（テクスチャ側の模様と干渉するため）
- `ALBEDO = col * face_factor(wn)` は共通

---

### T4. キャラ・プロップ用シェーダー

配置: `res://shaders/flat/flat_character.gdshader`

- `render_mode unshaded;`
- `uniform vec3 albedo_color : source_color;` — 単色マテリアル前提
- 色ゆらぎ・高さバンドは**適用しない**（キャラは個体差を出す対象ではない）
- `ALBEDO = albedo_color * face_factor(world_normal());`

キャラは地形より1〜2割明るめの `face_top` を別マテリアルで持たせてよい。
引いたSRPGカメラでユニットが地面に埋もれるのを防ぐため。この値は検証シーンで決める。

---

### T5. ブロブシャドウ

リアルタイム影を廃止するため、ユニットの接地感を別途担保する。
FFT・タクティクスオウガも動的影は持っていなかったが、真下の影表現はあった。

- キャラ足元に `Decal` または板ポリを1枚配置
- 楕円の柔らかいグラデーションテクスチャ、乗算ブレンド
- 高さに応じて縮小・薄化（ジャンプ・浮遊ユニット対応）
- 地形の起伏に追従させる必要があるため、`Decal` ノードを推奨

---

### T6. `palette.json` のフラット調整

旧仕様で導入予定だった `shadow_transform`（ランプ用の影色定義）は**不要になったため削除**する。
面方向係数がその役割を代替する。

#### 新しい構造

```json
{
  "flat_params": {
    "value_range": { "min": 0.15, "max": 0.45 },
    "saturation_scale": 0.72
  },
  "colors": {
    "grass":  { "base": "#5a8a3c" },
    "dirt":   { "base": "#7a5f3e" },
    "stone":  { "base": "#8a8a92" },
    "cliff":  { "base": "#6b4a3a" }
  }
}
```

#### `gen_palette_flat.py`（新規 / 旧 `gen_palette_ramps.py` の置き換え）

`palette.json` を読み、以下を適用した `palette_resolved.json` を出力する。

1. 各 base 色をHSV変換
2. 彩度に `saturation_scale` を乗算
3. 明度を `value_range` の帯に線形リマップ
4. RGB に戻して出力

これにより「明度レンジが狭く彩度が低い」という参考画像の性質が、
色を手で調整せずに構造的に保証される。

> **注意**: 参考画像の色そのものは流用しないこと。
> あれは明るく乾いたメサの配色であり、ダークファンタジーとは噛み合わない。
> 借用するのは**彩度の低さと明度レンジの狭さという性質**のみ。

`palette.json` を単一ソースとする原則は維持（`palette_resolved.json` は生成物、手編集禁止）。

---

### T7. B案比較用テクスチャの後処理生成

**`gen_terrain_textures.py` 本体は改修しないこと。** B案が採用された場合のみ step2 で行う。

#### 問題
既存の32×32テクスチャには陰影（草の濃淡、石のAO風の暗がり、崖面の縦グラデーション）が焼き込まれている。
これを面方向シェーディングに通すと二重に暗くなり、B案が不当に不利な条件で比較されてしまう。

#### 対応
`flatten_textures.py`（新規・使い捨て前提）を作り、既存テクスチャの後処理版を生成する。

- 各テクスチャをHSV変換し、**明度の分散のみを圧縮**（平均明度は維持）
- 目安: タイル内の明度差を ±8% 以内に収める
- 彩度・色相は変更しない（識別性を保つため）
- 出力先: `assets/terrain/flattened/`（比較専用。本採用時は生成側で対応する）

検証シーンでは B案にこの後処理版を使用する。

---

### T8. `WorldEnvironment` の再設定

`unshaded` マテリアルは Ambient / GI / SSAO の影響を受けないため、多くの設定が無効化される。
残るのは最終出力に効く項目のみ。

| 項目 | 設定 | 備考 |
|---|---|---|
| Tonemap | **Linear** | Filmic/ACES は明度レンジ圧縮の意図を壊す |
| Exposure | 1.0 | 露出調整は行わない。明るさは palette で作る |
| SSAO / SSIL | オフ | unshaded に効かない。コスト削減のため明示的にオフ |
| SDFGI / VoxelGI | オフ | 同上 |
| Ambient | 無効 | 同上 |
| Background | **単色** | 参考画像同様、無彩色寄りの中間調。空を描かない |
| Fog | 弱く有効 | 距離の帯として使う。深さは明度でなく色相で出す |
| Glow | 弱く有効・閾値高め | 溶岩・魔法用。地形が光らない閾値に |

DirectionalLight3D:
- フラットマテリアルには影響しないが、`StandardMaterial3D` を使う要素が残る可能性があるため1灯だけ残す
- **Shadow は無効化**（T5のブロブシャドウで代替）

---

### T9. 検証シーン `flat_validation.tscn`

配置: `res://scenes/dev/flat_validation.tscn`

**本stepの成果物を決定するための道具。**

#### 構成
1. **地形展示** — 既存の全タイル種をグリッド配置。崖の高さ方向の縞が見えるよう、3段以上の高低差を必ず含める
2. **キャラ配置** — `base.bbmodel` を3体。平地・斜面際・崖上に1体ずつ
3. **カメラ** — 実ゲームのSRPGカメラ角度をデフォルトに。`Tab` でフリーオービット切替

#### A/B切替（最重要機能）

キー `F1` / `F2` で地形マテリアルを A案 / B案 に**即時切替**する。
ジオメトリ・カメラ・パラメータは一切変えないこと。

> 並置よりも同一画面での瞬時切替の方が差が判別しやすいため、
> 分割ビューではなくトグル方式を採用する。

`F3` で切替時に自動スクリーンショットを撮り、`docs/dev/assets/` に A/B 一対で保存する機能を付ける。

#### ライブ調整UI

画面右にスライダーを配置:
- `face_top` / `face_side_x` / `face_side_z` / `face_bottom`
- `hue_jitter` / `sat_jitter` / `val_jitter` / `tile_size`
- `strata_enabled` / `strata_height` / `strata_hue_jitter` / `strata_val_jitter`
- キャラ用 `face_top` オフセット
- Background色 / Fog密度・色

#### 数値のエクスポート

`Ctrl+S` で全パラメータを `res://scenes/dev/flat_preset_export.json` に書き出す。
**この機能が step1 の完了判定に直結する。**

---

## 完了条件

1. `flat_validation.tscn` が起動し、`F1`/`F2` でA/B即時切替が動作する
2. 両案とも同一の面方向シェーディングを通っており、差分がアルベド供給元のみである
3. 崖面に高さ方向のカラーバンドが出ており、単調な壁になっていない
4. 草地のタイルに個体差が出ており、かつ明度ではなく色相で変化している
5. キャラが地形に埋もれず、ブロブシャドウで接地している
6. **A案 / B案のいずれかを選択済み**
7. `flat_preset_export.json` を出力済み
8. **確定値を `docs/dev/flat_shading_spec.md` に転記済み**

`flat_shading_spec.md` に含める内容:
- 採用した地形方式（A / B）とその判断理由
- 確定した面方向係数の全値
- 色ゆらぎ・高さバンドのパラメータ
- 明度レンジ・彩度スケールの確定値
- 新規マテリアル作成時の遵守事項（`unshaded` 必須、独自ライティング禁止、明度で変化を作らない）

---

## step2 への引き継ぎ

- **A案採用時** — `gen_terrain_textures.py` の役割縮小。タイル個体差の生成はシェーダー側に移るため、スクリプトは形状・UV生成に専念させる
- **B案採用時** — `gen_terrain_textures.py` を本改修し、明度分散を抑えたテクスチャを正規生成する（`flatten_textures.py` は破棄）
- 水・溶岩シェーダーのフラット化（確定した面方向係数に合わせる。2〜3段のベタ色＋動く白線のフォーム方式）
- 髪モデル着手（step3）

---

## 補足: 作業順序の推奨

T6（palette）→ T1（shaderinc）→ T2/T3（地形2種）→ T9（検証シーン）→ T8（Environment）→ T4（キャラ）→ T5（ブロブシャドウ）→ T7（比較用テクスチャ）

T9 の検証シーンを早い段階で立ち上げること。
以降のパラメータ調整はすべてこのシーン上で行うため、先に道具を用意した方が総作業時間が短くなる。
