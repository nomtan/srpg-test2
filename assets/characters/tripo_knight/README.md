# Tripo騎士 — Toon / リグ / アニメーション

配置済みのTripo製 `knight+3d+model.glb` が対象です。元GLBは上書きしていません。

## Blenderで編集・比較

`knight_toon.blend` を開き、シーンを切り替えます。

- **Toon**：Eevee、Standard、露出0、Gamma 1。既定の表示です。
- **Original**：元のPBRマテリアル、Normal Map、法線を保持。同じリグ・アニメーション・カメラ・照明で比較できます。

マテリアルも `Original` / `Toon` として残しています。全テクスチャをblendにパックしているため、外部画像を探す必要はありません。

Toonは白いDiffuse BSDF → Shader to RGB → Constant ColorRamp（0.68 / 0.84 / 1.00）の明暗を、元のBase Colorに乗算し、Emission → Material Outputへ出力します。色補正や再ペイントは行っていません。照明は白いSun 1灯と弱い無彩色の環境のみです。

ToonにはPBRの反射、Normal Map、Bumpを使用しません。GLB書き出し用の `Toon_Export_Matte` もMetallic 0、Roughness 1、Specular IOR Level 0です。Base Color自体に描かれた明暗やハイライトは原画の一部として保持しています。

法線は32度を境界に角を維持し、UV境界の重複頂点を考慮して算出しています。形状・トポロジー・UVを変えず、細分化や全体を丸める処理を行いません。濃紺の細いアウトラインは別の反転ハルで、同じスケルトンとウェイトを使用します（厚さ0.0018、エリア内で約0.004）。

## リグとクリップ

26ボーン、全頂点に正規化ウェイト、1頂点あたり最大4ボーン。兜・バイザー・飾りはheadに100%固定し、歩行中も形が変わらないようにしています。鎧の関節、前垂れ、左右のマントを分けて制御します。

| アクション | フレーム（30fps） | 長さ |
|---|---|---|
| idle | 1–61 | 2秒 |
| walk | 1–31 | 1秒 |
| run | 1–21 | 2/3秒 |

すべてその場で動くループで、最終キーは先頭と一致します。BlenderのAction Editorでアクションを選択してください。NPCはその場でidleを再生し、冒険者の横の配置を維持します。

## Godot

エリアの `tripo_knight_npc.tscn` は `knight_toon.glb` を参照します。元サイズのGLBを2.25倍で配置し、身長は約2.2です。正面は+Z、足元はY=0。

Eevee専用のShader to RGBはGLBへそのまま移せないため、`knight_import.gd` がゲーム用の3段階シェーダーとアウトラインを適用します。照明による色かぶりと光沢を抑え、元Base Colorの色味を維持します。各クリップのループもインポート時に設定します。blendの直接インポートは無効です。

## 検証と再生成

`artifacts/tripo_knight/toon/validation.json` に元GLBとBase ColorのSHA-256、変更前後の形状・UVのハッシュ、ウェイトと全フレームの接地・ループ検証を保存しています。GLBに埋め込まれたBase Colorも元画像とバイト単位で一致します。

比較画像は同じフォルダー内の `original_standard_idle.png`、`toon_standard_idle.png`、`toon_agx_idle.png`。歩行・走行とエリア内の画像も保存しています。AgXとの比較後、青と金色の発色を保つStandardを採用しました。

```powershell
blender --background --factory-startup --python-exit-code 1 --python tools/prepare_tripo_knight.py -- --render
godot --headless --path . --editor --import
godot --headless --path . --script scripts/world_jrpg/verify_tripo_knight.gd
```

再生成は元GLBから行うため、Toon版に手動編集を加えた場合は別名保存してから実行してください。

ノード仕様：[Blender公式 Shader to RGB](https://docs.blender.org/manual/en/5.0/render/shader_nodes/color/shader_to_rgb.html)
