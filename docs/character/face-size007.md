# Face007基準のサイズ統一

> **廃止**: 全体幅基準は髪のボリュームに左右されるため、[顎幅基準](face-size-jaw.md)へ置き換えた。本書は当時の記録。

ユーザー指定により、現行Character007のFace横幅 **0.419525m** を基準とする。
FaceはHead + Hair全体。001〜006のmodular出力を等方縮小し、横幅を一致させる。
高さ・奥行きは髪型の違いがあるため、縦横比を保持して一律に変形しない。
Body、共有リグ、atlas、原本GLBは変更しない。

| Face | 以前の幅 | 縮小倍率 | 現行幅 |
|---|---:|---:|---:|
| 001 | .517023m | .811426 | .419525m |
| 002 | .517095m | .811312 | .419525m |
| 003 | .516975m | .811500 | .419525m |
| 004 | .524828m | .799359 | .419525m |
| 005 | .527325m | .795570 | .419525m |
| 006 | .524230m | .800271 | .419525m |

001〜006のnormalization.jsonへ新scale、旧scale／positionのsize_baselineを記録。
Legacyの顔面投影も同じ変換を施した`legacy_size007_NNN` ExpressionProfileへ変更。
GLB mesh extrasのexpression_profileをControllerが使用し、明示されたCharacterDefinitionのprofileがあればそちらを優先する。
Face ID別のruntimeサイズ補正、組合せoffsetは追加しない。
ExpressionUV v2にはこのlegacy補正を適用しない。
以前のgenerated/charcter001〜004はPhase2の比較用として保持し、現行rosterはmodular出力を使う。

Character007はscale .54を保持。FaceのBlender Zを.89→.84へ5cm下げて頂点へ焼き込み、
元Body007リグのhead追従を維持した。武器なし・walkのみも維持。

再生成: Blender MCPで`resize_faces_to_007.py`を実行。原本hashを確認し、UV0を保持。
007は`build_character007_sample.py`の位置.84で生成。
数値基準は`character_asset_standard_v1.json`のface_size／face_head_spaceへ更新した。

確認画像: `artifacts/face_size007/lineup.png`、007の正面／側面 × walk4時点。
測定: `artifacts/face_size007/measurements.json`。
36 Body/Face組合せ、4clip追従、legacy変換後center、60体expression isolation：PASS。
007のsample配置・unarmed・walk／停止検証：PASS。
