# Tripo Character Golden Path 実施記録

Blender MCPで2026-09-24に生成、2026-09-26にGodot検証を完了。
body/001 + face/001、続いて同一Body/Armature/Actionを維持してface/002を出力した。

## 原本の調査

| 素材 | Mesh | Armature / animation | 見た目 |
|---|---|---|---|
| Body 001 | `tripo_node_cf4e7507-1871-46b7-a1ce-8cd4c661279f`、33,024頂点 | `Armature`、Mixamo系65ボーン、animationなし | 首下の鎧・マント。不要な頭部なし |
| Face 001 | `tripo_node_34a503d6-f0e5-4c3a-86b7-f323d3974dc0`、22,468頂点 | なし | 頭部・耳。髪、目、眉、口の描画なし |
| Face 002 | `tripo_node_85712f2e-1fd0-4c78-84f4-02537dfa5be5`、33,704頂点 | なし | 頭部と前髪を含む髪。顔表情の描画なし |

いずれも1 material、512×512の埋め込みtexture。Body高さは約0.969016 m。
Face 001原寸高さは約0.952235 m、Face 002は約0.973212 m。
全bone名、parent、rest位置、元transform、画像名は各出力先の
`body_source_inspection.json` / `face_source_inspection.json` に記録。
glTF importerが作ったIcosphereはbone表示用custom shapeと確認して除去した。

## 最終構成と補正

`Character` → `humanoid_v1`（65 bones）→ `Body` / `Head`、共通の4 animations。
原本の階層とrest poseを保存し、`mixamorig:Head` のみ `head` へ変更。
Godotでは1つのSkeleton3DとAnimationPlayerとしてimportされた。
他のbone名はGodotの変換により `mixamorig_Hips` 等になる。

| Face | position（Blender XYZ、m） | rotation（度） | 一様scale |
|---|---|---|---|
| 001 | (0.0019, -0.0589, 0.89) | (0, 0, 0) | 0.52 |
| 002 | (0.0019, -0.0589, 0.89) | (0, 0, 0) | 0.60 |

補正は原本world transformを適用したmeshに焼き込み済み。首元は襟内へ重ねる。
Head全頂点をhead boneへ100% bindし、独立Face skeletonは追加していない。
Face 002は位置を共有する頂点で連結性を調べても頭部・髪が同じ大きな連結成分に
属するため、切断しない。HairがHead内に含まれることをmanifestに記録した。

materialは `Body` / `Head_001` / `Head_002` へ命名整理した。
テクスチャの描き直し、平滑化、板ポリの顔パーツ追加は行っていない。
既存UVとtextureを利用するHead materialが、今後の表情合成先となる。

## 出力

- `assets/characters/generated/golden_path_001/character.glb`
- `assets/characters/generated/golden_path_002/character.glb`
- Blender作業ファイル: `artifacts/golden_path/001/character.blend`、`002/character.blend`
- 再生成コード: `tools/asset_gen/character_pipeline/build_golden_path.py`
- fitを反映したmanifest: `assets/characters/tripo/characters/golden_path_001.json`、`golden_path_002.json`

Blender操作はBlender MCPから実施。Blender 5.1.2。
MCP旧アドオンの情報取得には制約があったが、Python実行・scene取得・描画は動作した。

## 検証結果

Godot 4.6.1でheadless検証とOpenGL描画検証の両方が終了コード0、
`GOLDEN_PATH_VALIDATION: PASSED`。

- 両GLBの単体instantiateと `BattleUnit.setup_visual()` が成功。
- 両方とも1 Skeleton、65 bones、headあり。BodyとHeadは同一Skeletonへbind。
- Body / Headの元テクスチャを読み込み、idle自動再生を確認。
- idle / walk / attack / hitが再生可能。idle / walkのみloop。
- 001のAnimation resource自体を002へ渡し、各clipの0 / 25 / 50 / 75 / 100%で
  全65 bone poseが一致。65 rest poseも一致。
- GLB内のBody頂点属性・indexバッファと、4 clipの全channelの入力・出力バッファが
  2体で完全一致。1 skin / 65 joints、画像はGLB内に埋め込み済み。
- 原本3ファイルのSHA-256が作業開始時と一致。
- 実際の `GridSystem` と `VoxelMap` の10×8セルの検証用領域へ配置。
  本番Mainシーンのユニット編成は変更していない。
- Blenderの正面・斜め描画とGodot描画で首の接続と顔・髪の追従を確認。
  既定のSRPGカメラsize=18でも頭部シルエットの差を確認できる。

証跡は `artifacts/golden_path/validation.log`、`render_validation.log`、
`integrity.json`、`godot_battle_distance.png`、`godot_{idle,walk,attack,hit}.png`。
Blender側の描画証跡は各generatedディレクトリのPNG。

再検証コマンド（リポジトリルート）:

```powershell
& 'C:/Users/nomur/Desktop/godot/Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script tools/asset_gen/character_pipeline/verify_golden_path.gd
# 描画確認は --headless を外し、末尾に -- --capture を追加
```

## 制約・後続事項

- 原本には目・眉・口の表情textureがない。Face 002の前髪が頭部表面の手前に
  描画されることは確認したが、**実際の目・眉textureに対する遮蔽テストは未実施**。
  Face Controller実装時に表面へ表情を合成し、追加検証する。
- Face 001には髪がないためHair nodeや前髪遮蔽は対象外。
- 動作はパイプライン検証用の簡易clip。production品質の剣攻撃、足接地IK、
  マント物理は含まない。全clipを全視点で網羅したアートQAではない。
- 実行環境の証明書ストア読込・shader cache書込エラーはログに残る。
  アセットの読み込み、描画、検証終了には影響しなかった。
- import時の既存Godot MCP addonクラス重複エラーはこの作業の対象外。
  runtime検証では当該editor addonを使わず実施した。

確定したbone命名、fit座標系、統合Hairの扱い、material名、loop設定を
`tripo-character-pipeline.md` 第11節へ追加した。表情関連の検証を残すため、
表情を含む全項目が完了したSpec v1としては扱わない。
