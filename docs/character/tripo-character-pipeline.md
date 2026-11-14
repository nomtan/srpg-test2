# Tripo キャラクターパイプライン — Phase 3

> Phase 5の新規Face描画契約と現在の未完了事項は [Face Expression Rendering v2](face-expression-rendering-v2.md) を参照。旧Face001〜006の描画とAPIは維持する。

> 現行Face 001〜010は目・鼻・口を描き込んだTripo原本（`baked_face_features: true`）で、表情オーバーレイは使わず陰影なしで描画する。サイズは[目・顎のFace002基準](face-size-jaw.md#目顎のface002基準eye_jaw_face002_v1)（兜のFace005のみ例外）。旧[Face007基準のサイズ](face-size007.md)と顎幅単独基準は廃止。下記のPhase3測定・default profile説明は当時の記録。

> Phase 4 以降の正式規格は [Ashen Vow Character Asset Standard v1](character-asset-standard-v1.md) と [Golden Path](character-asset-golden-path.md) を優先する。本書は Phase 3 の実装経緯と互換仕様を記録する。

新しいキャラクターは Body と Face の2部品で構成する。Face は頭部と髪を含む1つのパーツであり、髪型を変える場合は別の Face ID を制作する。目・眉・口だけを Face の材質上で独立して切り替える。旧 `charcter001`〜`charcter004` の ID はシーン参照との互換性のため保持する。

```text
Tripo Body → Blender正規化 → modular/body/NNN/model.glb ─┐
                                                       ├→ CharacterAssembler → Character
Tripo Face (頭部 + 髪) → Blender正規化 → modular/face/NNN/model.glb ─┘        └→ ExpressionController
                                                                                  ├ Eyes
                                                                                  ├ Eyebrows
                                                                                  └ Mouth
```

## 原本と命名

- `assets/characters/tripo/{body,face}/<3桁ID>/model.glb` は原本。絶対に上書きしない。
- 正式出力は `assets/characters/modular/{body,face}/<3桁ID>/model.glb`。各IDの `normalization.json` にその部品だけの補正を記録する。
- `CharacterDefinition` は `body_id`、`face_id`、任意の `expression_profile_id` を持つ。表情の現在状態は保存しない。
- ID例: `body001`、`face001`、`expression_angry`、`eyes_blink`、`eyebrows_angry`、`mouth_open`。

## humanoid_v1

`assets/characters/_shared/rigs/humanoid_v1.glb` が正式な Reference Rig。65ボーンの名前、親子関係、全rest translation/rotation/scale、および `head`、root/hips を規格として固定する。リグ内のBody001由来メッシュは新しいBodyへのウェイト転送専用の donor であり、他のBodyの実行時メッシュには含めない。`create_reference_rig.py` はPhase 2のBody001からこの規格を固定した一回限りの移行スクリプトである。通常の新規Body出力はこの共有GLBを読み、Body001原本は読み込まない。

Bodyは唯一のSkeleton、`idle` / `walk` / `attack` / `hit` の4クリップを持つ。Faceは静的メッシュで、Skeleton、skin、animationを含めない。Faceの頂点は共通Skeletonのrest空間に置く。Godotでは `head` ボーンの `BoneAttachment3D` に `FaceSocket` を置き、その下にFace全体を装着する。`get_bone_global_rest(head_index).affine_inverse()` を一度だけ適用する。Body/Faceの組み合わせ別のランタイム補正は原則持たない。例外として、Faceを本来合わせたBodyとは別のBodyに載せるときだけ、`CharacterDefinition.face_offset`（rest空間、+Zが前）でFaceを平行移動できる。同じ場合に限り `CharacterDefinition.face_scale` でFaceを `head` ボーンの関節（首の接続位置）を中心に等方拡縮できる。charcter002で使っていた `face_offset (0, 0.01, -0.025)` / `face_scale 1.05` は、現在は全Faceの `normalization.json` に焼き込み済みで、定義側の補正は持たない。

Blenderはメートル・Z-up、GodotはY-up。出力root、Armature、mesh objectのtransformはidentityとし、正規化は頂点へ焼き込む。

## 部品出力と検証

Blender 5.1で原本と同じIDを指定し、部品ごとに別プロセスで作業領域へ出力する。

```powershell
python tools/asset_gen/character_pipeline/scan_sources.py
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind body --id 005 --output-root artifacts/modular_direct
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind face --id 005 --output-root artifacts/modular_direct
python tools/asset_gen/character_pipeline/validate_modular_parts.py --root artifacts/modular_direct
```

`normalization.json` の任意項目 `source_file` で同じTripoフォルダ内の別原本を指定できる（`source_sha256` はそのファイルのハッシュ）。`baked_face_features: true` はテクスチャに目・眉・口が描き込まれたFaceを示し、GLB node extrasに出力され、`CharacterAssembler` が表情オーバーレイを非表示にする。このFaceはテクスチャに陰影も描き込まれているため、Tripoでの見え方に合わせてトゥーンの陰影帯と受ける影を付けず、テクスチャ色をそのまま表示する（shader `shade_strength = 0`）。組み合わせるBodyも同じ表示にそろえ、FaceとBodyで光の当たり方が違って見えないようにする。Face002は `face+facial.glb` を原本とする。

Body 002〜014 の `normalization.json` は `rest_fit: "landmarks_v1"` を持ち、Body001（donor）を基準にrest空間へ合わせる。縮尺は全高ではなく胴体中央（|x|<0.12m）の最上点で決め、肩の羽飾りなど横に飛び出た部品で縮まないようにする（旧方式ではBody009が約5%小さかった）。続けて首元（z 0.86〜0.90m）と足首（z 0.07〜0.10m）の断面中心が001と同じ前後位置に来るようYを平行移動する（ローブやマントで断面の奥行きが読めない区間は使わない）。旧方式はX中心と足裏しか合わせず、003/005/008などが共通スケルトンより4〜7cm後ろにずれ、脚ボーンが脚の中心から外れて歩行が崩れ、Faceが首から前に浮いていた。Body 008・010の原本は65骨リグ付き・約3.4万頂点のため `source_rig: discard` と `decimate_ratio: 0.21` を使う。Body009は2026-10に別デザイン（リグなし・約1.2万頂点の静的メッシュ）へ差し替えたため、どちらも使わない。Body011（2026-10追加・同月に鎧デザインへ差し替え、リグなし・約1.55万頂点の静的メッシュ）も同様で、`arm_alignment: "whole_arm"` のみを使う（`arm_spread` なし。原本の両腕は約12°ずつ振れている）。Body012〜014（2026-10追加、リグなし・約1.4〜1.5万頂点）も同じく `arm_alignment: "whole_arm"` のみ（右腕が約26〜34°前へ振れている。`face_offset`・`arm_spread` なし）。対応するFace011〜014はないため、`capture_body_gait.gd` は同じIDのFaceがないBodyにFace001を載せて撮影する。

humanoid_v1は左右対称である（2026-10、`symmetrize_reference_rig.py`）。Body001のTripoリグは右前腕が約13cm前へ曲がり、ロールも左と逆、右手の指ボーンは手首に潰れ、右膝も7mm後ろにあった。全Bodyがこのrestを共有していたため、歩行・走行で右手だけ曲がり方とねじれが左と違っていた。現在は Right* の全ボーンが Left* の鏡像（中心は Hips のX、Blenderのロール反転規約）で、donorメッシュの右腕も肩・肘を軸に鏡像の左腕へ回し、正中より右の頂点は鏡像の左側ウェイトを持つ。これに合わせ Body 007 は `arm_alignment: "match_rig_source"` で、ウェイト転送前に腕の向きをdonorへ合わせる（Tripo原本も右前腕が前に曲がっている）。`match_rig_source` は上腕を肩〜肘の数cmだけで直線近似するため、肩パッドや袖口で中心線がぶれる。002ではdonor右側のサンプルだけが約20°下を向き、右腕だけ下がって脇が締まり、左は肘が外へ張っていた。002・003・005・006は `arm_alignment: "whole_arm"`（`align_whole_arms`）で、左右それぞれ肩〜手首の1本の直線を、肩を中心にdonorの左腕の向き（右はその鏡像）へ回す（002は原本の腕全体が約20〜35°前へ振れている。003・005・006も `match_rig_source` では右腕だけ大きく下がり手が体に寄っていた（003は左腕が上がり袖の下端が裂けていた）。003・006を `none` にすると右手がidleで約15cm前に出る）。004は原本の両腕がほぼ左右対称で、`match_rig_source` だと右腕だけ下へ引かれ、さらに下記 `right_arm_fit` で前腕が肘で折れ手袋の一部が腕の下に残ったため、`arm_alignment: "none"` で原本の腕をそのまま使う（idleで右腕もまっすぐ垂れ、脇の開きは左と同じ）。`arm_alignment` はベルトより上の腕しか見ないため、Tポーズで右手袋が下へ垂れているBodyは idle で手がポーチの裏に入り脇が締まって見える。その場合は `right_arm_fit: "mirror_left"` で、ウェイト転送前に右前腕+手を肘中心でそのBody自身の鏡像の左へICPで合わせる（`fit_right_forearm`）。ポーチに接した手袋は位置で分けられないので、腕の高さより下の頂点は回すと鏡像の左面に近づくものだけを動かす。009（2026-10差し替え後）も原本の右腕が約23°前へ振れており、`arm_alignment: "whole_arm"` を使う（`arm_spread` なし）。009の袖は手首から下へ大きく垂れる広袖で、Tポーズでは袖の下端（z≈0.60、|x|≈0.25〜0.36）がdonorの腰の横に来るため、最近傍転送では袖口の縁だけ Hips/UpLeg のウェイトになり、隣の ForeArm の頂点と引き裂かれて idle・歩行で腰の横に黒いトゲが出た。Bodyの `normalization.json` の任意項目 `sleeve_weights`（`{"min_abs_x": m, "min_z": m}`、rest空間）は、腕の向き合わせ後に |x|≥min_abs_x かつ z≥min_z の頂点のウェイトを、donorの同じ側の腕（Shoulder/Arm/Hand系が支配的な三角形）だけから転送し直す（`rebind_sleeves`）。009は `{"min_abs_x": 0.24, "min_z": 0.55}`。腰のポーチやタッセルは |x|<0.24 にあり対象外。008・010は原本の右腕が肩から全体で約25〜30°前へ、左腕はやや後ろへ振れている。`match_rig_source` では右腕だけポーチの裏へ入り、`none` + `right_arm_fit` では上腕が前に出たまま前腕だけ戻るので肘で前へ折れた。`arm_alignment: "whole_arm"` で両腕を肩から1本の直線としてそろえ、ローブとポーチが太く手が隠れるため `arm_spread` `{"left": 10, "right": 10}` で両腕を脇から開く。原本の右腕自体が長いBody（001、009など）は手先がわずかに長く出るが、ボーンと動きは左右対称である。donor（Body001）はさらに、右前腕+手（肘中心）と右の靴（足首中心）を鏡像の左へICPで合わせる（靴はつま先が約4°上がっていた）。右手袋は左のように手首で曲がらずまっすぐで約5cm長く、idleで拳が低くポーチの前に垂れ、手首が内側へ曲がって見えたため、`match_right_hand` がidleの腕姿勢（`arm_hang`）で右前腕+手を肘中心、拳を手首中心にそれぞれ鏡像の左へICPで合わせ（ねじれも含む）、最後に肘から拳までの距離が左と同じになるよう前腕+手を肘→拳方向に縮める（約0.88倍）。donorの右手は他Bodyの `arm_alignment` の基準でもあるため、002〜010の右手も左とそろう。このスクリプトは対称化前の原本リグ（HEADの `humanoid_v1.glb`）に対して実行する（対称化済みのリグに再実行すると腕が二重に曲がる）。`scripts/world_jrpg/gait_cycle.gd` の歩行・走行は両腕とも同じ `_aim` で作り、半周期ずらした左右の手が位置・向きとも一致する。

4クリップの腕は `build_golden_path.arm_hang` で自然に垂らす（`ARM_HANG`: 上腕は鉛直から22°、前腕16°・肘を前へ10°、手は前腕と一直線）。restはTポーズで前腕が前に曲がり手首も傾いているため、以前のように上腕だけを肩で0.75rad下ろすと、前腕が外へ突き出し手首が折れて見えた。各腕ボーンをrestの向きから目標方向へ最小回転させるので、手のひらは腿の方を向く。各クリップの腕の回転（walkの振り、attack）はこの垂れた腕を基準に掛ける。Bodyの `normalization.json` の任意項目 `arm_spread`（`{"left": 度, "right": 度}`）はそのBodyの片腕だけ上腕・前腕をさらに脇から開く。袖や手袋が体に寄って見えるBody用で、現在値は001 `{"right": 5}`、008・010 `{"left": 10, "right": 10}`。idleは歩行・走行の基準ポーズでもある。

襟やフードが首より高いBodyは、Faceの顎が襟に埋もれる。Bodyの `normalization.json` の任意項目 `face_offset`（Godotのrest空間、+Y上・+Z前、メートル）でそのBodyに載る全Faceを平行移動する。`build_modular_parts.py` がArmatureノードのextras `face_offset` に書き、`CharacterAssembler` が `CharacterDefinition.face_offset` に加算する。Body/Faceの組み合わせ別補正ではなく、Body自体の首の高さの性質として扱う。現在値: 004 `(0, 0.01, 0.005)`、006 `(0, 0.02, 0.01)`、007 `(0, 0.01, 0.005)`、008 `(0, 0.015, 0.01)`、009 `(0, 0.015, 0.025)`、010 `(0, 0.015, 0.015)`、011 `(0, 0.02, 0.015)`（高い襟）。確認は `capture_body_gait.gd`（全Bodyのidle/歩行/走行の正面・側面と頭部の拡大を `artifacts/body_gait/` へ撮影、引数 `NNN=x,y,z` で試し値を上乗せ）で行う。

`DIRECT_MODULAR_EXPORT` をBlenderログで確認する。検証後に正式ディレクトリへ配置し、Godotでインポート、実行時検証、目視確認を行う。`validate_modular_parts.py` は共有Reference RigとBodyの全65ボーンrest、4クリップ、Faceのskin/animation不在とtransformを照合する。rest成分の許容差 `2.5e-5` はBlenderのglTF再入出力による浮動小数丸めを吸収するための値である。

## 表情

`assets/characters/_shared/face/expression/` の透過SVG atlasはGodotにTexture2Dとして読み込む。`build_expression_atlases.py` で再生成できる。各行は256×256の顔面投影画像で、Eyes 8種、Eyebrows 6種、Mouth 7種。パーツは256グリッドで描いた後、`FEATURE_SCALE`（0.72）で中心(128,128)へ縮小し、髪を含む投影矩形ではなく肌の範囲に収める（線幅は√scaleで縮小）。`ExpressionController` の配列順序とatlasの行順は同一のアセット契約である。3つのatlasとトゥーンshaderは全個体で共有し、shader parameterを持つFace材質だけを個体ごとに複製する。Meshは共有する。表情変更時にMesh、Texture、Node、Shaderを生成しない。

`definitions/expression_*.tres` はプリセットの3チャンネルを定義する。初期プリセットは `normal` / `angry` / `smile` / `sad` / `surprised`。`ExpressionProfile` は顔面投影範囲と正面側の深度を定義し、Definitionの `expression_profile_id` が空なら `profiles/default.tres` を使う。現行Faceは1メッシュでUV島も共通ではないため、1つのFace材質内でrest座標から投影して合成する。前髪より前に常時表示する別メッシュは生成しない。

```gdscript
character.set_expression("angry")
character.set_eyes("blink")
character.set_eyebrows("confident")
character.set_mouth("open")
```

ロスター表示とBattleUnitも同じAPIを中継する。表情とアニメーションは独立する。自動瞬きとリップシンクはこの段階では実装しない。

現行atlasの図柄は参照モデル `assets/characters/tripo/paical/sample/model.glb` のチビアニメ調に合わせている（縦長の角丸ウォームグレー虹彩を上暗・下明の2トーンで段差をつけ、極小ハイライトと細い縁取り。太くほぼ水平な焦げ茶の上まつ毛は目尻で下へ跳ね、白目は目頭・目尻で肌へフェード、下まぶた線なし。薄い二重線、細く薄い眉、小さくやや下向きの口）。SVGは `svg/scale=2.0`・mipmap有りでimportする。`capture_face_features.gd` で全Faceの表情を `artifacts/face_features/` に撮影できる。

Legacy Face（001・003〜007）の目・眉・口はFace002（`face+facial.glb`）の描き込みと位置・テクスチャを一致させる。`build_face002_feature_atlases.py`（Blender）がFace002の正面肌レイヤーを `legacy_size007_002` の `face_rect` へ投影し、肌色に対してキーイングして `legacy_{eyes,eyebrows,mouth}_atlas.png`（1行512×512、行順はSVG atlasと同じ）を書き出す。`normal` 行はFace002の画素そのもの（左眉は前髪に隠れるため右眉の鏡像）、他の行は同じ画素を変形（まぶた圧縮・まつ毛のみの閉じ目・眉の傾き）し、口はFace002の口の色で描く。全legacy profileの `face_rect` はFace002と同一で、同じtexelが同じrest座標に乗る。Face002の目は顔の側面まで回り込むため、`surface_depth.x` は従来値より2cm手前を許容する（さらに下げると肌深度マップが後ろ髪を拾い、目が消える）。`ExpressionController` はUV2を持つv2 Faceには従来のSVG atlas、legacy投影Faceにはこのatlasを渡す。Face002の画像を更新したら、atlasと肌深度マップを再生成する。

Legacy Faceの表情は、GLB node extras の `expression_profile`（Godotでは `extras` meta）で各Faceの `legacy_size007_NNN` profileを使う（以前はこのmetaを読めず、全Faceが `default.tres` で描画されていた）。profileの `skin_depth` は `build_skin_depth_maps.py` が焼く肌の深度マップで、shaderはその深度＋4mm以内にだけパーツを描く。Tripo Faceは前髪の裏に肌が無い殻なので、正面最奥の層に4次多項式を当て、手前に3mm以上浮いた領域を髪として扱う（鼻・口の膨らみは境界の段差3mm未満かつ閉じた／顔下半分の領域として肌に戻す）。これにより前髪が目を自然に隠し、前髪上に目の断片が乗らない。Face再生成やprofile変更時はマップを再bakeする。Face 001〜004は単一メッシュ・単一材質で、細かな島が数百個あり、頭部と髪を安全に分割できる境界がない。肌側の深度に限定すると前髪が顔全体を遮り、表情が見えなくなる。別の板ポリは使っていない。正式アートでは、Face制作時に頭部と髪を識別できるmaterialまたはmaskを用意し、shaderで髪上への合成を抑える。原本の描画やgeometryは破壊的に変更していない。

## 回帰確認

```powershell
python tools/asset_gen/character_pipeline/validate_modular_parts.py
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --headless --path . --log-file artifacts/phase3_verify.log --script tools/asset_gen/character_pipeline/verify_modular_parts.gd
```

Godotテストは4 Body×4 Face、単一Skeleton、4クリップ中のhead追従、ロスター/戦闘経路、60体でのMesh/Texture共有と表情材質の個体分離を確認する。`capture_expressions.gd` はFace001/002の4状態を撮影し、`capture_main_camera.gd` は実ゲームカメラで5体の表情を撮影する。結果は `artifacts/phase3_face*.png` と `artifacts/phase3_main_expressions.png`。

## 敵モデル（enemy）

`assets/characters/tripo/enemy/<id>/model.glb` は敵1体分の静的メッシュ原本で、Body/Faceと同様に上書きしない。humanoid_v1は使わず、`tools/asset_gen/character_pipeline/build_enemy.py` がモデル自身の姿勢に合わせた小さなSkeleton（Root + 19ボーン）を作り、`assets/characters/enemy/<id>/model.glb` へ出力する。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_enemy.py -- --id goblin --preview artifacts/enemy_preview   # ウルフは --id wolf、グリムは --id grimm、スケルトンは --id skeleton
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script scripts/world_jrpg/verify_enemy.gd
```

- 浮遊物の削除: 1.5cm以内の頂点をつないだ塊のうち、`remove_inside` の箱に収まるものを消す。ゴブリンは背後に浮いていた布片（537頂点）と小片（68頂点）。
- 装備の分離: 握っていた曲刀（柄から刃先への軸からの距離で判定）と円盾（独立した塊）を本体から切り出し、`assets/characters/enemy/equipment/{weapon,shield}/<id>/model.glb` に出力する。武器GLBは握りの座標系（原点=拳の中、+Y=刃先方向、+X=刃の幅方向）、盾GLBは盾の座標系（原点=裏面中央、+Z=表面、+Y=上）で置く。本体GLBはArmatureのextras `weapon_socket`／`shield_socket`（bone・origin・basis、glTF軸、rest空間）にその座標系の位置を記録する。
- 装備ライブラリ: `EQUIPMENT` がプロジェクトの武器原本（`assets/weapons/...`、読み取りのみ）を同じ座標系へ置き直して出力する。現在は武器 `scimitar`（ゴブリン原本）・`hand_axe`（両手斧002を0.52倍）・`longsword`（片手剣001.glbを0.72倍）・`staff`（杖001を0.82倍）、盾 `round`（原本）・`kite`（盾001を0.55倍）。
- スキン: Tripoメッシュは数百の島に分かれているため、ボーン線分までの距離でウェイトを付け、半径2cmで平滑化して隣の島と一緒に動かす。
- クリップ: `idle`・`walk`（ループ）、`attack`・`guard`・`hit`・`death`（最終フレームで停止）。その場モーションで、移動はゲーム側が行う。`death`（4.1秒）は大きく上を見上げ、力が抜けて腕が垂れ膝が折れ、膝をついてからスローモーションのようにゆっくりかかとの上へ座り込み、上体を前へ丸めて頭と腕を垂らす（横や後ろへは倒れない）。キーは通常の速さ（膝つき38→座り込む60フレーム）で書き、`DEATH_PACE`（1.5）倍に引き延ばす。膝をついた時点からは最下点が地面に来るようRootを上下させ、宙に浮かずに地面に沿って崩れる。
- Godot: `scenes/characters/enemies/goblin.tscn`（`scripts/character/enemy_character.gd`、Modelは2.025倍）と、継承シーン `goblin_axe`（片手斧+円盾）・`goblin_longsword`（ロングソード+カイトシールド）・`goblin_staff`（片手杖、盾なし）。`weapon_id`／`shield_id` をインスペクタで選ぶか、実行中に `set_weapon(id)`／`set_shield(id)` で差し替える（`none` で外す）。装備は `RightHand`／`LeftHand` の `BoneAttachment3D` 下に `get_bone_global_rest().affine_inverse() * socket` で付く。
- 描画と消滅: 本体・装備とも `enemy_dissolve.gdshader`（Tripoの描き込み陰影を保つ無陰影表示）。夜はグローバルシェーダ変数 `night_tint` を掛けて暗くなる（消滅時の燃える縁は暗くしない。同じシェーダのフィールドのドラゴンも同様）。インスタンスごとの `dissolve` で、倒れた後にノイズ状に燃える縁を残しながら崩れ、骨に沿って灰と火の粉が舞い上がる（CPUParticles3D）。2秒後に最初の位置へ戻り、逆向きのdissolveで現れる。
- `JRPGWorldSample2` は `field_enemies` の7体（ゴブリン4体＋ウルフ＋グリム＋スケルトン）を出現位置の7.5m前に3.2m間隔で並べる。全員 `idle` で立っているだけ（自動で動くデモは無し。`enemy_character.gd` の `demo` は検証用に残る）。攻撃が当たると `hit`／ときどき `guard`、`max_hp` 発目（既定3、スケルトンは4、グリムは5）で倒れて塵になる。

### ウルフ（wolf）

`--id wolf` で同じスクリプトから作る。武器・盾は持たないので装備の分離とソケットは無く、本体GLBだけを出力する（原本は1つの塊で浮遊物も無い）。

- Skeleton（Root + 23ボーン、四足）: `Hips → Spine → Chest → Neck → Head → Jaw`、`Hips → Tail → Tail1 → Tail2`、前脚 `{Left,Right}Shoulder → Arm → ForeArm → Hand`（肩甲骨・上腕・前腕・前足）を `Chest` から、後脚 `{Left,Right}UpLeg → Leg → Foot`（腿・すね・飛節から先）を `Hips` から。
- 原本は胴がやや斜め（胸の中心 x=-0.1、腰 x=+0.07）なので、左右の脚のウェイトは x=0 ではなく `midline` の線を境にする。
- 原本のテクスチャは体の右側が左側より暗く塗られている（平均輝度 0.12 対 0.20）。`even_sides` が中心線で鏡写しにした反対側との明るさの比をボーン近傍で平滑化したゲインにし、UV上の三角形に補間してテクスチャのコピーに掛ける（明るくするだけ、3回繰り返し、最大2.5倍）。続けて局所的な明暗の幅も反対側に合わせて広げる（最大1.8倍）。出力GLBのテクスチャ（`…_even`）だけが変わり、原本は変更しない。
- クリップ（ボーン構成とポーズは `CLIPS['wolf']`）: `idle`（呼吸・尾の揺れ・あえぎ）、`walk`（トロット: 左前と右後、右前と左後が対で振れる）、攻撃2種 `attack`（後脚に体重を乗せて右前脚を頭上へ大きく振り上げ、前方の地面へ振り下ろす）と `attack_bite`（溜めて口を開き、`BITE_REACH`（0.45＝ゲーム内約1.6m）前へ飛びかかって噛みつき、首を振ってから後ろへジャンプして元の位置へ戻る。0.77秒の速い1撃で、移動はクリップ内で完結）、`guard`（低く後ずさり、牙をむいて尾を巻く）、`hit`（前半身がのけぞり頭が跳ね上がる）、`death`（4.1秒。頭を空へ振り上げて口が緩み、後脚から力が抜け、前脚が胸の下に折れて伏せ、後脚も畳んで腹ばいに沈み込み、ゆっくり頭を前へ垂らして前足の上に落とす。横には転がらない）。
- Godot: `scenes/characters/enemies/wolf.tscn`（Modelは3.6倍、`weapon_id`／`shield_id` は `none`）。`enemy_character.gd` の `attack_clips()` が使える攻撃（`attack` と、モデルにあれば `EXTRA_ATTACKS` の `attack_bite`）を返し、デモの攻撃は順番に切り替わる（ゴブリンは `attack` のみ）。

### グリム（grimm）

`--id grimm` で同じスクリプトから作る。赤い角と白いたてがみの四足の魔物で、武器・盾は持たず本体GLBだけを出力する。原本は長い前脚だけで地面に立ち、後脚は腰の下で宙に丸まっている（左後脚は前へ折り込み、右後脚は後ろへ流す）。尾は腰から上へ弧を描いて後ろへ垂れる。

- 浮遊物の削除: たてがみの中に浮いていた3mmの小片（147頂点）。
- 接地: 地面に付くのは前足だけで、しかも右寄り（x -0.36〜0.24）なので、`keep_x` で左右の中心合わせをせず体の中心線（x=0）を保つ。
- Skeleton（Root + 27ボーン）: `Hips → Spine → Chest → Neck → Head → Jaw`、角は `Head → {Left,Right}Antler → …Antler1`（付け根から外への枝と、上へ伸びる先端。キーは打たず頭と一緒に固く動く）、`Hips → Tail → Tail1 → Tail2`、前脚 `{Left,Right}Shoulder → Arm → ForeArm → Hand` を `Chest` から、後脚 `{Left,Right}UpLeg → Leg → Foot` を `Hips` から（宙に丸まった形のまま）。
- クリップ（`CLIPS['grimm']`）: `idle`（荒い呼吸、頭の揺れ、丸まった後脚のひくつき）、`walk`（前脚で交互に踏み出し、後脚は宙で逆位相に掻く）、攻撃2種 `attack`（頭をのけぞらせ片前脚を上げて立ち上がり、頭を下げて角を前へ突き出し、そのまま上へかち上げる）と `attack_bite`（顎を開いて低く溜め、`GRIMM_BITE_REACH`（0.3＝ゲーム内約1.7m）前へ首を伸ばして飛び込み、牙を閉じて首をひねってから元の位置へ戻る）、`guard`（頭を下げて角を相手へ向け、前脚を開いて踏ん張り後ずさる）、`hit`（前半身がのけぞり頭と角が横へ跳ねる）、`death`（4.1秒。天を仰いで吠え、前脚が胸の下に深く折れて腹ばいに沈み込み、頭と角を前へ垂らして地に付ける。丸まった後脚は腰の下から後ろへ流し、尾も後ろへ伸ばして体を支えないようにする。横には転がらない）。
- Godot: `scenes/characters/enemies/grimm.tscn`（Modelは5.6倍＝肩の高さ約4m、角の先まで約5.2m、`max_hp` 5、`weapon_id`／`shield_id` は `none`）。`attack_clips()` は `attack` と `attack_bite` を返す。`verify_enemy.gd` は角が頭に固定されて動くこと、突きと噛みつきの動き、死亡後に元の位置で前へ崩れ込むことを確認する。

### スケルトン（skeleton）

`--id skeleton` で同じスクリプトから作る。フードとぼろ布の腰巻をまとった4本腕の骸骨戦士で、上の腕に曲刀（右、頭の後ろへ振りかぶる）とトゲ付きメイス（左）、下の腕に鎌（右、刃が前向き）と円盾（左）を持つ。原本は1つの塊で浮遊物は無い。脚は大きく外へ開き、つま先が左右に広がるので `keep_x` で中心線（x=0）を保つ。

- 装備: 4つの武器は差し替えずに本体の一部として残し、ソケットも出力しない（`weapon_id`／`shield_id` は `none`）。代わりに `rigid` が武器の範囲（曲刀・鎌・メイスの柄は折れ線のカプセル、メイスの頭は球、盾は球を x>0.235 の面で切った範囲）の頂点を握る手のボーンへ100%で割り当て、武器が曲がらず手と一緒に固く動く。
- 頭: `head_region` が頭蓋とフード（頭のx±0.1、z 0.71〜0.77で徐々に、それより上は完全に `Head`）を割り当てる。`head_full` と違い範囲外の高い位置（振り上げた手や武器）は `Head` にしない。
- Skeleton（Root + 27ボーン）: `Hips → Spine → Chest → Neck → Head`、上の腕 `{Left,Right}Shoulder → Arm → ForeArm → Hand` と下の腕 `{Left,Right}LowerShoulder → LowerArm → LowerForeArm → LowerHand` を `Chest` から、脚 `{Left,Right}UpLeg → Leg → Foot` を `Hips` から。
- クリップ（`CLIPS['skeleton']`）: `idle`（開いた脚の上で揺れ、4本の武器が少しずつずれて揺れる、頭蓋が傾く）、`walk`（がに股でカタカタ歩く。上の腕は脚と逆、下の腕はさらに逆に振れる）、攻撃2種 `attack`（体を右へひねって曲刀とメイスを振りかぶり、踏み込んで2本同時に叩きつけ、続けて鎌を横から引っかける）と `attack_flurry`（4本の腕を大きく広げて沈み、小さく跳びながらその場で1回転して4つの刃で周囲を薙ぎ、正面を向いて着地。回転は `Root` のZ回転、しゃがみは pose の `hips` キーで腰だけを下げる）、`guard`（円盾を前へ掲げ、曲刀とメイスを胸の前で構えて腰を落とす）、`hit`（のけぞって4本の腕が跳ねる）、`death`（4.1秒。頭蓋を天へ向けて腕を振り上げ、武器が垂れ、がに股の脚が外へ折れて崩れ落ち、肋骨が前へ折れ頭蓋が垂れた骨の山になる）。
- Godot: `scenes/characters/enemies/skeleton.tscn`（Modelは4.6倍＝フードの先まで約4m、武器を広げた幅約3.4m、`footprint` 2（4m四方）、`max_hp` 4）。`enemy_character.gd` の `EXTRA_ATTACKS` に `attack_flurry` を追加し、`attack_clips()` は `attack` と `attack_flurry` を返す。SRPG戦闘のステータスは `srpg_battle.gd` の `ENEMY_STATS.skeleton`。`verify_enemy.gd` は叩きつけで上の両手が下がること、回転して正面に戻ること、死亡後に元の位置で崩れることを確認する。

## ガーディアン（guardian）

ガーディアンはキャラクターが1体ずつ装備できるスタンドのような存在。将来は装備したガーディアンからステータスやスキルを得るが、現状はビジュアル（出現・返還）のみ。`assets/characters/tripo/guardian/<id>/model.glb` は原本で上書きしない。`tools/asset_gen/character_pipeline/build_guardian.py` が `build_enemy.py` のヘルパー（Armature生成・ポーズ合成・プレビュー）を使ってリグとクリップを付け、`assets/characters/guardian/<id>/model.glb` へ出力する。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_guardian.py -- --id shadow1 --preview artifacts/guardian_preview   # 影２は --id shadow2
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script scripts/world_jrpg/verify_guardian.gd
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --path . --script res://tools/asset_gen/character_pipeline/capture_guardian.gd   # -- res://artifacts/guardian_shadow2 shadow2 で影２
```

### 影（シャドウ）（shadow1）

宙に浮く影の怪物。大きく裂けた牙の口、鉤爪の両腕、頭の触手、下半身は尾のような煙状。原本は1つの塊（19,829頂点）で高さ0.96、尾の先が原点。右手は前（y −0.18）、左手は後ろ（y +0.08）に構えた非対称の姿勢をそのまま使う。

- Skeleton（Root + 18ボーン）: `Hips → Spine → Chest → Head → Jaw`、`Hips → Tail → Tail1 → Tail2`、腕 `{Left,Right}Shoulder → Arm → ForeArm → Hand → Fingers`（Fingersは鉤爪全体）を `Chest` から。
- スキニング: ボーン距離に加え、口の隙間（下の歯 z 0.54〜0.62、上の歯 0.68〜0.74）より下・ヒンジ（y −0.1）より前を `Jaw`、隙間より上の上顎と頭蓋を `Head` に固定し、平滑化でも上下の歯が混ざらないようにしている。
- クリップ（`CLIPS['shadow1']`、全て浮遊・接地補正なし）: `idle`（ループ。上下に漂い、尾が波打ち、爪と顎がゆっくり動く）、`roar`（身を丸めてから頭を反らし、口を大きく開いて両腕を広げる。出現時に再生）、`attack`（右の鉤爪を肩の上へ引いて前へ振り下ろす）、`attack_bite`（引いてから突進して噛みつく）。単発クリップはidleの初期姿勢で終わる。
- Godot: `scenes/characters/guardians/shadow.tscn`（`scripts/character/guardian_character.gd`、Modelは6.3倍＝約6m、探索者の約3倍）。描画は `guardian_shadow.gdshader`（Tripoの描き込みを無陰影で表示＋淡い深紅のリム）。インスタンスごとの `reveal`（0=消滅、1=完全）で、縦方向の筆の筋に沿って尾から頭へ墨として現れ、縁は深紅に焼けた線と墨の帯がゆらぐ。返還は頭から尾へ消える。
- 筆の演出: `guardian_ink_fx.gd` が円弧リボン（半径は `height` に比例、`guardian_ink_stroke.gdshader`、かすれのある墨の筆致＋深紅の縁）を動かす。出現時は16本が外側から螺旋を描いて体へ集まり、返還時は体から剥がれて外・上へ散る。出現中の常時エフェクトは無し。
- 追従: `follow_target`（探索者）の向き基準で `follow_offset`（既定 前 −2.0・上 0.3・左 0.8 m＝すぐ後ろの少し左）に浮かび、少し遅れて追い、同じ向きを向く。12m以上離れると瞬間移動。
- API: `summon()` / `dismiss()` / `toggle()` / `is_summoned()`、`act("attack" | "attack_bite" | "roar")`（出現中のみ）、シグナル `summoned` / `dismissed`。途中で逆操作すると現在の `reveal` から引き返す。
- UI: `world.gd` の装備パネルの左に「ガーディアン」パネル（装備中の名前、`影` / `影２` の選択ボタン、`出現` / `返還` ボタン。右列は1080pで埋まっているため2列目）。キーボードは `T` で出現／返還を切替。候補は `GUARDIANS`（id・ボタン名・シーン）で、各ガーディアンは最初の出現時に生成して `guardian_nodes` に保持する。出現中に別のガーディアンを選ぶと、今のものを返還して選んだものを出現させる。
- `verify_guardian.gd` は両ガーディアンのボーン・クリップ・roarで顎が開くこと、ボタンで徐々に出現／返還すること、左後ろに浮いて同じ向きを向くこと、出現途中で返還できること、影２への切替と出現中の入れ替えを確認する。`capture_guardian.gd` はJRPGWorldSample2でUIと出現・攻撃・返還のコマ（演出のコマはHUDを隠す）を `artifacts/guardian/` に撮る。

### 影２（シャドウ２）（shadow2）

墨の悪魔のような大柄な姿。前へ突き出た嘴状の頭（鼻先 y −0.24・z 0.67、小さな口）、両腕は前へ垂らした鉤爪（右手の方が前）、背中から触手がなびき、下半身は尾の煙。原本は1つの塊（23,748頂点）で高さ0.97、尾の先が原点。

- 浮遊物の削除: 右肩の後ろ（背中側）に本体から約8cm離れて浮いていた線（256頂点、`remove_inside`）。
- 先端の払い（`taper_tips`、`GUARDIANS['shadow2']['taper']`）: 体の各所から伸びる影の流れの先端を、筆の払いのような鋭い尖りに整える。UVの継ぎ目で分かれた頂点を同一視して表面の測地距離を体の中心（ボーンに最も近い頂点）から測り、その山を先端とする。山から下へ掃いて、より高い枝と合流するまでに `min_branch`（0.02）以上突き出た枝だけを触手として扱う（表面の凹凸は無視）。先端から `length`（0.09、短い枝は長さの8割）の範囲で、同じ深さの頂点の重心（断面の中心）へ寄せて先端で一点に絞り、先へ少し伸ばす。断面の半径が `thin`（0.035）を超える所（体に開く所）で止める。嘴と歯（`exclude`）と小片（`min_island` 未満）は対象外。75本の先端を処理する。先端が本体に接してループになっている鉤は先端が無いので変わらない。
- Skeleton: 影と同じボーン名・階層（Root + 18ボーン）を `SHADOW2_BONES` で体形に合わせて配置。クリップも影と共通（`CLIPS['shadow2'] = CLIPS['shadow1']`）。
- スキニング: 顎はヒンジ y −0.17 より前、z 0.635〜0.70 の嘴の下縁（x ±0.07）。頭は z 0.69〜0.74 で `Head` へ移行（x ±0.19、z 0.78以上は全て）。背中の触手（y > 0.06）は腕に乗らず（`arm_max_y`）、腰より上は y 0.08〜0.16 で `Chest` に移行する（`back`）。
- Godot: `scenes/characters/guardians/shadow2.tscn`（Modelは6.2倍＝約6m）。描画・筆の演出・追従は影と同じ `guardian_character.gd`。

## 一体型キャラクター（standalone）

`assets/characters/tripo/characters/<id>/model.glb` は Body/Face に分かれていない1体分の静的メッシュ（Tポーズ）原本で、上書きしない。`tools/asset_gen/character_pipeline/build_rigged_character.py` がモデルに合わせた専用Skeletonを作り、`assets/characters/standalone/<id>/model.glb` へ出力する。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_rigged_character.py -- --id test --preview artifacts/rigged_character_preview
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --path . --script res://tools/asset_gen/character_pipeline/capture_rigged_character.gd
```

- Skeleton: 骨の配置はモデルごと（`TEST_BONES`）だが、出力時の骨名は humanoid_v1 と同じ（`mixamorig_Hips`〜`mixamorig_Spine2`、`head`、腕・脚・`HandMiddle1`・`ToeBase`、`EXPORT_NAMES`）。これにより `SwordCombat`・`SwordGait`・`GaitCycle`・`GroundSit` がそのまま使える。マント（`Cape1〜3`、Spine1から）と前垂れ（`Tabard1〜2`、Hipsから）は独立した鎖で、脚に引っ張られない。前腕は肘側1/3だけを `ForeArm` に、残りを子の `ForeArmTwist1`・`ForeArmTwist2` にスキンする（`SKIN_SEGMENTS`）。`SwordCombat` のクリップは握りの向きを手の骨のねじれだけで作る（横薙ぎで約150°）ため、大きな籠手が手首で棒状に潰れていた。実行時に `scripts/character/forearm_twist.gd`（SkeletonModifier3D、装備の後に追加）が手のねじれの1/3・2/3を2本のツイスト骨に配り、ねじれを前腕全体に分散させる。原本のTポーズは左右非対称で、右腕は左腕より約3.5cm前にある（手首 y 0.005 対 0.049）。以前は左腕の値を鏡写しにしていたため、右手の骨が手の中心から約4cm後ろに外れていた。現在は各腕が自分の中心線に沿う。手は指（`Fingers1/2`→`HandMiddle1/2`）・親指（`Thumb1/2`→`HandThumb1/2`）・短い小指（`Pinky`→`HandPinky1`）に分け、骨同士が手の幅より近いため距離ではなく領域でウェイトを付ける（`HANDS`。親指の境界は指先へ向かって前へ傾け、人差し指を親指に含めない）。原本は指を伸ばした平手で、剣を持たせると平手が柄に乗って手首が折れたように見えたため、`bake_fists` が `FIST` の角度で指を曲げた拳をバインドポーズとして焼き込む（メッシュは拳の形になり、骨のrestも追従）。`SwordCombat` は拳メッシュの中心に柄を通すので、剣は握った拳の中に収まる。武器なしの手も拳になる。片手剣の共通クリップは剣の向きだけで手を回すため、手の骨と拳が一致するこのモデルでは手首が76〜150°折れて見えた（Tripoの Body キャラも数値上は同程度に曲がっているが、手のメッシュと骨の軸が揃っていないので目立たない）。対策は2つ。(1) シーンの `metadata/sword_grip_blade`（バインドポーズで剣が拳から出る向き、スケルトン空間）を `SwordCombat` が読み、`SWORD_REST_BLADE` の代わりにその握りを使う（test は親指側＝前方から指先側へ約30°傾けた `Vector3(-0.62, 0, 1)`。柄が拳を斜めに通る実際の握り方）。(2) `forearm_twist.gd` が毎フレーム、剣の向きは変えずに剣の軸まわりのロールだけを選び直して手を前腕の線に最も近づけ、それでも `MAX_BEND`（40°）を超えるとき（剣が腕とほぼ一直線になる振りかぶり等）だけ剣の向きを譲る。(3) 構え・歩き・走り（`sword_gait` 系 `GAIT_CLIPS`）では、手首を前腕にまっすぐ乗せて剣側へ `GAIT_COCK`（10°）起こした一定の角度に保ち、剣は腕の振りと一緒に動く（共通クリップの構えは剣先が低く、歩き・走りでは手が外へ開いていた）。前腕まわりのロールは、剣が構えの剣の向き（胸の骨の座標系）に最も近づくように選ぶ。走りの前後の振りで剣先が `GAIT_PITCH`（下15°〜上45°）を外れるときだけ、手首を `GAIT_COCK_RANGE` の範囲で起こす・寝かせる（後ろ振りで地面に刺さらない）。攻撃クリップとは0.15秒で切り替える。歩き・走りでは剣の向きを `GAIT_MOVE_YAW`（外へ25°）開く（構えは胸を盾側へ大きくひねっているため、その剣の向きのままだと腰の前を横切る）。さらに歩きの剣腕はシーンのメタ `sword_walk_swing`（振り幅の倍率、test は0.35）と `sword_walk_wrist`（手首位置の追加オフセット、腕の長さ比・胸の座標系、test は外へ0.08・前へ0.08）で `SwordGait.install_armed` の `WALK_SWORD` を調整し、刃と右太ももの骨の最短距離を0.13mから0.22mに広げた。(4) 上段斬り（`LOOSE_CLIPS`）の振り下ろし後は、共通キーの剣先が前腕の線より35°以上下がり、手が反って見えた。腕より下を向く剣は線から `LOOSE_LIFT`（0°、つまり前腕の線まで）持ち上げ、剣を拳の中で最大 `LOOSE_PIVOT`（45°）回して（`SwordGrip` ノードを回転、握りが緩む表現）手首の曲がりを `LOOSE_BEND`（10°、届かないときは回転の上限まで。振り下ろし後は約20°）に抑える。振り下ろし後の剣先は約-25°（前腕と同じ向き）。metaのないキャラクターの挙動は変わらない。確認は `capture_rigged_hands.gd`（右手首の拡大を構え・歩行・横薙ぎ・上段・防御・奥義で撮影）。
- クリップ: `idle`・`walk`・`run`（ループ、その場、マントがなびく）。探索者として操作する間は他キャラと同じ手続き的クリップが優先される: 武器を持つ間は `SwordCombat` の構え・歩行・攻撃（`sword_gait/*`、`sword/slash`・`overhead`・`guard`・`skill`）、納刀・武器なしでは `GaitCycle` の `gait/walk`・`gait/run`。手続き的クリップはマントと前垂れの骨を動かさない。
- Godot: `scenes/characters/standalone/test.tscn`（`scripts/character/rigged_character.gd`、Modelは1.85倍＝身長約1.8m）。装備は `SwordCombat.LOADOUTS["standalone_test"]`（片手剣＋盾）。描画は他の Tripo キャラと同じ無陰影表示で、`rigged_character.gd` が `_ready` で全メッシュに `character_toon.gdshader`（`shade_strength = 0`）を当てる。テクスチャの描き込み陰影をそのまま見せ、ライティング・影の影響を受けない（インポート材質は変更せず、インスタンスの上書きのみ）。ただし夜の暗さだけは受ける: `night_amount = 1` で、`field_weather.gd` が時間帯ごとに設定するグローバルシェーダ変数 `night_tint`（`project.godot` の `shader_globals`、夜は `NIGHT_TINT`、他の時間帯は白）を色に掛ける。装備は他キャラと同じく `SwordCombat._apply_character_toon` のトゥーン表示で、シーンのメタ `night_shade` により専用の材質（`night_amount = 1`）を使い、同じく夜に暗くなる（他キャラは `night_amount = 0` で夜も明るさが変わらない）（2026-11 まではシーンのメタ `weapon_lit` でライティングを受けていたが、test〜test4 から外した。`weapon_lit` の仕組み自体は `SwordCombat` に残る）。`JRPGWorldSample2` の初期操作キャラで、ロスターの末尾にもいる。
- test2（`--id test2`）: マントの騎士（前垂れなし）。骨名・クリップ・装備の扱いは test と共通で、骨の配置・手の領域・布の範囲だけをモデルに合わせる（`TEST2_BONES`・`TEST2_HANDS`・`TEST2_SKIN_SEGMENTS`、`CHARACTERS['test2']`）。test より腕が約2.5cm高く（手首 z 0.70）、体の中心線近く（y 左 -0.01・右 -0.02）を通る。指は短く（指の付け根 0.448、指先 0.483）、親指は掌の前縁に沿い先端だけが離れる。マントは腰まで背中に沿うので、鎖は腰から始め（`Cape1` の頭 z 0.50）、布の範囲も腰より下（`top` 0.50）に限る。前垂れの鎖は無い（`cloth['tabard']` が空なら作らない）。Godot: `scenes/characters/standalone/test2.tscn`（`character_id` `standalone_test2`、メタは test と同じ）、`SwordCombat.LOADOUTS["standalone_test2"]`（片手剣＋盾）。`JRPGWorldSample2` のロスター末尾。手の確認は `capture_rigged_hands.gd -- <out_dir> res://scenes/characters/standalone/test2.tscn`。
- test3（`--id test3`）: マント無しの騎士。前垂れ（ベルトから前へ垂れる布）と脚の後ろに長い後ろ垂れがある。後ろ垂れはマントの鎖（`Cape1〜3`、ここでは `Hips` から）に乗せ、前垂れは `Tabard1〜2`。上腕が短く（肘 0.232、手首 0.368）、Tポーズは左右で前後にずれている（左手 y +0.055＝後ろ、右手 y −0.082＝前）。4本の指が同じ付け根の線（0.416）から出るので小指は指と一緒に曲げる（小指領域なし、`pinky_y` 1）。膝は低い（0.205）。`TEST3_BONES`・`TEST3_HANDS`・`TEST3_SKIN_SEGMENTS`、`CHARACTERS['test3']`。Godot: `scenes/characters/standalone/test3.tscn`（`character_id` `standalone_test3`、メタは test と同じ）、`SwordCombat.LOADOUTS["standalone_test3"]`（片手剣＋盾）。`JRPGWorldSample2` のロスター末尾。
- test4（`--id test4`）: 上半身裸にたすき、段になったゆったりしたズボン（脛の上で絞る）、帯から垂れる破れた前垂れ（中心よりやや右、y −0.07〜−0.12、z 0.12まで）。マント無し: `Cape1〜3` は共通クリップのために残すが頂点を持たない（`back_y`・`side_x` を 1 にして、広がったズボンが鎖に乗らないようにする）。前垂れは `Tabard1〜2`（`front_y` −0.07、`tabard_x` 0.06）。Tポーズは左右対称で腕は中心線のやや後ろ（y +0.02）。肘 0.23（太い腕甲の始まり）、手首 0.37、指は開いていて付け根 0.44・指先 0.487、親指は掌の前、小指は後ろ。膝はズボンの中（約 0.25）。髪がz 0.775まで首の横に垂れるので `head_blend` 0.775・`head_reach` 0.095。`TEST4_BONES`・`TEST4_HANDS`・`TEST4_SKIN_SEGMENTS`、`CHARACTERS['test4']`（`clean` あり: 15,996 → 溶接 8,013 → 極小片7個削除で 7,924 頂点）。Godot: `scenes/characters/standalone/test4.tscn`（`character_id` `standalone_test4`、メタは test と同じ）、`SwordCombat.LOADOUTS["standalone_test4"]`（片手剣＋盾）。`JRPGWorldSample2` のロスター末尾。
- メッシュの掃除（`CHARACTERS[id]['clean']`、`clean_mesh`。test3・test4）: スキニング前に (1) Tripo がUVの継ぎ目ごとに分けている同位置の頂点を溶接し（距離 1e-5。UV・法線は面の角に残る）、(2) `min_extent`（4mm）未満の潰れた極小片を削除する。test3 は 18,749 頂点・1,550 片 → 溶接で 10,002 頂点・35 片、極小片19個（肘・顔まわり、552頂点）を削除して 9,450 頂点。継ぎ目が曲げで開かず、ウェイトも継ぎ目の両側で一致する。原本は変更しない。
- プレビュー（`--preview`）は export の骨名変更より後に走るため、`--no-export --preview` で別に撮ると正しく動く。
