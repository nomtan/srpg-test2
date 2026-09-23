# Tripo Character Pipeline v1

## 目的

Tripoで生成した `Face` と `Body` を素材として管理し、Codex + Blender MCPで最終調整した1体のキャラクターGLBをGodotで利用するための標準フローを定義する。

この仕様では、ゲーム中の3Dキャラクターは戦闘中の引き絵を主用途とする。会話シーンの細かな感情表現は別途2D立ち絵で行うため、3D側のフェイシャル表現は軽量なテクスチャ切り替えを前提とする。

## 1. Source of Truth

Tripoから出力したGLBは加工せず、原本として以下へ置く。

```text
assets/characters/tripo/
├─ face/
│  ├─ 001/model.glb
│  ├─ 002/model.glb
│  └─ ...
├─ body/
│  ├─ 001/model.glb
│  ├─ 002/model.glb
│  └─ ...
└─ characters/
   ├─ _template.json
   └─ <character_id>.json
```

`face/*/model.glb` と `body/*/model.glb` は **immutable source** とし、Blenderで直接上書きしない。

素材の存在確認:

```bash
python tools/asset_gen/character_pipeline/scan_sources.py
```

カタログを書き出す場合:

```bash
python tools/asset_gen/character_pipeline/scan_sources.py --write-catalog
```

## 2. Face source specification

Tripoで用意するFaceは次の範囲に限定する。

- 頭部
- 髪型（前髪を含む）

原則としてTripo側では以下を作り込まない。

- 目
- 眉
- 口の表情差分
- 髭

1つのGLBでよいが、Blender調整後は可能な限り次のように論理的に分離する。

```text
FaceRoot
├─ Head
└─ Hair
```

前髪が目を隠すキャラクターに対応するため、目・眉をカメラ側の板ポリゴンとして置く方式は標準にしない。顔表現はHead表面のマテリアル/テクスチャ側で扱い、通常のDepth判定でHairが自然に手前へ来る構造とする。

## 3. Face expression specification

3D戦闘モデルでは複雑な表情リグやBlendShapeを必須にしない。

初期仕様:

- eye style
  - male_01
  - male_02
  - male_03
  - female_01
  - female_02
  - female_03
- expression
  - normal
  - closed / blink
  - surprised
  - squint
- mouth
  - default 1種
- beard
  - none
  - テクスチャで表現できる口髭・無精髭・顎髭
  - シルエットを変える長い髭のみ、将来Mesh attachmentを許可

瞬きはBody Animationに焼き込まず、Godot側のFace Controllerで独立して切り替える。

## 4. Body source specification

Bodyはキャラクターの首から下の造形を担当する。

Tripo出力に不要な頭部や顔要素が残っている場合は、source GLBは変更せず、Blenderのworking scene内で除去する。

最終キャラクターではBody側を基準に標準リグへ統一する。

標準リグID:

```text
humanoid_v1
```

重要な方針:

- runtime characterは原則1 Skeleton
- FaceはBody側Skeletonの `head` boneへ追従させる
- Face用に独立したAnimationPlayer/Skeletonを残さない
- 武器や将来の髭などはBoneAttachment相当のSocketで扱える構成にする

## 5. Character manifest

キャラクターごとの組み合わせはJSONで管理する。

例:

```json
{
  "schema_version": 1,
  "character_id": "vain",
  "display_name": "Vain",
  "face_id": "001",
  "body_id": "001",
  "rig_profile": "humanoid_v1",
  "animation_profile": "onehand_sword",
  "face": {
    "eye_style": "male_01",
    "expression": "normal",
    "mouth_style": "default",
    "beard_style": "none"
  },
  "fit": {
    "face_position": [0.0, 0.0, 0.0],
    "face_rotation_degrees": [0.0, 0.0, 0.0],
    "face_scale": [1.0, 1.0, 1.0]
  },
  "output": {
    "glb": "assets/characters/generated/vain/character.glb"
  }
}
```

`fit` はFaceとBodyの組み合わせ固有の補正値として保持する。Tripo素材そのものをキャラクターごとに破壊的編集しない。

## 6. Blender MCP processing flow

Codex + Blender MCPはキャラクターmanifestを読み、次の順序で処理する。

### Step 1: clean scene

既存オブジェクトを消し、作業用Sceneを初期化する。

### Step 2: import Body source

```text
assets/characters/tripo/body/<body_id>/model.glb
```

を読み込む。

### Step 3: normalize Body

- Blender Unit Scale = 1.0
- meter基準
- 原点を足元中央へ合わせる
- root scaleを可能な限り `(1, 1, 1)` に適用
- 不要なcamera/lightを削除
- 不要な頭部があればworking sceneで削除
- GodotへのglTF exportを前提とした向きへ統一

### Step 4: standardize rig

Bodyを `humanoid_v1` に合わせる。

最低限必要なbone名は、実モデルを1体処理して確定し、その後この文書へ追記する。既存ゲームコードでは `head` bone名を利用しているため、少なくとも `head` は固定名とする。

### Step 5: import Face source

```text
assets/characters/tripo/face/<face_id>/model.glb
```

を読み込む。

- Head/Hairを識別する
- Face側に独立Skeletonがある場合は最終出力には残さない
- Bodyの `head` boneへ追従できるよう調整する
- manifestの `fit` を適用する
- 首の境界、髪のめり込み、頭身を確認する

### Step 6: material normalization

- Tripoのテクスチャを保持する
- 不要な自動Smooth/Material置換でセルルックを崩さない
- HeadとHairを識別可能なMesh/Material名に整理する
- Head側には後から目・眉・口・髭テクスチャを合成できるMaterial slotを確保する

推奨名:

```text
Body
Head
Hair
```

### Step 7: animation

最終的に共通アニメーションを `humanoid_v1` へ適用できるようにする。

初期Golden Pathで扱うclip:

```text
idle
walk
attack
hit
```

追加候補:

```text
cast
reaction
victory
ko
```

Animation profile例:

```text
common
onehand_sword
bow
staff
```

### Step 8: export

出力先:

```text
assets/characters/generated/<character_id>/character.glb
```

source GLBへ上書きしてはいけない。

## 7. Godot output contract

Godotへ渡すGLBは、概念上次を満たす。

```text
Character
├─ Skeleton3D
│  ├─ Body
│  ├─ Head
│  ├─ Hair
│  ├─ WeaponSocket
│  └─ optional BeardSocket
└─ AnimationPlayer
```

Godotの既存 `BattleUnit.setup_visual()` はPackedScene/GLBを読み込んで `AnimationPlayer` を探索できるため、Golden Pathではこの仕組みに合わせて1体を表示する。既存の `TripoRosterCharacter` にはFace差し替えの実装があるため、今後は新パイプラインのHead/Hair構造へ統合する。

## 8. Golden Path

最初から全10 Face × 全10 Bodyを処理しない。

まず以下を完成条件とする。

1. `body/001/model.glb` をBody sourceとして使用
2. `face/001/model.glb` をFace sourceとして使用
3. `face/002/model.glb` も同じBodyへ装着
4. 2体とも同じ `humanoid_v1` を使用
5. `idle / walk / attack / hit` を共通再生
6. Godotの戦闘マップ上へ配置
7. 前髪が目より手前に描画される構造を確認
8. Faceだけ交換してもBody animationが壊れないことを確認

ここまで通った時点で `Ashen Vow Character 3D Spec v1` として寸法・bone名・material名を固定する。

## 9. Validation checklist

Blender export前:

- [ ] source GLBを直接変更していない
- [ ] Body/Faceの組み合わせがmanifestと一致
- [ ] root transformが異常なscale/rotationを持っていない
- [ ] 足元原点が安定している
- [ ] Skeletonが1つに統一されている
- [ ] `head` boneが存在する
- [ ] Head/Hairを識別できる
- [ ] 首の隙間・めり込みが目立たない
- [ ] texture/materialがTripo原本から不必要に劣化していない
- [ ] animation名がprofile規約に合っている

Godot import後:

- [ ] character.glbを単体instantiateできる
- [ ] idleがループする
- [ ] walk/attack/hitが再生できる
- [ ] Face/Bodyの位置関係が崩れない
- [ ] 前髪が顔表現を正しく遮蔽する
- [ ] 既存SRPGカメラ距離でシルエットが読みやすい

## 10. 次の実装順

1. Golden PathのBody 001 + Face 001をBlender MCPで処理
2. 標準Skeleton/bone名を確定
3. Face 002へ交換して互換性確認
4. Godot側のCharacter visual definitionをJSON/Resource化
5. Face Controller（blink/expression texture）を実装
6. 共通Animation Setを整備
7. `tools/asset_gen` にCharacter管理UIを追加
8. 別ツールとしてCharacter/Skill master data管理画面を整備
