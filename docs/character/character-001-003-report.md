# Character 001 / 002 / 003 作成記録

2026-09-26。差し替え後の素材をBlender 5.1.2 + Blender MCPで処理。

| ID | Body | Face | 出力 |
| --- | --- | --- | --- |
| charcter001 | 001 | 001 | assets/characters/generated/charcter001/character.glb |
| charcter002 | 002 | 002 | assets/characters/generated/charcter002/character.glb |
| charcter003 | 003 | 003 | assets/characters/generated/charcter003/character.glb |

IDは依頼の `charcter001` 表記に合わせた。画面表示は `Character 001` 等。
manifestは `assets/characters/tripo/characters/charcter00{1,2,3}.json`。

## 素材とリグ

- Body 001: 1 Mesh、1 Armature、65 bones、11,175頂点。元から首より下のみ。
- Body 002: 1 Mesh、リグなし、8,552頂点。
- Body 003: 1 Mesh、リグなし、8,887頂点。
- Face 001/002/003: 各1 Mesh、リグなし、7,582 / 7,122 / 7,023頂点。全て髪と頭が一体。
- 全素材にアニメーションなし。元のUV・色テクスチャを保持し、頭髪の破壊的分離は行わない。
- Tripo auto rigはBody 001だけを使用。65 bones/rest poseを全キャラクターで共用。
  `mixamorig:Head` のみ `head` へ変更。他のボーンはGodotで `:` が `_` になる。
- Body 002/003は高さを001へ一様スケールで合わせ、001の最近傍三角形から
  重心座標補間でウェイト転送。上位4影響を正規化し、未ウェイト頂点は0。
- 最終出力は各1 scene / 1 skin / Body + Head。Face全頂点は `head` weight 1。
- 原本6ファイルは作業前後のSHA-256一致を確認。値・元構造・転送距離は各出力先の
  `build_report.json` に記録。

## フィット

Blender Z-up、単位m。Faceのsource world transformにscale、その後translationを適用しmeshへ焼き込む。

| Face | 一様scale | translation (X, Y, Z) |
| --- | --- | --- |
| 001 | 0.5395 | (0, -0.055, 0.89) |
| 002 | 0.536 | (0, -0.055, 0.89) |
| 003 | 0.63 | (0, -0.055, 0.79) |

003は長髪が下へ伸びるため、髪先ではなく顎と襟の位置を基準に合わせた。
2026-09-27のFace 003差し替え後、3体の頭幅を約0.517mへ統一した。
最終頭幅は001が0.5170m、002が0.5171m、003が0.5170m。
正面idle・walkと斜めattackを描画して、首元と髪の位置を確認した。
runtimeのroot/armature transformはidentity、接地面はほぼ0。
サンプルのラッパーsceneでは全体を1.35倍に表示する。

## アニメーション・サンプル

既存Golden Pathの `idle` (2秒) / `walk` (1秒) / `attack` (1秒) / `hit` (0.8秒)
を共用。idle/walkはimport hookでloop。いずれも互換性確認用の簡易動作。

`samples/JRPGWorldSample.tscn` のplayerと切り替え候補はこの3体のみ。
Vキー、左スティック押込み、探索中のBボタンで切り替えられる。
run未収録のため走行時は既存のwalkフォールバックを使用。

## 検証

- `scan_sources.py`: 成功。
- `verify_characters.gd`: PASSED。単体instantiate、BattleUnit表示、単一Skeleton、
  Body/Headのskin、トゥーン材質と元テクスチャ、65 bonesと同一rest poseを確認。
  4クリップのhead変化、root motionなし、同じAnimation resourceを他2体で再生する検証も成功。
- `verify_tripo_switching.gd`: PASSED。全3枠をidle/walk/runで循環、位置・向き・歩行位相・HUD保持。
  会話/戦闘中の切り替えも確認。
- Blenderで正面idle/walkと斜めattack/hitを描画確認。
- Godotで戦闘グリッドと実際のJRPGWorldSampleを描画確認。
- 画像・検証ログ・作業blend: `artifacts/character_batch/` (`.gdignore`付き)。

Godot editor import時、既存MCPアドオンのグローバルクラス重複エラーと、サンドボックス外の
editor settings保存エラーが出た。キャラクターimport自体と上記runtime検証は成功。
描画検証時にも環境の証明書ストア・shader cache書き込み警告あり。

## 対象外・制約

- 目・眉・口の表情配置は未実施。今回の新規3体は素材の顔テクスチャをそのまま使用する。
  旧FaceControllerの顔形状依存の投影値を新しい顔へ流用していない。既存Golden Pathの表情処理は維持。
- 既存の剣装備用スクリプトは別ボーン命名規約のため、新3体へ剣装備・専用斬撃は追加しない。
  GLBの `attack` / `hit` は再生可能。
- 共通ウェイトは簡易クリップで確認済み。将来の大きな可動域の動作には服の追加調整が必要になりうる。

## 再生成

Blender MCPから `tools/asset_gen/character_pipeline` をPython import pathへ追加し、
`build_characters.build('001')`、`build('002')`、`build('003')` の順に実行する。
新しい作業シーンを追加して既存シーンを保持し、active sceneの選択物だけをexportする。
既存シーンとexport用オブジェクト名が衝突する場合は別のBlenderセッションを使う。
Godot import後、以下を実行する。

```text
godot --headless --path . --script tools/asset_gen/character_pipeline/verify_characters.gd
godot --headless --path . --script scripts/world_jrpg/verify_tripo_switching.gd
```

描画証跡が必要な場合は `--headless` を外して `-- --capture` を末尾に追加。
