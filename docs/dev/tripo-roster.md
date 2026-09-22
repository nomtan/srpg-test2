# Tripoキャラクター9体

`samples/JRPGWorldSample.tscn` の開始地点付近に、指定の9体を3列で配置しています。名前表示、NPCの衝突、会話に対応しています。操作キャラクターも、今回指定された `tripo_knight2/knigth.glb` を加工した騎士です。

パッドの **X（PS系では□）／Vキー** で操作キャラクターを順番に変更できます。順序は下の表と同じで、白魔導士の次は冒険者へ戻ります。初期状態は騎士なので最初の切り替え先は学者です。探索・会話・戦闘中に切り替えでき、位置・向き・移動状態を保ちます。選択中の名前はHUDに表示します。

入力パスの `tripo\_adventure` などは、実際の `tripo_adventure` フォルダーに対応させています。入力GLBは上書きしません。

| キャラクター | 入力ファイル | Blender編集ファイル |
|---|---|---|
| 冒険者 | `assets/characters/tripo_adventure/adventure.glb` | `assets/characters/tripo_adventure/prepared/character.blend` |
| 黒魔導士 | `assets/characters/tripo_black_mage/black_mage.glb` | `assets/characters/tripo_black_mage/prepared/character.blend` |
| 執事 | `assets/characters/tripo_butler/butler.glb` | `assets/characters/tripo_butler/prepared/character.blend` |
| 執事長 | `assets/characters/tripo_chief_butler/chief_butler.glb` | `assets/characters/tripo_chief_butler/prepared/character.blend` |
| 勇者 | `assets/characters/tripo_hiro/hero.glb` | `assets/characters/tripo_hiro/prepared/character.blend` |
| 騎士 | `assets/characters/tripo_knight2/knigth.glb` | `assets/characters/tripo_knight2/prepared/character.blend` |
| 学者 | `assets/characters/tripo_scholar/scholar.glb` | `assets/characters/tripo_scholar/prepared/character.blend` |
| 戦士 | `assets/characters/tripo_warrior/warrior.glb` | `assets/characters/tripo_warrior/prepared/character.blend` |
| 白魔導士 | `assets/characters/tripo_white_mage/white_mage.glb` | `assets/characters/tripo_white_mage/prepared/character.blend` |

各 `prepared` フォルダーにはゲーム用 `character.glb`、交換用の雛形 `face_default.glb`、顔の分割情報 `face_manifest.json`、検証結果 `validation.json` もあります。Godotのキャラクターシーンは `scenes/characters/tripo_roster/` にあります。

## Blenderでの比較とアニメーション

シーンを切り替えて比較できます。

- `Original`：入力の形状、UV、マテリアル、法線、埋め込み画像。騎士の既存リグもこのシーンで保持します。入力の姿勢です。
- `Toon`：ゲーム用の26ボーン、ウェイト、顔の分割、3段階のセルシェーダー、細い輪郭。こちらを表示した状態で保存しています。

`Character_Rig` のActionには `idle`（2秒）、`walk`（1秒）、`run`（20/30秒）があり、すべて30fpsのその場ループです。移動距離はゲーム側が制御します。歩行・走行の接地は2関節の脚の計算とrootの高さ補正で調整しています。攻撃、被弾、表情アニメーションは含みません。

分離した顔と頭部（髪・帽子・兜を含む）は `head` に100%固定し、拡縮キー、Subdivision、Remesh、Decimateは使いません。服と鎧の大きな面は保ち、関節付近でウェイトを混ぜています。執事のスカートは腰に追従する構成です。

Toonマテリアルは `Diffuse BSDF → Shader to RGB → Constant ColorRamp` の明暗を、元のBase Colorに中立色で乗算し、Emissionへ渡します。明暗は **0.68 / 0.84 / 1.0**。色補正、Normal Map、Bump、金属反射を追加しません。32度を境にしたカスタム法線を使い、UV境界では同じ位置の法線を揃えています。

Color Managementは **Standard / None / Exposure 0 / Gamma 1**。Eevee、白色のSun 1灯、弱い環境光です。AgXとの比較画像も `artifacts/tripo_roster/<キャラクターID>/` にあります。輪郭は元の形状から0.0018だけ広げた反転メッシュで、元と同じウェイトを使います。

GLBには互換用マテリアル（Metallic 0、Roughness 1、Specular IOR Level 0）を書き出します。[BlenderのglTFマテリアル仕様](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html)に合わせ、Eeveeのノード構成はGodotの `tripo_roster_import.gd` が専用シェーダーに置き換えます。Godot側も3段階の中立色の陰影と細い輪郭で表示します。

## 顔を交換する

モデルは `Body`、`Head_Shell`、`Face_Default` に分かれています。それぞれに対応する `*_Outline` があります。顔パッチは元の三角形を分離したもので、頂点座標・UV・各頂点の法線を維持しています。髪や帽子は頭部側に残し、騎士は正面のバイザーを交換範囲にしています。`face_mask.png` の青緑色が実際の交換範囲です。

**テクスチャで顔を変更する場合**：キャラクターシーンのルートにある `Face Texture` に、元と同じUV配置のテクスチャを設定します。服や髪のマテリアルは変わりません。実行時は `set_face_texture(texture)` を呼べます。目や口は元画像に描かれているため、独立した目・口の立体メッシュではありません。

**顔の形状を変更する場合**：

1. 対象の `character.blend` または `face_default.glb` を雛形にします。
2. `Face_Default` を編集し、顔と頭の境界、オブジェクト原点、UVを維持します。ウェイトは `head` に100%固定します。境界の頂点番号はBlenderの `boundary_vertex_ids`、元の頂点・面番号は `face_manifest.json` に記録しています。
3. `Face_Outline` も同じ形状に合わせて更新します。
4. リグ、顔、顔の輪郭をGLBへ書き出します。Base ColorはPrincipled BSDFへ接続した互換用マテリアルを使い、ボーン名とスキンを保持します。
5. 元の `face_default.glb` と同じGodotインポート設定を適用します。`skins/use_named_skins=true`、`import_script/path="res://scripts/character/tripo_roster_import.gd"` が必要です。
6. キャラクターの `Face Variant` にそのGLBを設定するか、`set_face_variant(packed_scene)` を呼びます。`reset_face()` で元の顔・マテリアル・スキンへ戻せます。

顔の輪郭や寸法は9体で異なります。別キャラクターへの無調整の互換性は想定せず、対象キャラクターの雛形から作成してください。小物用には、頭の骨に追従する `FaceSocket` も用意しています。

## 再生成と確認

プロジェクトルートから実行します。再生成は `prepared` の生成物を更新するので、手編集した派生モデルは別名で保存してください。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/prepare_tripo_roster.py -- --render
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/verify_tripo_roster_blender.py
& 'C:/Users/nomur/Desktop/godot/Godot_v4.6.1-stable_win64_console.exe' --headless --path . --editor --import
& 'C:/Users/nomur/Desktop/godot/Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script scripts/world_jrpg/verify_tripo_roster.gd
```

生成を限定する場合は `-- --only adventure hero --render` を指定できます。ゲーム画像の確認は最後のコマンドから `--headless` を外し、末尾に `-- --capture` を追加します。

検証では元GLB・埋め込み画像・書き出したBase ColorのSHA-256、分離前後の頂点座標と各面のUV、全頂点のウェイト、全クリップのループ・接地、保存し直したBlenderファイル、頭部変形時の距離保持を確認します。Godotでは9体の配置、骨とマテリアル、27本のアニメーション、顔テクスチャの独立性、顔GLB交換と復元を確認します。

この環境では既存の `godot_mcp` プラグインのクラス重複とOS証明書ストアへのアクセスに関するログが出ます。キャラクターの実行検証・画像出力とは別の既存の問題です。
