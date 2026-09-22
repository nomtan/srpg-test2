# Character Model Phase 1.5 検証報告

対象: Adventure / Knight / Black Mage。作業指示は `character_model_phase1_5_fix_task.md`、規格は `character_model_standard_v1.md` と `character_model_standard_v1_1_addendum.md`。

## 出力と保護

各キャラクターの `prepared/phase1_5/` に `character.blend`、`body.glb`、`head_default.glb`、`palette_mask.png`、`validation.json`、`animations/common_combat.glb` を作成した。Knightには `body_albedo_clean.png`、`cape_mask.png`、`clean_albedo_audit.json` も出力した。分割の元面番号を `semantic_selection.json` に保存している。

raw、legacy prepared、prepared/phase1、および既存の共有Rig / Animationを含む115ファイルを、開始時のSHA-256と比較する。生成処理の前後および検証時に一致を確認する。既存アセットへの昇格とPhase 2の実装は行っていない。

## Skeleton / Rest / Retarget

必須20ボーンと既存の布用6ボーンについて、名前・親子関係・軸規約を共有する。Head、肩、肘、手首、股、膝、足首の位置と骨長、Bindは各rawの体型に合わせる。Masterの絶対Rest位置への体型合わせは行わない。

| 値（Blender Z、m） | Adventure | Knight | Black Mage |
|---|---:|---:|---:|
| HeadSocket高さ | 0.553 | 0.607 | 0.478 |
| 肩高さ | 0.460 | 0.503 | 0.365 |
| 股高さ | 0.245 | 0.209 | 0.175 |
| 足首高さ | 0.060 | 0.055 | 0.045 |

A-poseからT-poseへの変換では、nativeの腕角度とウェイトから逆スキニングを解く。元のA-poseを再適用した頂点の再構成誤差を記録する。T-poseへの腕の移動量と、Master体型へ合わせる変形は区別する。

唯一の制作元は `_shared/animations/common_combat.blend`。5 Actionを全フレーム読み、native腕角度との差と共通の足方向補正を適用して各キャラクターへBakeする。出力GLBはrotation trackのみ。Root translationは使わず、キャラクター別にwalkを作り直していない。共有Sourceは変更していない。

## Weightと接地

肩・腕・胴の連続的なウェイト分配、股中央のHips寄せ、裾のSkirt分配、背面のCape分配、革ポーチのHips寄せを実施した。UV分割で重複した同位置頂点を仮想的にまとめ、メッシュ上の隣接関係でウェイトを平滑化してから最大4 influenceに正規化する。Bodyの形状を平滑化する処理ではない。

足ボーンの姿勢はnativeの足裏方向に補正し、足首位置とRootを移動させずBakeする。Blender再読込検証ではwalkの全フレーム、他Actionの5時点について接地・頂点有限性・実際の姿勢変化・辺の伸長を測定する。辺の伸長値は診断値であり、それだけで外観合格とはしない。

## Head / BodyとSocket

raw面のUV色と解剖学的位置、隣接面を併用して分割した。Mageは首より低い左右・背面の髪もHeadへ含める。Headは骨なしのrigid GLBで、HeadSocketのローカル基準に合わせる。首下端には15 mmの重なりを持たせ、切断境界を閉じる。組み合わせ別offsetは使用しない。Eyes単体分離は実施していない。

Godotで4 Socketを5 Actionに対して検査する。HeadSocket→Head、WeaponSocket_R/L→Hand_R/L、BackSocket→Chest。キャラクターごとに20ケースを検査する。

## Palette / Emblem

Rをprimary、Gをsecondary、Bは未使用、Aはreservedとする。BodyのUV領域と衣装の色を使い、Headの肌・髪は対象にしない。primaryのみ、secondaryのみ、両方、originalをGodotで描画する。金属や装飾の境界についても画像で判定する。

Knightはprepared側のマントと前掛けのパネルを、元の青を基準に再ペイントする。色選択による部分修復では青地に紋章の影が残ったため、選択パネル全体を対象とし、元の紋章に依存しない位置ベースの陰影を付けた。透明な菱形・リングを別テクスチャとしてUV2に合成する。AdventureとBlack Mageは `supports_emblem: false`。

## 検証資料

- [3体×5 Animation](../../artifacts/character_phase1_5/animations_contact_sheet.jpg)
- [6 Head swap](../../artifacts/character_phase1_5/head_swaps_contact_sheet.jpg)
- [被弾時の6 Head swap](../../artifacts/character_phase1_5/head_swaps_hit_contact_sheet.jpg)
- [Body単体・前後](../../artifacts/character_phase1_5/body_split_contact_sheet.jpg)
- [Palette](../../artifacts/character_phase1_5/palette_contact_sheet.jpg)
- [Emblem](../../artifacts/character_phase1_5/emblem_contact_sheet.jpg)
- [rawとpreparedの比較](../../artifacts/character_phase1_5/native_pose_contact_sheet.jpg)
- [Blender計測](../../artifacts/character_phase1_5/blender_validation.json)、[Godot検査](../../artifacts/character_phase1_5/godot_validation.json)、[GLB構造検査](../../artifacts/character_phase1_5/portable_validation.json)、[保護ファイル検査](../../artifacts/character_phase1_5/preservation.json)

## 最終判定

最終再生成後の外観レビュー中。構造検査の成功を外観合格の代わりにはしない。Phase 2への進行は保留する。

## 再現方法

Blender 5.1.2で `tools/prepare_character_phase1_5.py` をbackground実行する。`-- --skip-preview` でBlender補助プレビューを省略できる。その後 `tools/verify_character_phase1_5_blender.py` を実行する。

Godot 4.6.1で `--rendering-method gl_compatibility --script tools/verify_render_character_phase1_5.gd` を実行して実描画を保存し、Python + Pillowで `tools/report_character_phase1_5.py` を実行する。Godotの `-- --verify-only` は画像を生成しないため、最終外観検証の代用にはしない。
