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
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_enemy.py -- --id goblin --preview artifacts/enemy_preview   # ウルフは --id wolf、グリムは --id grimm
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script scripts/world_jrpg/verify_enemy.gd
```

- 浮遊物の削除: 1.5cm以内の頂点をつないだ塊のうち、`remove_inside` の箱に収まるものを消す。ゴブリンは背後に浮いていた布片（537頂点）と小片（68頂点）。
- 装備の分離: 握っていた曲刀（柄から刃先への軸からの距離で判定）と円盾（独立した塊）を本体から切り出し、`assets/characters/enemy/equipment/{weapon,shield}/<id>/model.glb` に出力する。武器GLBは握りの座標系（原点=拳の中、+Y=刃先方向、+X=刃の幅方向）、盾GLBは盾の座標系（原点=裏面中央、+Z=表面、+Y=上）で置く。本体GLBはArmatureのextras `weapon_socket`／`shield_socket`（bone・origin・basis、glTF軸、rest空間）にその座標系の位置を記録する。
- 装備ライブラリ: `EQUIPMENT` がプロジェクトの武器原本（`assets/weapons/...`、読み取りのみ）を同じ座標系へ置き直して出力する。現在は武器 `scimitar`（ゴブリン原本）・`hand_axe`（両手斧002を0.52倍）・`longsword`（片手剣001.glbを0.72倍）・`staff`（杖001を0.82倍）、盾 `round`（原本）・`kite`（盾001を0.55倍）。
- スキン: Tripoメッシュは数百の島に分かれているため、ボーン線分までの距離でウェイトを付け、半径2cmで平滑化して隣の島と一緒に動かす。
- クリップ: `idle`・`walk`（ループ）、`attack`・`guard`・`hit`・`death`（最終フレームで停止）。その場モーションで、移動はゲーム側が行う。`death`（4.1秒）は大きく上を見上げ、力が抜けて腕が垂れ膝が折れ、膝をついてからスローモーションのようにゆっくりかかとの上へ座り込み、上体を前へ丸めて頭と腕を垂らす（横や後ろへは倒れない）。キーは通常の速さ（膝つき38→座り込む60フレーム）で書き、`DEATH_PACE`（1.5）倍に引き延ばす。膝をついた時点からは最下点が地面に来るようRootを上下させ、宙に浮かずに地面に沿って崩れる。
- Godot: `scenes/characters/enemies/goblin.tscn`（`scripts/character/enemy_character.gd`、Modelは2.025倍）と、継承シーン `goblin_axe`（片手斧+円盾）・`goblin_longsword`（ロングソード+カイトシールド）・`goblin_staff`（片手杖、盾なし）。`weapon_id`／`shield_id` をインスペクタで選ぶか、実行中に `set_weapon(id)`／`set_shield(id)` で差し替える（`none` で外す）。装備は `RightHand`／`LeftHand` の `BoneAttachment3D` 下に `get_bone_global_rest().affine_inverse() * socket` で付く。
- 描画と消滅: 本体・装備とも `enemy_dissolve.gdshader`（Tripoの描き込み陰影を保つ無陰影表示）。インスタンスごとの `dissolve` で、倒れた後にノイズ状に燃える縁を残しながら崩れ、骨に沿って灰と火の粉が舞い上がる（CPUParticles3D）。2秒後に最初の位置へ戻り、逆向きのdissolveで現れる。
- `JRPGWorldSample2` は `field_enemies` の6体（ゴブリン4体＋ウルフ＋グリム）を出現位置の7.5m前に3.2m間隔で並べる。種類（`enemy_id`）ごとに先頭の1体が全モーション（最後に塵化と再出現）を順に再生するデモ（`enemy_demo`）。攻撃が当たると `hit`／ときどき `guard`、`max_hp` 発目（既定3、グリムは5）で倒れて塵になる。

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
