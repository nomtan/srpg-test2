# Character Model Phase 1 — 実施・検証レポート

対象指示: [character_model_phase1_blender_task.md](character_model_phase1_blender_task.md)

**判定: 構造検証用の試作を作成。外観の受入基準は未達。正式なゲーム用アセットへの置換、他6体への展開は行わない。**

作業日: 2026-09-22。Blender 5.1.2 / Godot 4.6.1。

## 1. 変更前の Inspection

最初に3体の raw GLB を Blender に読み込んで調査した。元GLBと既存 prepared ファイルは変更していない。詳細なオブジェクト名、全ボーン名、親子関係、座標、元Transform、境界箱、接続成分は [inspection.json](../../artifacts/character_phase1/inspection.json) に保存。

| Raw | メッシュ | 材質 / 画像 | リグ / ボーン | 頂点 / 三角形（キャラクター本体） | 身長 |
|---|---:|---:|---:|---:|---:|
| Adventure | 1 | 1 / 1 | 0 / 0 | 33,415 / 38,681 | 0.976631 m |
| Knight | 2（本体+Icosphere） | 1 / 1 | 1 / 67 | 33,751 / 42,068 | 0.979924 m |
| Black Mage | 1 | 1 / 1 | 0 / 0 | 34,880 / 43,286 | 0.978738 m |

- 全て元アニメーションは0。Adventure / Black Mage に元ウェイトはない。
- Knight の `Icosphere` は42頂点・80三角形の無材質補助球。全オブジェクトの境界箱では高さ2mになるため、本体と分けて計測。試作の出力からのみ除外した。
- 本体は Blender Z-up / -Y正面、足裏Z≈0。rawのglTFでは +Z正面であり、Godot -Z正面へ向きを補正する必要がある。
- Adventure / Black Mage は小さなXY平行移動があるが、Scale / Rotation は単位値。Knight は単位Transform。
- 頭・髪・服は同じ本体メッシュ。UV分割を位置で仮想的に接続した成分数はAdventure=5、Knight=2、Black Mage=8だが、最大成分にほぼ全身が含まれる。単純な「連結パーツ分離」ではHead/Hair/Bodyに分かれない。
- 正面・背面の画像では持ち武器・盾は見当たらない。
- Adventure は背面に一体化したスカーフの垂れ布。Knight は一体化したマントと焼き込み済み金色紋章。Black Mage はローブで、独立したマントは確認できない。

元画像: [Adventure 背面](../../artifacts/character_phase1/adventure_back.png) / [Knight 背面](../../artifacts/character_phase1/knight_back.png) / [Black Mage 背面](../../artifacts/character_phase1/black_mage_back.png)

## 2. Master Skeleton

Adventure の関節位置を基準に新規作成。Tripoの67ボーンをそのまま採用していない。必須20ボーンと、布用の任意6ボーンの計26ボーン。

```text
Root
└─ Hips
   ├─ Spine
   │  └─ Chest
   │     ├─ Neck
   │     │  └─ Head
   │     ├─ Shoulder_L → UpperArm_L → LowerArm_L → Hand_L
   │     ├─ Shoulder_R → UpperArm_R → LowerArm_R → Hand_R
   │     ├─ Cape_01_L → Cape_02_L
   │     └─ Cape_01_R → Cape_02_R
   ├─ UpperLeg_L → LowerLeg_L → Foot_L
   ├─ UpperLeg_R → LowerLeg_R → Foot_R
   └─ Skirt_01 → Skirt_02
```

3体で名前・親子関係・レスト行列を共通化。Blender再読込で行列誤差1e-5未満、Godotでも共通レストを比較した。左右の腕はT-pose。Body/Armatureの未適用回転・拡縮はない。静止時の足裏を0へ補正。BlenderではZ-up / +Y正面、GLB/GodotではY-up / -Z正面。

HeadSocket / WeaponSocket_R / WeaponSocket_L / BackSocketを出力。GLBのSocketは対応ボーンに対するローカル位置0・回転単位値。GodotでHead、左右Handの動きへの追従を検証する。

詳細: [skeleton.json](../../assets/characters/_shared/master_rig/skeleton.json)

## 3. 作成ファイル・3体の出力統計

既存 `prepared/character.blend` を保護するため、指示書の新規出力名許可に従い `prepared/phase1/` を使用。

各フォルダ:

```text
assets/characters/tripo_adventure/prepared/phase1/
assets/characters/tripo_knight2/prepared/phase1/
assets/characters/tripo_black_mage/prepared/phase1/
  character.blend
  body.glb
  head_default.glb
  palette_mask.png
  validation.json
  cape_mask.png     # Adventure / Knightのみ
```

共通:

```text
assets/characters/_shared/master_rig/master_rig.blend
assets/characters/_shared/master_rig/master_rig.glb
assets/characters/_shared/master_rig/skeleton.json
assets/characters/_shared/animations/common_combat.blend
assets/characters/_shared/animations/common_combat.glb
assets/characters/_shared/phase1_palette.gdshader
```

| 試作 | Body 頂点 / 三角形 | Head 頂点 / 三角形 | 材質 | Bodyボーン |
|---|---:|---:|---:|---:|
| Adventure | 19,799 / 22,997 | 14,332 / 16,312 | 元材質1を共有 | 26 |
| Knight | 25,635 / 31,595 | 8,788 / 11,041 | 元材質1を共有 | 26 |
| Black Mage | 21,413 / 25,050 | 16,167 / 20,524 | 元材質1を共有 | 26 |

首の平面カットによる交点追加で頂点・三角形は増加。Decimate / Remesh / LOD / Atlas化は実施していない。元画像の埋め込みバイト列はBody GLBでもSHA-256一致。

`character.blend` はBodyとHeadBaseを同じリグへ結合した編集用ファイル。`body.glb` はBodyメッシュ1個とSkeleton1個。`head_default.glb` はHeadボーンのローカル座標にした剛体メッシュで、追加Skeletonを持たない。Godotでは出力されたHeadSocketの子にそのまま追加する。

**Head GLBはボーンローカル基準であり、単体のワールドY-upモデルとして配置する用途ではない。** Blenderへ再インポートする場合の座標変換は検証スクリプトに明示している。

## 4. 共通アニメーションの再利用

`idle` / `walk` / `attack_melee` / `cast_magic` / `hit` を共有ファイル内に各1 Actionだけ作成。各キャラクターのblend、body.glb、head_default.glbにはActionを複製していない。Godotでも同じAnimationLibraryリソースを3体のAnimationPlayerへ設定し、全15通りでボーンが実際に動くことを確認する。

Root移動は0で、walkはin-place。これは完成モーションではなく変形検査用。`ko` はPhase 1対象外。

**外観は未合格。** 肩・袖・股下・ローブに局所伸びがある。歩行中の足裏沈み込みも残る。短い辺を除外した最大辺長比でもAdventure約5.06倍、Knight約6.86倍、Black Mage約14.73倍を検出。数値チェックの「動く」「有限座標」と見た目の「破綻しない」を区別する。

画像: [15通りのアニメーション](../../artifacts/character_phase1/animations_contact_sheet.jpg)

数値: [blender_validation.json](../../artifacts/character_phase1/blender_validation.json)

## 5. Head交換

指定の6組を追加位置補正なしで組み合わせ、画像とGodot追従を検証した。

| Body | Head | 外観判定 |
|---|---|---|
| Adventure | Knight | 基本位置は合う。首の動作確認を継続する必要あり |
| Adventure | Black Mage | 顎下に暗い隙間・切断境界が見えるため未合格 |
| Knight | Adventure | 基本位置は合う。首元の干渉を継続確認する必要あり |
| Knight | Black Mage | 顎下境界が見えるため未合格 |
| Black Mage | Adventure | 元の髪の一部がBody側へ残るため未合格 |
| Black Mage | Knight | 元の髪の一部がBody側へ残るため未合格 |

頭のサイズ補正はしていない。髪・Eyesの独立分離は、安全に保証できないため未実施。全身一体トポロジーをZ=0.55の平面で切るだけでは、Black Mageの長い髪と襟を正しく区別できない。

画像: [6組のHead交換](../../artifacts/character_phase1/head_swaps_contact_sheet.jpg)

## 6. Palette

元UVに沿う512×512の独立マスクを出力。R=primary、G=secondary、B=未使用、A=予約値1。元Albedoは保持。shaderはマスク領域だけを変更し、元明度を利用する。

| キャラクター | R画素数 | G画素数 |
|---|---:|---:|
| Adventure | 5,819 | 25,911 |
| Knight | 29,201 | 14,701 |
| Black Mage | 18,805 | 16,488 |

Godot実描画でRとGをそれぞれ単独に変更した。画像の左からsecondary変更 / primary変更 / 元色、上からAdventure / Knight / Black Mage。

**外観は未合格。** 自動推定したマスクには細かな抜け、ベルト・金属等への意図しない混入がある。Headとして分離した肌・髪・目は対象外だが、Black MageのBody側へ残った髪については除外を保証できない。量産前にUV上で領域を確定・修正する必要がある。

画像: [Godotでの独立色替え](../../artifacts/character_phase1/godot_palette.png)

## 7. Cape emblem

Adventureの垂れ布、Knightのマントにcape_maskとEmblemUV（第2UV）を用意。元UV/Albedoを壊さず `emblem_texture` / `emblem_color` / `emblem_enabled` で重ねるshaderを実装。Black Mageには適用しない。

実描画画像の左から透過ダイヤ / 不透明背景付きダイヤ / 元の背面。Adventureは垂れ布の範囲が細く、Knightは元の金色紋章が焼き込み済み。透過画像では元紋章が残る。不透明背景でもマスク境界に抜けがあり、完全な紋章差し替えは未合格。

画像: [Godotでの紋章重ね合わせ](../../artifacts/character_phase1/godot_emblems.png)

## 8. 検証結果と未解決事項

- raw 3ファイルのSHA-256一致、元画像バイト列保持、Bodyの単一Skeleton、Headの追加Skeletonなし、共通Action数、SocketローカルTransformを機械検証。
- GodotのGLTFDocumentで納品GLBそのものを読み込み、全クリップ再生・同一ライブラリ参照・ボーン比較・6組のHead追従・Socket追従を検査。
- Godot OpenGL Compatibilityでpalette/emblem shaderを実際に描画して画像保存。headlessでのパラメーター設定だけを描画確認の代用にしていない。
- `user://` のログ出力制約を避け、エンジンログは作業フォルダへ出力。OSの証明書ストア読取とshader cache書込に環境由来のエラーが残るが、GLB検査・画像保存は実行できた。PowerShellの終了コードだけで成功判定せず、検証JSONと完了マーカーを確認する。
- 最大の課題は**同一レスト行列への自動合わせ込みによるBlack Mageの体型・ローブ変形**。回転補正を除いた頂点移動の平均はAdventure約0.011m、Knight約0.040m、Black Mage約0.092m。Black Mageには最大約0.447mの移動があり、見た目維持の要件を満たさない。
- 肩・袖、ローブ、足裏、首の切断境界、残留する髪、マスクの精度、焼き込み紋章の扱いを修正するまで正式採用しない。
- ゲームの既存シーン・既存9体・既存preparedへの接続は変更していない。

構造検査結果: [portable_validation.json](../../artifacts/character_phase1/portable_validation.json) / [godot_validation.json](../../artifacts/character_phase1/godot_validation.json)。総合判定は [acceptance.json](../../artifacts/character_phase1/acceptance.json) に保存し、構造合格と外観未合格を別フィールドで管理する。

## 9. character_model_standard_v1 への変更提案

現行規格自体は変更していない。モデルをさらに強制変形して整合させる前に、次の定義を確定する必要がある。

1. **共通Skeletonの同一性を明文化する。** 名前・階層・軸が同じことと、全レスト位置まで同じことを区別する。現モデルの外見を優先する場合は、キャラクター別bind/restと共通回転アニメーションのretargetを許容する案が妥当。完全同一レストを維持するなら、生成段階で胴長・肩高・腕長をAdventureへ揃え直す。
2. **Head境界を高さだけで決めない。** 顔・髪・帽子は意味的なHead領域として切り出す。長髪の下端は首より下まで許容し、Body側に残さない。統一するのはHeadSocketの基準と首の接続領域であり、全ポリゴンの水平切断面ではない。
3. **座標の適用先を区別する。** Blender制作空間はZ-up、Godot/GLBワールドはY-up。剛体Headのローカル基底とSocketの基底は同一とし、二重のY-up変換をしない。
4. **マスクに意味領域の検収を追加する。** 2チャンネルが存在するだけでは合格にせず、肌・髪の混入なし、服領域の抜けなしをUV画像と実描画で確認する。
5. **既存紋章付きrawの扱いを追加する。** 透過overlayだけでは元紋章を除去できない。紋章なし生成を推奨し、既存モデルは別の無紋章Albedoを作るか、十分な不透明パッチ領域を許可する。元画像は保管する。
6. **移行中の出力パスを認める。** 既存preparedを保護する試作は `prepared/phase1/` に置き、外観合格後に正式ファイルへ移行する。

このレポートは「Phase 1全項目完了」の報告ではなく、再現可能な試作・構造検証と、未合格箇所の記録である。

## 再現手順

プロジェクトルートで実行。既存raw/legacy preparedには書き込まないが、この作業で作ったphase1出力は更新する。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python tools/inspect_character_phase1.py
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python tools/prepare_character_phase1.py
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python tools/verify_character_phase1_blender.py
& 'C:/Users/nomur/Desktop/godot/Godot_v4.6.1-stable_win64_console.exe' --headless --path . --log-file artifacts/character_phase1_godot_engine.log --script tools/verify_character_phase1.gd
python tools/report_character_phase1.py
```

実描画は `tools/render_character_phase1.gd` をGodotの `--rendering-method gl_compatibility` で実行する（headless不可）。新規の実装ファイルは上記5スクリプトに `tools/render_character_phase1.gd` と共通shaderを加えたもの。出力一覧・測定値は `artifacts/character_phase1/` と各 `validation.json` に保存。
