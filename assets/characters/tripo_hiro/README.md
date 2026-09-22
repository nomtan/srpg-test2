# 勇者 — Toon / リグ / アニメーション

入力はこのフォルダーの `hero.glb` です（GLB内のexporter表記はTripo）。元ファイルを上書きせず、加工版を `hero_toon.blend` / `hero_toon.glb` に分けています。

## Blenderで比較・編集

`hero_toon.blend` を開き、シーン選択を切り替えてください。

- **Toon**：Eevee、Standard、露出0、Gamma 1。通常はこちらを表示します。
- **Original**：元のマテリアル・メッシュ・法線を保持。同じリグ、カメラ、ライトで比較できます。

元のBase ColorはsRGBのままblend内へパックし、色補正・塗り直しを行っていません。頂点位置、面構成、UVも保持しています。変更前のマテリアルは `Original` として残しています。

Toonの構成は、白いDiffuse BSDF → Shader to RGB → Constant ColorRamp（0.68 / 0.84 / 1.00）→ Base Colorと乗算 → Emission → Material Outputです。色相を変えず、追加する光の明暗を3段階にしています。テクスチャ自体に描かれた陰影・ハイライトは元画像の一部として残ります。

PBRの反射、Normal Map、BumpをToonに使用していません。この入力GLBにはNormal Map自体がありません。GLB書き出し用の `Toon_Export_Matte` はMetallic 0、Roughness 1、Specular IOR Level 0です。

法線は32度を境界に角を保持し、UV境界の重複頂点を考慮して計算します。細分化・リメッシュ・デシメーションは行いません。輪郭は幅0.0018の濃紺の反転ハルで、同じスケルトンとウェイトを使用します。

確認用照明は白いSun 1灯と弱い無彩色の環境光のみ。HDRIは使用しません。StandardとAgXの比較画像を `artifacts/tripo_hero/toon` に出力します。

## リグとクリップ

26ボーン、全頂点に正規化ウェイト、頂点あたり最大4ボーン。顔と髪はheadに100%固定し、輪郭を保ちます。肩鎧、腕、手、脚、左右のマント、前垂れを分けて制御します。Armatureによる変形だけを使い、形を丸めるSubdivisionやSmoothモディファイアーは追加しません。

| アクション | フレーム（30fps） | 長さ |
|---|---|---|
| idle | 1–61 | 2秒 |
| walk | 1–31 | 1秒 |
| run | 1–21 | 2/3秒 |

その場で動くループです。Action Editorでクリップを選択してください。最終キーは先頭キーと一致します。

## ゲーム内の配置

`JRPGWorldSample` の開始地点で、騎士から `(-2.4, 0, -1.8)` の方向、距離3の位置に勇者NPCを配置しています。騎士と同じ向き・モデル倍率2.25（身長約2.2）で、足元は地形に合わせています。idleを自動再生し、接近時の会話とNPC衝突判定にも登録しています。

EeveeのShader to RGBはGLBへ直接移せないため、`hero_import.gd` がGodot用の3段階セルシェーダーとアウトラインを設定します。法線マップ・光沢・照明の色かぶりを追加せず、同じBase Colorを使用します。blendのGodot直接インポートは無効です。

## 再生成と検証

```powershell
blender --background --factory-startup --python-exit-code 1 --python tools/prepare_tripo_hero.py -- --render
godot --headless --path . --editor --import
godot --headless --path . --script scripts/world_jrpg/verify_tripo_hero.gd
godot --path . --script scripts/world_jrpg/verify_tripo_hero.gd -- --capture
```

実行ファイル名は各環境に合わせて読み替えてください。再生成は元GLBから行うため、Toon版を手動編集した場合は別名保存してから実行してください。

`artifacts/tripo_hero/toon/validation.json` に元GLB・Base ColorのSHA-256、変更前後の形状・UVハッシュ、全フレームの接地・ループ検証を記録します。GLB内のBase Color画像も元画像とバイト単位で一致することを確認します。
