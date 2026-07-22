# Phase 17 - Step 1: セルルック基盤の確立

## 目的

ゲーム全体（地形・キャラ・プロップ）を統一したセルシェーディングに移行するための土台を作る。
本stepのゴールは **見た目の完成ではなく、シェーディング規約の確定** である。
最終成果物は「検証シーンで実際に見比べて決定したランプ数値が、spec文書に書き戻された状態」。

## スコープ

### やること
- `cel_core.gdshaderinc` の作成（全マテリアル共通のランプ関数）
- キャラ用 / 地形用の2種類のセルシェーダー作成
- `palette.json` のランプセット化と、影色の自動生成スクリプト
- `gen_terrain_textures.py` の改修（明度分散の除去）
- `WorldEnvironment` のセルルック向け再設定
- 検証シーン `cel_validation.tscn` の作成（3プリセット切替＋ライブ調整）
- キャラ用アウトラインの暫定実装

### やらないこと（step2以降）
- 水・溶岩シェーダーのセル化 → **step2**。本stepでランプ基準が確定してから着手する
- スムース法線のベイク（アウトラインの角割れ対策） → **step2**
- 髪モデルの作成 → step3以降
- エフェクト・UI のセル対応

---

## 設計方針

### 1. ランプは唯一の権威を持つ

段数・閾値・影色ルールは `cel_core.gdshaderinc` に集約する。
地形もキャラも同じ関数を通す。個別マテリアルで独自のシェーディング計算を書かないこと。

### 2. ATTENUATION をランプに乗せる

Godot 4 の `light()` 関数において、`ATTENUATION` にはリアルタイム影の減衰が含まれる。
これをそのまま乗算するとシャドウマップのぼけたエッジが残り、セルの平坦さが崩れる。

**必ず `NdotL * ATTENUATION` を先に合成してから量子化すること。**
これによりキャラの落ち影が、地形のセル影と同一の色・同一の段数になる。

### 3. 影色は「生成」する、手で置かない

`palette.json` の各エントリに shade1 / shade2 を手書きすると、色数が増えたときに統一が崩れる。
ベース色に対して **共通の影変換**（明度低下 + 色相の寒色シフト + 固定色へのブレンド）を適用して生成する。

これにより「草も肌も金属も、影側では同じ寒色に収束する」状態が構造的に保証される。
地形とキャラという別パイプラインの産物が、同じ空気の中に立って見えるための最重要ポイント。

### 4. 暗さは Environment ではなく palette で作る

従来のダークファンタジー向けライティング（SSAO・GI・トーンマップによる暗さ）は、
連続的な陰影を生むためセルと矛盾する。暗さは色そのものに持たせる。

---

## タスク

### T1. `cel_core.gdshaderinc` の作成

配置: `res://shaders/cel/cel_core.gdshaderinc`

以下を提供する:

```glsl
group_uniforms cel_ramp;
uniform float ramp_threshold_1 : hint_range(0.0, 1.0) = 0.50;
uniform float ramp_threshold_2 : hint_range(0.0, 1.0) = 0.15;
uniform float ramp_softness    : hint_range(0.0, 0.10) = 0.01;
group_uniforms;

group_uniforms cel_shadow;
uniform vec3  shadow_tint : source_color = vec3(0.28, 0.24, 0.42);
uniform float shadow_1_mul : hint_range(0.0, 1.0) = 0.62;
uniform float shadow_1_blend : hint_range(0.0, 1.0) = 0.25;
uniform float shadow_2_mul : hint_range(0.0, 1.0) = 0.40;
uniform float shadow_2_blend : hint_range(0.0, 1.0) = 0.50;
group_uniforms;

group_uniforms cel_rim;
uniform vec3  rim_color : source_color = vec3(0.55, 0.62, 0.85);
uniform float rim_power : hint_range(1.0, 16.0) = 4.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
group_uniforms;
```

**関数1: レベル算出**

```glsl
// 戻り値: 0.0(最暗) / 1.0(中間) / 2.0(明) の連続値
float cel_level(float ndotl, float attenuation) {
    float l = clamp(ndotl, 0.0, 1.0) * attenuation;
    float s1 = smoothstep(ramp_threshold_2 - ramp_softness,
                          ramp_threshold_2 + ramp_softness, l);
    float s2 = smoothstep(ramp_threshold_1 - ramp_softness,
                          ramp_threshold_1 + ramp_softness, l);
    return s1 + s2;
}
```

**関数2: 影色生成**

```glsl
vec3 cel_shadow_color(vec3 base, float mul, float blend) {
    return mix(base * mul, shadow_tint, blend);
}
```

**関数3: ベース色 + レベル → 最終色**

```glsl
vec3 cel_apply(vec3 base, float level) {
    vec3 s2 = cel_shadow_color(base, shadow_2_mul, shadow_2_blend);
    vec3 s1 = cel_shadow_color(base, shadow_1_mul, shadow_1_blend);
    vec3 c  = mix(s2, s1, clamp(level, 0.0, 1.0));
    return mix(c, base, clamp(level - 1.0, 0.0, 1.0));
}
```

**関数4: リムライト**

```glsl
vec3 cel_rim(vec3 normal, vec3 view) {
    float r = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), rim_power);
    return rim_color * r * rim_strength;
}
```

#### 段数について
`ramp_threshold_2` を 0.0 に設定すると `s1` が常に1になり、実質2段ランプとして機能する。
2段 / 3段の切り替えは閾値だけで行い、コードを分岐させないこと。

---

### T2. キャラ用シェーダー

配置: `res://shaders/cel/cel_character.gdshader`

- `#include "res://shaders/cel/cel_core.gdshaderinc"`
- `render_mode ambient_light_disabled;` を指定（Environment の Ambient を二重適用しない）
- `uniform vec3 albedo_color : source_color;` — 単色マテリアル前提
- `light()` 内で `cel_level()` → `cel_apply()` を通し、`DIFFUSE_LIGHT` に加算
- `fragment()` の末尾でリムを `EMISSION` に加算（ランプの影響を受けないようにするため）

`light()` の骨子:

```glsl
void light() {
    float ndotl = dot(normalize(NORMAL), normalize(LIGHT));
    float level = cel_level(ndotl, ATTENUATION);
    DIFFUSE_LIGHT += cel_apply(ALBEDO, level) * LIGHT_COLOR;
}
```

> **注意**: `LIGHT_COLOR` には light energy が乗っている。
> DirectionalLight3D の energy を 1.0 以外にするとランプの閾値がずれるため、
> **energy は 1.0 固定** とし、明るさの調整は palette 側で行う。

---

### T3. 地形用シェーダー

配置: `res://shaders/cel/cel_terrain.gdshader`

キャラ用との違いは **アルベドがテクスチャ由来** である点のみ。
テクスチャからサンプルした色をそのまま `cel_apply()` に渡せば、影変換が自動適用される。
（影色を palette から引く必要はない — これが T1 の設計方針3を採用した最大の利点）

- `uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;`
  → 既存の `NEAREST_WITH_MIPMAPS` 方針を維持
- リムライトは **無効**（地形に入れると地面が縁取られて浮く）
- `light()` の構造はキャラ用と同一

---

### T4. `palette.json` のランプセット化

#### 現状
各エントリが単色を1つ持つ構造。

#### 変更後
ベース色は据え置き。加えてファイル先頭に共通の影変換パラメータを持たせる。

```json
{
  "shadow_transform": {
    "tint": "#473d6b",
    "shade1": { "mul": 0.62, "blend": 0.25 },
    "shade2": { "mul": 0.40, "blend": 0.50 }
  },
  "colors": {
    "grass":      { "base": "#5a8a3c" },
    "dirt":       { "base": "#7a5f3e" },
    "stone":      { "base": "#8a8a92" },
    "skin_light": { "base": "#e0b088" },
    "cloth_green":{ "base": "#3aa84f", "shade1": "#1f6b3a" }
  }
}
```

- 個別エントリの `shade1` / `shade2` は **任意のオーバーライド**。省略時は `shadow_transform` から生成
- オーバーライドは例外的な用途（発光物、特殊素材）にのみ使う。乱用すると統一が崩れる

#### `gen_palette_ramps.py`（新規）

`palette.json` を読み、影色を解決した完全版 `palette_resolved.json` を出力する。
- HSV変換して明度低下 + 色相を寒色側へシフト → tint とブレンド、の順で計算
- 既存の各種生成スクリプトは `palette_resolved.json` を参照するよう切り替える
- `palette.json` が単一ソースである原則は維持（resolved は生成物であり手編集禁止）

#### `MapVisualTheme` の拡張
現状 base 色のみを参照しているため、shadow_transform 一式をマテリアルの uniform に流す経路を追加する。

---

### T5. `gen_terrain_textures.py` の改修

**本stepで最も見落としやすい箇所。**

現状の32×32テクスチャに焼き込まれている「陰影らしさ」— 草の濃淡、石のAO風の暗がり、崖面の上下グラデーション等 — は、
シェーダーのランプ段差と喧嘩して画面が濁る原因になる。

#### 改修方針
- **色相・パターンは維持する**（タイルの識別性はここで担保される）
- **明度分散を最小化する**。目安として、1タイル内の明度差を **±8%以内** に収める
- 具体的には、濃淡でパターンを描いていた箇所を、同明度の色相違いに置き換える
  - 例: 草の濃い緑 → 明度同等で黄緑寄り / 青緑寄りの2色
- 崖面の縦グラデーションは削除。立体感はシェーダーの法線由来の陰影に任せる

#### 検証
改修前後のテクスチャを並べて出力する比較画像を生成し、`docs/dev/assets/phase17_texture_diff.png` として残すこと。

---

### T6. `WorldEnvironment` の再設定

| 項目 | 設定値 | 理由 |
|---|---|---|
| Tonemap | **Linear** | Filmic/ACES はハイライトを圧縮し、ランプの段差を歪める |
| Exposure | 1.0 | 同上。露出調整は行わない |
| SSAO | **オフ** | 連続的な陰影がセルと矛盾する |
| SSIL | オフ | 同上 |
| SDFGI | オフ | モバイル前提でも同結論 |
| VoxelGI | オフ | 同上 |
| Ambient Light Source | **Color（固定色）** | Sky由来だと下段が不安定になる |
| Ambient Color | shadow_tint と同系色 | 影の下限を palette と揃える |
| Ambient Energy | 0.15〜0.30（検証で決定） | ランプ最暗段の底上げ量 |
| Fog | **有効** | 距離の帯として使う。深さは明度でなく色相で出す |
| Glow | 弱く有効 / 閾値高め | 溶岩・魔法エフェクト用。地形が光らない閾値に |

DirectionalLight3D:
- 1灯のみ。補助光は追加しない（段差が交差して汚くなる）
- `light_energy = 1.0` 固定（T2の注意参照）
- Shadow: 有効。`ATTENUATION` 経由でランプに乗るため、blur は最小値に

---

### T7. 検証シーン `cel_validation.tscn`

配置: `res://scenes/dev/cel_validation.tscn`

**本stepの成果物を決定するための道具。ここで数値を確定させる。**

#### 構成
1. **地形タイルの全種展示** — 草・土・石・崖面など既存の全タイルをグリッド配置。高低差を含めること
2. **キャラ配置** — `base.bbmodel` を3体。平地・斜面際・崖上に1体ずつ（落ち影の見え方を確認するため）
3. **カメラ** — 実ゲームのSRPGカメラ角度をデフォルトに。キー `Tab` でフリーオービットに切替
4. **ライト角度プリセット** — キー `1` / `2` / `3` で朝・正午・夕（低角・高角・逆光気味）を切替

#### スタイルプリセット（重要）
キー `F1` / `F2` / `F3` で以下を一括切替できるようにする。**これを見比べて方向性を決定する。**

| キー | 名称 | 段数 | threshold_1 | threshold_2 | softness | shadow_1_blend | rim_strength |
|---|---|---|---|---|---|---|---|
| F1 | Soft（トライアングルストラテジー寄り） | 2段 | 0.45 | 0.0 | 0.03 | 0.20 | 0.20 |
| F2 | Sharp（ギルティギア／原神寄り） | 2段 | 0.50 | 0.0 | 0.005 | 0.35 | 0.55 |
| F3 | Deep（3段・重厚） | 3段 | 0.55 | 0.18 | 0.01 | 0.30 | 0.35 |

上記は**検討の出発点となる暫定値**であり、正解ではない。実際に見て調整すること。

#### ライブ調整UI
画面右にスライダーを配置し、以下をリアルタイム変更できるようにする:
- `ramp_threshold_1` / `ramp_threshold_2` / `ramp_softness`
- `shadow_tint`（カラーピッカー）/ `shadow_1_mul` / `shadow_1_blend` / `shadow_2_mul` / `shadow_2_blend`
- `rim_color` / `rim_power` / `rim_strength`
- Ambient Energy
- アウトライン太さ

#### 数値のエクスポート
`Ctrl+S` で現在の全パラメータを `res://scenes/dev/cel_preset_export.json` に書き出す機能を実装する。
**この機能が step1 の完了判定に直結する。**

---

### T8. アウトライン（暫定実装）

配置: `res://shaders/cel/cel_outline.gdshader`

- `render_mode cull_front, unshaded, shadows_disabled;`
- `vertex()` で `VERTEX += NORMAL * outline_width * <深度補正>`
  - 遠景でも線幅を一定に保つため、ビュー空間Zに比例させること
- キャラ・プロップのマテリアルの `next_pass` に設定。メッシュの複製はしない
- **地形には適用しない**（タイルごとに縁取られて格子が浮くため）

#### 既知の問題（step2で対処）
`base.bbmodel` はハードエッジのため頂点法線が分裂しており、**角でアウトラインが裂ける**。
step1では許容し、検証シーンで線幅・色の当たりを付けることを目的とする。
恒久対応（スムース法線を `COLOR` または `UV2` に格納し、押し出しにはそちらを使う）は step2 で実施。

---

## 完了条件

以下がすべて満たされた時点で step1 完了とする。

1. `cel_validation.tscn` が起動し、F1〜F3のプリセット切替とライブ調整が動作する
2. 地形とキャラの影色が視覚的に統一されている（キャラだけ浮いて見えない）
3. キャラの落ち影が、地形のセル影と同じ段数・同じ色で描画されている
4. 改修後の地形テクスチャで、ランプ段差とテクスチャ模様が干渉していない
5. **プリセットを1つ選択（または調整）し、`cel_preset_export.json` を出力済み**
6. **上記の確定値を `docs/dev/cel_shading_spec.md` に転記済み**

`cel_shading_spec.md` には以下を含めること:
- 確定したランプ段数・全閾値・影変換パラメータ
- 光源方針（1灯 / energy 1.0固定 / 補助光禁止）
- アウトライン適用範囲（キャラ・プロップのみ、地形は非適用）
- 新規マテリアル作成時の遵守事項

---

## step2 への引き継ぎ

- 水・溶岩シェーダーのセル化（確定したランプに合わせる。2〜3段のベタ色＋動く白線のフォーム方式）
- スムース法線のベイク（アウトライン角割れの恒久対応）
- `bbmodel_to_glb.py` への法線出力オプション追加

---

## 補足: 作業順序の推奨

T4（palette）→ T1（shaderinc）→ T2/T3（マテリアル）→ T7（検証シーン）→ T6（Environment）→ T5（テクスチャ）→ T8（アウトライン）

T5 のテクスチャ改修は、検証シーンが動いてから着手した方が効率が良い。
「どの程度明度分散を削れば十分か」を目視しながら判断できるため。