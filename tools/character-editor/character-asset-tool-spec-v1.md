# Character Asset Tool Specification v1

## 1. Overview

本仕様は、SRPG向け3Dキャラクター制作フローを支援する以下のツール群について定義する。

- Character Builder
- Asset Creator
- Asset Library
- Godot Export

Blockbenchを3Dモデル制作のオーサリング環境として利用し、ブラウザ上ではThree.jsを使って3Dプレビューを行う。

ブラウザ上で本格的な3Dモデリング編集は行わない。

基本フロー:

```text
Blockbench / AI Agent
        ↓
Asset Creator
        ↓
Asset Library
        ↓
Character Builder
        ↓
GLB + PNG + JSON
        ↓
Godot
```

---

## 2. Goals

### 2.1 Character Builder

既存の素体・髪型・防具・武器・テクスチャなどを組み合わせてキャラクターを作成する。

目的:

- キャラクター構成をブラウザ上で確認
- 装備やパーツを差し替え
- Palette Slotによる色変更
- Animation Preview
- キャラクター構成をJSONとして保存
- Godotで利用可能な形式へExport

### 2.2 Asset Creator

Character Builderで利用する各種Assetを作成・登録する。

v1ではブラウザ上で3Dモデルそのものを編集しない。

目的:

- Asset Typeの指定
- AI Agent向けPrompt生成
- Blockbench / AI Agentで作成したAssetのImport
- Three.js Preview
- Socket / Scale / TextureなどのValidation
- Asset Libraryへの登録

### 2.3 Asset Library

Character BuilderとAsset Creatorから共通利用するAsset管理領域。

対象例:

- Base Body
- Hair
- Headgear
- Head Accessory
- Chest Armor
- Shoulder Armor
- Arm Armor
- Gloves
- Waist
- Boots
- Weapon
- Shield
- Back Equipment
- Texture

---

## 3. Base Body

### 3.1 Body Types

基本素体は以下とする。

```text
BodyType
├─ adult
└─ child
```

female専用素体は作成しない。

女性、細身、巨漢などの差異はadult素体を基準にScaleで表現する。

### 3.2 Body Scale Parameters

v1では変更可能なScale項目を以下に限定する。

- Height
- Body Width
- Head Scale

Presetを用意する。

```text
Adult Normal
Adult Slim
Adult Large
Child
```

Preset選択後に各値を微調整できる。

自由変形は行わない。

---

## 4. Skeleton

Skeletonは3Dキャラクターをアニメーションさせるための骨組みである。

素体側がSkeletonを持ち、髪・防具・武器などのAssetはSkeletonまたはSocketへ追従する。

基本方針:

- Skeletonは素体側で共通化
- キャラクターごとにSkeletonを作り直さない
- Idle / Walk / Runなどの基本Animationを共有
- 武器カテゴリごとにAnimation Setを用意
- Assetは共通Skeletonに追従

概念例:

```text
Skeleton
├─ body
│  └─ head
├─ arm_left
│  └─ hand_left
├─ arm_right
│  └─ hand_right
├─ leg_left
│  └─ foot_left
└─ leg_right
   └─ foot_right
```

---

## 5. Animation

### 5.1 Base Animations

素体側で共通Animationを管理する。

例:

- idle
- walk
- run
- damage
- death

### 5.2 Weapon Animation Set

武器種ごとにAnimation Setを持つ。

```text
onehand_sword
great_sword
spear
bow
dagger
staff
```

各Animation Setは必要に応じて以下を持つ。

```text
idle
walk
run
attack
skill
```

Character Builderは装備中の武器Assetに設定された`animationSet`を見て使用Animationを決定する。

---

## 6. Socket System

SocketはAssetの取り付け位置を定義する。

### 6.1 Character Sockets

v1では以下を基本Socketとする。

```text
socket_head
socket_hair
socket_headgear

socket_chest
socket_back
socket_waist

socket_shoulder_left
socket_shoulder_right

socket_arm_left
socket_arm_right

socket_hand_left
socket_hand_right

socket_foot_left
socket_foot_right
```

### 6.2 Attachment Rules

推奨追従先:

```text
hair             → head
headgear         → head
head_accessory   → head

chest_armor      → body
back / cape      → body
waist            → lower body

shoulder_left    → arm_left
shoulder_right   → arm_right

glove_left       → hand_left
glove_right      → hand_right

main_hand        → hand_right
off_hand         → hand_left

boots            → foot
```

左右肩装備は独立して選択できる。

---

## 7. Asset Grip Point

武器などはCharacter Socketだけではなく、Asset自身にGrip Pointを持つ。

例:

```text
Sword
├─ geometry
└─ grip_main
```

Character Builderでは:

```text
Sword.grip_main
    ↓
socket_hand_right
```

へ自動Alignmentする。

### 7.1 Two-Handed Weapon

両手武器は以下を持つ。

```text
GreatSword
├─ grip_main
└─ grip_sub
```

対応:

```text
grip_main → socket_hand_right
grip_sub  → socket_hand_left
```

---

## 8. Equipment Handling

武器Assetには装備方式を持たせる。

```text
one_hand
two_hand
off_hand
```

例:

- Sword → one_hand
- Great Sword → two_hand
- Shield → off_hand

---

## 9. Layer System

基本ルール:

- 同一カテゴリ内では原則1Asset
- 異なるカテゴリ間ではOverlay可能

例:

```text
Body Texture
+ Chest Armor
+ Shoulder Armor
+ Cape
+ Waist
```

### 9.1 Hide Parts

防具は基本的に素体の上へOverlayする。

ただし、大型防具などで素体と干渉する場合はAsset側から対応する素体Partを非表示にできる。

例:

```json
{
  "hideParts": [
    "base_forearm_right"
  ]
}
```

---

## 10. Hair / Headgear Rules

頭装備時は基本的にHairを非表示にする。

ただし髪飾り、ティアラ、小型アクセサリなどHairと共存する装備を許可する。

`hairPolicy`:

```text
hide
overlay
```

例:

Helmet:

```json
{
  "hairPolicy": "hide"
}
```

Hair Ornament:

```json
{
  "hairPolicy": "overlay"
}
```

---

## 11. Texture

### 11.1 Resolution

Base Bodyの基本Texture Resolution:

```text
32 x 32
```

武器については32x32以外のTexture Resolutionも許可する。

防具・髪型などについては原則としてBase規格へ合わせる。

### 11.2 Palette Slots

色違いAssetを大量生成するのではなく、Character Builder上でPalette Slotを変更する。

基本Slot:

```text
primary
secondary
metal
leather
hair
skin
```

Assetごとに利用するPalette Slotを定義する。

例:

```json
{
  "paletteSlots": [
    "primary",
    "secondary",
    "metal"
  ]
}
```

---

## 12. Asset Format

Blockbenchの`.bbmodel`をオーサリング用Source Formatとする。

ブラウザPreviewおよびGodot連携にはGLB / glTFを使用する。

```text
.bbmodel
   ↓ export/build
.glb
   ↓
Three.js / Godot
```

推奨Asset Structure:

```text
hair_short_001/
├─ source/
│  └─ hair_short_001.bbmodel
├─ model.glb
├─ texture.png
├─ thumbnail.png
└─ asset.json
```

---

## 13. Asset Metadata

基本`asset.json`例:

```json
{
  "specVersion": 1,
  "assetVersion": 1,

  "id": "great_sword_001",
  "name": "Iron Great Sword",
  "type": "weapon",

  "bodyTypes": [
    "adult"
  ],

  "equipment": {
    "slot": "main_hand",
    "handling": "two_hand",
    "animationSet": "great_sword"
  },

  "attachment": {
    "main": {
      "assetPoint": "grip_main",
      "characterSocket": "socket_hand_right"
    },
    "sub": {
      "assetPoint": "grip_sub",
      "characterSocket": "socket_hand_left"
    }
  },

  "appearance": {
    "paletteSlots": [
      "primary",
      "secondary",
      "metal"
    ]
  },

  "hairPolicy": null,

  "hideParts": [],

  "model": "model.glb",
  "texture": "texture.png",
  "thumbnail": "thumbnail.png"
}
```

---

## 14. Character Builder

### 14.1 UI

基本構成:

```text
┌──────────────────────────────┐
│ Asset Categories             │
│                              │
│ Base                         │
│ Hair                         │
│ Headgear                     │
│ Head Accessory               │
│ Chest Armor                  │
│ Shoulder L / R               │
│ Arm Armor                    │
│ Gloves                       │
│ Waist                        │
│ Boots                        │
│ Main Hand                    │
│ Off Hand                     │
│ Back                         │
│                              │
├─────────────┬────────────────┤
│ Asset List  │  3D Preview    │
│             │                │
│             │   Three.js     │
│             │                │
├─────────────┴────────────────┤
│ Scale / Palette / Animation  │
└──────────────────────────────┘
```

### 14.2 Functions

- Base Body選択
- Asset選択
- Asset着脱
- 左右独立装備
- Palette変更
- Body Scale変更
- Camera操作
- Animation Preview
- Character保存
- Godot Export

---

## 15. Character Recipe

Character Builderの構成はJSONとして保存する。

例:

```json
{
  "specVersion": 1,
  "id": "vein",

  "body": {
    "base": "adult",
    "preset": "adult_normal",

    "scale": {
      "height": 1.0,
      "bodyWidth": 1.0,
      "headScale": 1.0
    }
  },

  "assets": {
    "hair": "hair_short_003",
    "headgear": null,
    "headAccessory": null,

    "chestArmor": "armor_leather_002",

    "shoulderLeft": "shoulder_iron_001",
    "shoulderRight": "shoulder_iron_001",

    "mainHand": "sword_iron_003",
    "offHand": null
  },

  "palette": {
    "primary": "#8c2430",
    "secondary": "#303030",
    "metal": "#a0a0a0",
    "leather": "#654321",
    "hair": "#36251c",
    "skin": "#d8aa85"
  }
}
```

Character Recipeを保存することで、Asset更新後もキャラクターを再構築できる。

---

## 16. Asset Creator

### 16.1 v1 Scope

v1ではブラウザ上で本格的なモデリングを行わない。

対応:

- Asset Type選択
- Base Body選択
- Asset description入力
- AI Prompt生成
- Asset Import
- Texture Import
- Three.js Preview
- Attachment Preview
- Validation
- Asset登録

非対応:

- Vertex編集
- Mesh編集
- UV編集
- Texture Paint
- Rigging編集
- Animation編集

これらはBlockbench側で行う。

---

## 17. AI Prompt Generator

v1ではAI Agentへの自動送信は行わない。

AI機能はPrompt生成のみとする。

```text
Asset Description
       ↓
Prompt Generator
       ↓
3D Model Prompt
Texture Prompt
```

### 17.1 Model Prompt

含める情報:

- Asset Type
- Style
- Target BodyType
- Scale
- Coordinate System
- Attachment Socket
- Grip Point
- Pivot / Origin
- Polygon制約
- Material制約
- UV制約
- Output Format

### 17.2 Texture Prompt

含める情報:

- Texture Resolution
- Pixel Art / Low-poly style
- Palette Slots
- Material表現
- UV Layout
- Transparency条件
- Output Format

---

## 18. Asset Validation

Asset Creatorで以下を検証する。

- ID重複
- Asset Type
- BodyType compatibility
- Socket存在
- Grip Point存在
- Position
- Rotation
- Scale
- Pivot / Origin
- Bounding Box
- Polygon Count
- Material Count
- Texture Resolution
- UV
- Transparency
- Shader compatibility
- Palette Slot
- Animation Set compatibility
- Hide Part存在

Preview:

```text
Asset Only
Base + Asset
Animation + Asset
```

の3種類を確認可能とする。

---

## 19. Three.js Preview

ブラウザPreviewはThree.jsを使用する。

対応:

- GLB表示
- Texture表示
- Character Asset合成
- Camera Rotate
- Camera Zoom
- Grid表示
- Animation再生
- Palette反映
- Hide Parts反映

ブラウザ上ではMesh編集を行わない。

---

## 20. Godot Export

v1では完成したキャラクターをBaked CharacterとしてExportする。

基本出力:

```text
character/
├─ character.glb
├─ texture.png
└─ character.json
```

GLBには以下を含める。

- Mesh
- Skeleton
- Material
- UV
- Animation

Godot側ではGLB Importによって利用する。

将来的にはGodot上でリアルタイムにAssetを組み替えるModular Character方式も検討するが、v1では対象外とする。

---

## 21. Coordinate / Scale

プロジェクト基本規格:

```text
Y Up
Godot Scale = 1.0
Blender Unit = 1
1 Field Cell = 1 meter
```

Blockbenchモデルについては、GodotへExportする際のNormalization Scaleを別途正式決定する。

Asset Creatorでは全Assetが同じNormalization Ruleに従っていることをValidationする。

---

## 22. Naming Rules

Asset IDは英小文字snake_caseとする。

例:

```text
hair_short_001
helmet_iron_001
armor_leather_002
shoulder_iron_001
sword_iron_003
great_sword_001
bow_wood_001
```

Socket / Bone / Grip Pointについても英小文字snake_caseへ統一する。

既存`base.bbmodel`にある名称は移行時にMappingを用意し、既存Animationを壊さない形で段階的に整理する。

---

## 23. Asset Categories

v1候補:

```text
base

hair
headgear
head_accessory

chest_armor

shoulder_left
shoulder_right

arm_armor
gloves

waist
boots

weapon
shield

back

texture
```

武器の細分類はMetadataで管理する。

例:

```text
sword
great_sword
spear
bow
dagger
staff
```

---

## 24. Version Management

Asset / Character RecipeにはVersionを持たせる。

```json
{
  "specVersion": 1,
  "assetVersion": 1
}
```

目的:

- Asset更新への対応
- Character再生成
- 将来仕様との互換性管理
- AI再生成時の再現性確保

---

## 25. v1 Non-Goals

以下はv1では実装対象外。

- ブラウザ上での3Dモデリング
- ブラウザ上でのUV編集
- ブラウザ上でのRigging
- ブラウザ上でのAnimation制作
- AIによる完全自動Asset生成
- Godot Runtime上での装備組み換え
- Cloth / Hair Physics
- 複雑なSkinned Armor

---

## 26. Future Extensions

将来的には以下を検討する。

- PromptからAI Agentへの直接送信
- 3D Model自動生成
- Texture自動生成
- 自動Validation
- Asset Library自動登録
- Godot Runtime Modular Character
- Character Preset共有
- Asset検索 / Tag
- Asset thumbnail自動生成
- Asset dependency管理
- Cape / Hair追加Bone
- Animation Retarget
- NPC一括生成

---

## 27. Overall Architecture

```text
                    ┌─────────────────┐
                    │    Blockbench   │
                    └────────┬────────┘
                             │ .bbmodel
                             ↓
┌─────────────────────────────────────────────┐
│               Asset Creator                 │
│                                             │
│ Type / Prompt / Import / Preview / Validate │
└──────────────────────┬──────────────────────┘
                       │
                       ↓
              ┌─────────────────┐
              │  Asset Library  │
              │                 │
              │ GLB / PNG / JSON│
              └────────┬────────┘
                       │
                       ↓
┌─────────────────────────────────────────────┐
│              Character Builder              │
│                                             │
│ Base + Asset + Palette + Scale + Animation  │
└──────────────────────┬──────────────────────┘
                       │
                       ↓
                character.json
                       +
                 character.glb
                       +
                  texture.png
                       │
                       ↓
                  ┌─────────┐
                  │  Godot  │
                  └─────────┘
```

---

## 28. Decisions Fixed in v1

- Base Bodyはadult / child
- female専用Base Bodyは作らない
- adult素体をScaleして女性・細身・巨漢を表現
- Body ScaleはHeight / Body Width / Head Scale
- SkeletonはBase Body側で共通化
- Weapon Animation Setを採用
- 武器のみ32x32以外のTextureを許可
- 色変更はPalette Slot方式
- 左右肩装備は独立
- 同一カテゴリ1Assetを基本とし、異カテゴリ間Overlayを許可
- 防具はOverlayを基本とし、必要時のみBase PartをHide
- Headgear装備時はHairを基本非表示
- Hair OrnamentなどはHairとのOverlayを許可
- Weapon Handlingはone_hand / two_hand / off_hand
- Asset Creatorでは3D編集を行わない
- AI v1はPrompt Generationのみ
- Godot Export時はAnimationをGLBへ含める
- v1 Godot ExportはBaked Character方式
- Blockbench `.bbmodel`をSource、GLBをBrowser/Godot用Formatとする
