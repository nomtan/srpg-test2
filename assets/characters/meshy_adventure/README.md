# 冒険者：共通ボディと顔・髪の差し替え

`samples/JRPGWorldSample.tscn` を Godot で開いて **F6**。
開始地点の操作キャラの横（マップ座標 X=30.5 / Z=57.5）に、別の「冒険者」が立ちます。
既存の移動操作は従来の hero2 を操作します。冒険者は静止 NPC で、接触回避・E/A の会話に対応します。

## パーツ構成

- `adventurer_body.glb`：冒険者ジョブの共通ボディ。首から下の服・腕・手袋・脚・靴・マフラー・マントを含みます。
- `face_default.glb`：顔・耳・露出した首。`Smile` / `Blink` / `Angry` のブレンドシェイプ。
- `hair_tousled.glb`：元の髪型。
- `hair_swept.glb`：同じ生え際を保ち、上の毛束を横に流したバリエーション。
- `Adventure_modular.blend`：Blender MCP で作成した編集用ファイル。`Adventure_Modular` が分離後、`Adventure_Original` が元モデルです。
- `Adventure.blend`：入力ファイル。上書きしていません。`.blend.import` は直接の自動インポートを止め、ゲームには準備済み GLB を使います。

共通化は「**同じ冒険者ジョブ内で首から下を共通にする**」という構成です。
全ジョブで下半身を共有する構成ではありません。
`JobDatabase` の `adventurer`（表示名「冒険者」）にボディのパスを登録しています。
ジョブ数値は既存の基本値、能力補正なしです。専用スキル・装備ルールは追加していません。

## キャラごとの変更

再利用シーンは `res://scenes/characters/adventurer_npc.tscn`。
Inspector の `appearance` に `AdventurerAppearance` リソースを指定します。
`appearance_default.tres` と `appearance_swept.tres` が設定例です。

- `face_scene`：別の顔 GLB / PackedScene。
- `face_texture`：顔だけの差し替えテクスチャ。未指定なら、その顔モデルに入っているテクスチャを使います。
- `hair_scene`：独立した髪の GLB / PackedScene。
- `hair_tint`：髪だけの色調整。
- `expression`：`neutral` / `smile` / `blink` / `angry`。

実行時の切り替え例（NPC がシーンツリーに入ってから）：

```gdscript
var npc = $AdventurerNPC
npc.set_expression("smile")
npc.set_expression("blink", 0.5) # 0～1 の強さ
npc.set_hairstyle("swept")
npc.set_face(load("res://path/to/compatible_face.glb"))
npc.apply_appearance(load("res://assets/characters/meshy_adventure/appearance_swept.tres"))
```

同じ設定リソースを複数キャラに渡しても、実行時の設定・マテリアルはキャラごとに独立します。
ボディのメッシュリソースは共有したままです。未対応の表情・髪型 ID は `false` を返します。
新しい顔に現在の表情がなければ通常表情へ戻します。

差し替えモデルの規約：Godot で足元原点、+Y が上、+Z が正面、元モデル全高 2.2。
顔・髪もこの全身座標のまま配置し、原点を頭の中心へ変更しないでください。
この Meshy メッシュは顔・髪・服が溶接されていたため、元のポリゴン境界で分離しています。
帽子なし・坊主・生え際が大きく違う髪型には、隠れていた頭皮の追加と境界の調整が必要です。
現時点の髪型 2 種類は同じ境界を使います。歩行用の骨格・全身アニメーションはこの静止 NPC には追加していません。

## セル調の保持

元の 2048px Base Color・UV・全ポリゴンを引き継ぎます。元テクスチャは各 GLB 内でも SHA-256 が一致します。
`adventure_toon.gdshader` は色付きの照明で元の配色が変わりすぎないように、0.72 / 0.86 / 1.0 の中立な3段階の陰影を足します。
金属光沢・スペキュラー・法線マップはゲーム表示で使用しません。
顔の表情にはブレンドシェイプを使い、笑顔・怒りのみ細い口の線もシェーダーで補います。通常表情の元テクスチャは変更しません。
Blender の分離シーンは元の描き込みを確認する無照明マテリアル、GLB 単体はマットな PBR フォールバックです。
ゲームと同じ段階陰影には必ず NPC シーン（または `AdventurerCharacter`）を使ってください。

## 再作成・検証

`artifacts/meshy_adventure/Adventure_disk_original.blend` は入力ファイルのコピー、
`Adventure_live_original.blend` は作業開始時の未保存編集も含むコピーです。
ライブコピーを Blender で開き、Blender MCP から次のように実行できます。

```python
path = r"<project>/tools/prepare_meshy_adventure.py"
ns = {"__file__": path, "__name__": "adventure_prepare"}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), ns)
ns["setup"]()
ns["export"]()
```

生成済みシーンを開いている場合は `setup()` を繰り返さず、編集して `export()` だけを実行します。
Godot インポート設定は自動 LOD 無効・頂点圧縮無効を維持してください（パーツ境界のずれを防止）。

```text
godot --headless --path . --script scripts/world_jrpg/verify_meshy_adventure.gd
godot --path . --script scripts/world_jrpg/verify_meshy_adventure.gd -- --capture
godot --headless --path . --script scripts/world_jrpg/verify_meshy_hero2.gd
```

配置・別操作・足元・会話/接触回避・パーツ単独書き出し・表情・顔差し替え・髪変更・個体間の独立を検証します。
画像とログは `artifacts/meshy_adventure/` に保存します。
