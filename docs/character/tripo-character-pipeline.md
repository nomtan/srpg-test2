# Tripo キャラクターパイプライン — Phase 3

> Phase 5の新規Face描画契約と現在の未完了事項は [Face Expression Rendering v2](face-expression-rendering-v2.md) を参照。旧Face001〜006の描画とAPIは維持する。

> 現行Faceのサイズは[顎幅基準](face-size-jaw.md)（Face004のみ例外）。旧[Face007基準のサイズ](face-size007.md)は廃止。下記のPhase3測定・default profile説明は当時の記録。

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

Bodyは唯一のSkeleton、`idle` / `walk` / `attack` / `hit` の4クリップを持つ。Faceは静的メッシュで、Skeleton、skin、animationを含めない。Faceの頂点は共通Skeletonのrest空間に置く。Godotでは `head` ボーンの `BoneAttachment3D` に `FaceSocket` を置き、その下にFace全体を装着する。`get_bone_global_rest(head_index).affine_inverse()` を一度だけ適用する。Body/Faceの組み合わせ別のランタイム補正はない。

Blenderはメートル・Z-up、GodotはY-up。出力root、Armature、mesh objectのtransformはidentityとし、正規化は頂点へ焼き込む。

## 部品出力と検証

Blender 5.1で原本と同じIDを指定し、部品ごとに別プロセスで作業領域へ出力する。

```powershell
python tools/asset_gen/character_pipeline/scan_sources.py
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind body --id 005 --output-root artifacts/modular_direct
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind face --id 005 --output-root artifacts/modular_direct
python tools/asset_gen/character_pipeline/validate_modular_parts.py --root artifacts/modular_direct
```

`normalization.json` の任意項目 `source_file` で同じTripoフォルダ内の別原本を指定できる（`source_sha256` はそのファイルのハッシュ）。`baked_face_features: true` はテクスチャに目・眉・口が描き込まれたFaceを示し、GLB node extrasに出力され、`CharacterAssembler` が表情オーバーレイを非表示にする。このFaceはテクスチャに陰影も描き込まれているため、Tripoでの見え方に合わせてトゥーンの陰影帯と受ける影を付けず、テクスチャ色をそのまま表示する（shader `shade_strength = 0`）。Face002は `face+facial.glb` を原本とする。

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
