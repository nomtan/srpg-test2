# Codex instruction: Tripo Character Golden Path

このタスクでは `docs/character/tripo-character-pipeline.md` を最初に読み、その仕様を優先すること。

## Goal

最初のGolden Pathとして次の素材を組み合わせ、Godotで利用可能な1体のcharacter GLBを作る。

```text
Body: assets/characters/tripo/body/001/model.glb
Face: assets/characters/tripo/face/001/model.glb
Output: assets/characters/generated/golden_path_001/character.glb
```

成功後、Faceだけ `002` へ交換した2体目も作り、同じBody/Skeleton/animationを再利用できることを確認する。

```text
Body: assets/characters/tripo/body/001/model.glb
Face: assets/characters/tripo/face/002/model.glb
Output: assets/characters/generated/golden_path_002/character.glb
```

## Non-negotiable rules

1. `assets/characters/tripo/face/**/model.glb` と `body/**/model.glb` は原本。絶対に上書きしない。
2. Blender操作は接続済みBlender MCPを使う。
3. Tripoのobject/bone/material名を事前に決めつけない。まずscene/object/material/armature構成を調査する。
4. 最終runtime characterにSkeletonを複数残さない。Body側を基準に1 Skeletonへ統合する。
5. Faceは最終的にBody Skeletonの `head` boneへ追従する。
6. Face側の独立AnimationPlayer/Armatureは最終出力から除去する。
7. Tripoのtexture/materialを不要に作り直さない。セルルック/アニメ調の見た目を維持する。
8. 目・眉・口を前髪より手前の板ポリで常時描画する構造にはしない。
9. raw sourceを修正する必要がある場合も、Blender scene内のコピーだけを編集する。
10. 不明なmeshやboneを推測で削除しない。役割を確認してから処理する。

## Step A: preflight

リポジトリルートで実行する。

```bash
python tools/asset_gen/character_pipeline/scan_sources.py
```

エラーがある場合はBlender処理へ進まず原因を報告する。

## Step B: inspect Body 001

Blender sceneをcleanにしてBody GLBをimportする。

確認して記録すること:

- root object名
- Mesh一覧
- Armature有無
- bone一覧
- material一覧
- texture参照
- bounding box / character height
- root transform
- 不要なhead/face geometryがBody側に含まれているか

この調査結果を作業ログへ残す。

## Step C: normalize Body

- Blender Unit Scale 1.0
- meter基準
- 足元中央をcharacter原点とする
- export rootに不自然なscale/rotationを残さない
- camera/light等の不要objectを削除
- Body側に不要な頭部がある場合はworking sceneでのみ除去
- rigを `humanoid_v1` として再利用可能な構成へ整理

最低限 `head` boneを固定名として確保する。

既存boneを大幅変更する必要がある場合、先に現在のbone構成を提示してから最小変更で対応する。

## Step D: inspect/import Face 001

Face GLBをimportし、次を確認する。

- Head相当mesh
- Hair相当mesh
- 前髪geometry
- Armature/Skin有無
- materials/textures
- sourceに目/眉/口/髭の造形が残っていないか

HeadとHairが1 Meshの場合でも、無理に破壊的分離しない。material slotやvertex island等から安全に分離できる場合だけ分ける。

推奨最終名:

```text
Head
Hair
```

## Step E: fit Face to Body

FaceをBodyの首へ合わせる。

優先順位:

1. 首の継ぎ目が目立たない
2. 元の頭身/シルエットを維持
3. 前髪とHeadの位置関係を維持
4. Face全体のscale変更を最小化

Faceの補正値を記録する:

```text
position
rotation
scale
```

後でcharacter manifestの `fit` に転記できる値として扱う。

## Step F: bind to one Skeleton

最終形ではBodyのSkeletonを唯一のruntime Skeletonとする。

Faceがrigged meshの場合:

- Faceの必要bone weightsをBody Skeletonの対応boneへremap
- head周辺だけで十分な場合は必要最小限のbindにする
- source Face Armatureは除去

Faceがriggedでない場合:

- `head` boneへ安全に追従する構成にする
- HairもHeadと一緒に追従させる

顔/髪がBodyアニメーション中に遅れたり位置ずれしないことを確認する。

## Step G: animation Golden Path

まず以下の4 clipを共通Skeleton上で使用できる状態にする。

```text
idle
walk
attack
hit
```

既存アニメーションが素材にない場合、今回のタスクで無理に高品質animationを完成させる必要はない。まずrig互換性を優先し、簡易clipまたは既存利用可能clipでパイプラインを検証する。

アニメーション中に確認すること:

- 首が外れない
- Head/HairがBodyに追従する
- mesh deformationが破綻しない
- root motionが意図せず入らない

## Step H: export

Godot用GLBとして書き出す。

```text
assets/characters/generated/golden_path_001/character.glb
```

概念上の最終構造:

```text
Character
├─ Skeleton / Armature
├─ Body
├─ Head
├─ Hair
└─ animations
```

Godot側で `AnimationPlayer` がimportされ、既存 `BattleUnit.setup_visual()` からinstantiate可能であることを確認する。

## Step I: Face 002 compatibility test

Body 001とSkeleton/animationを維持したまま、Faceだけ002へ交換する。

出力:

```text
assets/characters/generated/golden_path_002/character.glb
```

001と002でBody側のrigやanimationを作り直す必要がある場合は、その理由を特定する。個別対応で済ませず、共通化できる規格へ修正する。

## Step J: report

完了時は次を報告する。

1. Body 001の元のmesh/armature/bone構成
2. Face 001/002の元のmesh/armature構成
3. 採用した最終Skeleton/bone名
4. Face fit補正値
5. material/textureで変更した内容
6. animation clip一覧
7. 出力したGLBパス
8. Godotでのimport/instantiate結果
9. 未解決事項
10. `docs/character/tripo-character-pipeline.md` に固定すべき追加規格

## Face expressionについて

今回のGolden Pathでは高度な表情リグを作らない。

後続実装でHead materialへ以下を重ねられる構造を確保する。

```text
Eyes + Eyebrows: male/female 各3 style
Expression: normal / closed(blink) / surprised / squint
Mouth: default
Beard: optional texture
```

瞬きはBody animationから分離し、Godot側Face Controllerで行う方針とする。
