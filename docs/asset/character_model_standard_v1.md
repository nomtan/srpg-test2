# Character Model Standard v1

Ashen Vow のプレイアブルキャラクター／NPCを Tripo で量産し、Blender でゲーム用規格へ変換し、Godot で共通アニメーションと外見差し替えを行うための標準仕様。

## 1. 目的

この規格では以下を成立させる。

- 1つの共通アニメーションを複数キャラクターで再利用する
- `Head` と `Body` を交換してキャラクターを組み立てる
- 頭部内で髪・目・眉・髭・アクセサリーを差し替える
- Body の配色をゲーム内で変更する
- マントの紋章を差し替える
- 武器・盾・杖などをモデル本体から分離して装備する
- Tripo の生成結果が多少変わってもゲーム側の仕様を壊さない

## 2. 制作パイプライン

正式な制作フローは以下とする。

```text
Reference Image
    ↓
Tripo
    ↓
raw GLB
    ↓
Blender
    ├─ transform/scale normalization
    ├─ mesh cleanup
    ├─ Head / Body split
    ├─ optional Hair / Eyes split
    ├─ master skeleton binding
    ├─ socket placement
    ├─ palette mask setup
    └─ cape emblem setup
    ↓
prepared GLB
    ↓
Godot
    ├─ appearance assembly
    ├─ shared animation library
    ├─ palette shader
    └─ emblem shader
```

Tripo の GLB は **raw source** として扱い、ゲーム内へ直接組み込む最終成果物とはしない。

## 3. 座標・単位・Transform

- Blender Unit: `1.0`
- 1 Blender unit = 1 meter
- Godot import scale = `1.0`
- Up axis: `Y`
- キャラクター正面: Godot の `-Z` を向く
- Ground: 足裏最低点を `Y = 0`
- Root object / Armature の Scale: `(1, 1, 1)`
- Root object / Armature の Rotation: `(0, 0, 0)`
- Mesh object の未適用 Scale / Rotation を残さない

キャラクター間で絶対身長を完全一致させる必要はないが、`HeadSocket` と骨格比率は共通アニメーションが破綻しない範囲に収める。

## 4. Rest Pose

ゲーム用 Master Skeleton の Rest Pose は **T-pose** に統一する。

要件:

- 左右の腕は水平
- 手のひらの向きを全キャラで統一
- 膝・肘を極端に曲げない
- 左右の足を重ねない
- 肩・脇・指・脚の間にウェイト調整できる最低限の隙間を確保する

Tripo 側の生成ポーズに差がある場合は Blender で Master Rest Pose に補正する。

## 5. Master Skeleton

全キャラクターの Body は、最終的に同一の Master Skeleton へバインドする。

### 5.1 必須ボーン

```text
Root
└─ Hips
   ├─ Spine
   │  └─ Chest
   │     ├─ Neck
   │     │  └─ Head
   │     ├─ Shoulder_L
   │     │  └─ UpperArm_L
   │     │     └─ LowerArm_L
   │     │        └─ Hand_L
   │     └─ Shoulder_R
   │        └─ UpperArm_R
   │           └─ LowerArm_R
   │              └─ Hand_R
   ├─ UpperLeg_L
   │  └─ LowerLeg_L
   │     └─ Foot_L
   └─ UpperLeg_R
      └─ LowerLeg_R
         └─ Foot_R
```

### 5.2 任意ボーン

必要に応じて以下を追加してよい。

```text
Toe_L
Toe_R
Cape_01..n
Hair_01..n
Skirt_01..n
Accessory_01..n
```

ただし必須ボーンの名前・親子関係は変更しない。

### 5.3 方針

- Tripo Auto Rig の Skeleton は中間成果物として利用してよい
- Godot で使用する最終 Skeleton は Master Skeleton に統一する
- キャラ固有の揺れ物ボーンは追加可能
- 共通アニメーションは必須ボーンのみを基本ターゲットとする

## 6. Character Node Standard

Godot では概念的に以下の構成とする。

```text
CharacterRoot
├─ Skeleton3D
├─ BodySet
│  ├─ BodyMesh
│  ├─ CapeMesh        # optional
│  └─ OtherBodyMesh   # optional
├─ HeadSocket
│  └─ HeadSet
│     ├─ HeadBase
│     ├─ Hair
│     ├─ Eyes
│     ├─ Eyebrows
│     ├─ Beard         # optional
│     └─ Accessory     # optional
├─ WeaponSocket_R
├─ WeaponSocket_L
└─ AnimationPlayer / AnimationTree
```

Skeleton は CharacterRoot に1つだけ持つことを基本とする。

## 7. Head / Body 分割

### 7.1 Body

Body は首より下を担当する。

含めるもの:

- 胴体
- 腕
- 手
- 脚
- 靴
- 服
- 鎧
- 肩当て
- マント
- 腰装備

含めないもの:

- 顔
- 頭髪
- 目
- 眉
- 髭
- 頭部アクセサリー

### 7.2 Head

Head は首接続位置より上を担当する。

最低構成:

```text
HeadBase
Hair
Eyes
```

初期段階では HeadBase と Hair が一体でも許容するが、量産用正式アセットでは分離を推奨する。

### 7.3 Neck Seam

全 Body / Head で首接続規格を統一する。

- Head 原点は `Head` bone / HeadSocket 基準
- 首の接続部は襟・スカーフ・鎧などで隠せるデザインを優先
- Body ごとに Head の位置補正を必要としないことを目標とする
- やむを得ない場合のみ appearance data に head offset を持たせる

## 8. Head Customization

推奨パーツ分類:

```text
head_base_###
hair_###
eyes_###
eyebrows_###
beard_###
head_accessory_###
```

例:

```text
head_base_001
hair_003
eyes_002
eyebrows_001
beard_none
```

### 8.1 髪互換性

長髪は Body との干渉が起こるため互換タグを持たせる。

例:

```text
hair_012:
  compatible: [normal, robe]
  incompatible: [heavy_armor, high_collar]
```

## 9. Body Color Customization

服色変更のため、完成テクスチャへの単純 Hue Shift は使用しない。

`palette_mask` を使う。

### 9.1 Palette Mask Channel

```text
R = primary
G = secondary
B = accent
A = reserved / optional
```

Godot shader parameters:

```text
primary_color
secondary_color
accent_color
```

肌、髪、金属等を色替え対象外にしたい場合は palette mask を 0 にする。

### 9.2 命名

```text
body_<id>_albedo.png
body_<id>_palette.png
```

必要に応じて normal / ORM 等を追加する。

## 10. Cape Emblem

紋章は Body の Albedo へ固定で焼き込まない。

マントに Emblem 用 UV 領域を用意し、Godot shader で overlay する。

推奨 texture:

```text
emblem_none.png
emblem_kingdom.png
emblem_empire.png
emblem_church.png
```

Shader parameters:

```text
emblem_texture
emblem_color
emblem_enabled
```

可能な限り複数 Body で同じ Emblem UV レイアウトを利用する。

## 11. Equipment Socket

最低限以下を用意する。

```text
WeaponSocket_R
WeaponSocket_L
HeadSocket
```

追加候補:

```text
BackSocket
HipSocket_R
HipSocket_L
ShieldSocket
```

武器・盾・杖は原則として Tripo のキャラクターモデルに一体化しない。

## 12. Common Animation Standard

### 12.1 v1 必須

```text
idle
walk
attack_melee
cast_magic
hit
ko
```

### 12.2 後続候補

```text
attack_sword
attack_spear
attack_bow
attack_staff
guard
hit_heavy
victory
revive
```

### 12.3 Animation Rule

- 移動アニメーションは原則 In-place
- マス間移動は Godot 側で CharacterRoot を移動する
- 共通アニメーションは Master Skeleton 基準で作成する
- キャラ固有の Cape / Hair bone は共通アニメーションの必須対象にしない
- Animation 名は小文字 snake_case

## 13. File Naming

Raw Tripo source:

```text
assets/characters/tripo_<character>/
  <character>.glb
```

Prepared asset:

```text
assets/characters/tripo_<character>/prepared/
  character.blend
  body.glb
  head_default.glb
  palette_mask.png        # when required
```

`face_default.glb` は既存資産として残してよいが、新規規格では `head_default.glb` を使用する。

Shared resources:

```text
assets/characters/_shared/
  master_rig/
    master_rig.blend
    master_rig.glb
  animations/
    common_combat.blend
    common_combat.glb
  heads/
  hair/
  eyes/
  emblems/
```

## 14. Tripo Generation Rules

今後 Tripo へ渡すキャラクターデザインでは以下を守る。

- T-pose
- 正面・側面・背面の形状を読み取りやすくする
- 武器、盾、杖を手に持たせない
- 腕を胴体から離す
- 左右の脚を離す
- 髪と肩・背中を可能な限り接触させない
- 長髪は身体へ貼り付けない
- マントは胴体・腕と形状的に分離して見えるようにする
- 首と襟の境界を明確にする
- 左右非対称の装飾は必要最小限にする
- 紋章や勢力マークは生成画像へ固定で描かないことを推奨
- キャラクターごとに極端な骨格比率差を作らない

## 15. Blender Conversion Checklist

Tripo raw model から prepared model を作る際に以下を実施する。

- [ ] Scale / Rotation apply
- [ ] feet Y=0
- [ ] forward = -Z
- [ ] unwanted mesh cleanup
- [ ] weapon / shield removal
- [ ] Head / Body split
- [ ] Hair separation where practical
- [ ] Eyes separation where practical
- [ ] Master Skeleton bind
- [ ] weight normalization
- [ ] shoulder deformation check
- [ ] elbow deformation check
- [ ] knee deformation check
- [ ] neck seam check
- [ ] WeaponSocket_R / L placement
- [ ] HeadSocket placement
- [ ] palette mask setup
- [ ] cape emblem UV setup when cape exists
- [ ] idle test
- [ ] walk test
- [ ] attack test
- [ ] cast test
- [ ] hit test
- [ ] GLB export

## 16. Acceptance Criteria

prepared asset は以下を満たした場合にゲーム用として採用する。

1. Master Skeleton の必須ボーン構造に一致する
2. 共通 `idle` / `walk` / `attack_melee` / `cast_magic` / `hit` を適用して大きく破綻しない
3. Head を別 Body へ交換して首の隙間・極端なズレが出ない
4. 武器が右手 Socket へ正しく追従する
5. palette mask で最低 primary / secondary の2色を変更できる
6. マント有り Body は emblem texture を差し替えられる
7. Godot import scale 1.0 で使用できる

## 17. Phase 1 Pilot

最初の検証対象は以下の3体とする。

```text
assets/characters/tripo_adventure/adventure.glb
assets/characters/tripo_knight2/knigth.glb
assets/characters/tripo_black_mage/black_mage.glb
```

Phase 1 で確認する内容:

- Master Skeleton を1つ作成
- 3体を Master Skeleton へ統一
- Head / Body 交換
- `idle`
- `walk`
- `attack_melee`
- `cast_magic`
- `hit`
- Body color variation
- Cape があるモデルで emblem replacement

3体で成立を確認後、以下へ展開する。

```text
tripo_butler
tripo_chief_butler
tripo_hiro
tripo_scholar
tripo_warrior
tripo_white_mage
```

## 18. Migration Policy

既存の raw GLB や `prepared/character.blend` は削除しない。

新規規格への移行は以下の順序で行う。

1. raw source を保持
2. `prepared/character.blend` を編集マスターにする
3. 新規 `body.glb` / `head_default.glb` を出力
4. Godot 上で検証
5. 問題がなければ既存 character.glb 使用箇所を段階的に置換

これにより既存シーンを壊さずに新方式へ移行する。
