# Character Model Phase 1 — Blender / Codex Task

このドキュメントは `docs/asset/character_model_standard_v1.md` を実装するための Phase 1 作業指示。

## 対象

以下の3体だけで規格を検証する。

```text
assets/characters/tripo_adventure/adventure.glb
assets/characters/tripo_knight2/knigth.glb
assets/characters/tripo_black_mage/black_mage.glb
```

既存 raw GLB は変更・削除しないこと。

既存 `prepared/` がある場合も既存ファイルを壊さず、必要ならバックアップまたは新規出力名を使うこと。

---

## Goal

3体について以下を成立させる。

1. 同一 Master Skeleton を使用する
2. Head / Body を分離できる
3. Head を3体間で交換できる
4. 共通アニメーションを再利用できる
5. Body 色替えのための palette mask を用意できる
6. マントがあるモデルは紋章差し替えに対応できる
7. Godot へ GLB で安全にインポートできる

---

# Step 1 — Inspect Only

最初に3体を Blender へ読み込み、変更前にレポートする。

各モデルについて以下を確認する。

```text
- object names
- mesh count
- material count
- texture count
- armature count
- bone count
- bone names
- animations / actions
- vertex count
- triangle count
- bounding box
- total character height
- root transforms
- forward direction
- feet ground position
- whether weapon/shield is merged
- whether head/hair/body are connected meshes
- whether cape is separate or merged
```

レポート例:

```text
Adventure
  Armature: Armature
  Bones: 65
  Meshes: 3
  Height: 1.52m
  Head: merged with body
  Hair: merged
  Cape: none
  Weapon: none
```

**この Inspection が終わる前に大規模な自動修正を行わない。**

---

# Step 2 — Choose Master Proportions

冒険者を Phase 1 の基準キャラクターとする。

ただし Tripo の既存 Skeleton をそのまま Master Skeleton に採用しない。

`character_model_standard_v1.md` の必須構造を持つ新しい Master Skeleton を作成する。

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

Master Rest Pose:

```text
T-pose
feet on Y=0
forward = -Z
scale = 1
rotation = 0
```

---

# Step 3 — Preserve Visual Design

リグ変更のためにキャラクターの見た目を作り直さない。

特に以下を維持する。

```text
- silhouette
- head/body proportion
- face appearance
- clothing shape
- armor shape
- material / texture appearance
- current toon-like texture impression
```

不要な Decimate や Remesh は実施しない。

Topology 修正は必要な箇所のみに限定する。

---

# Step 4 — Head / Body Split

各キャラクターを以下へ分割する。

```text
Body
HeadBase
Hair (possible when safe)
Eyes (possible when safe)
Cape (when present and separable)
```

首の分割位置は3体で可能な限り同じ相対位置にする。

Body 側の襟などで seam を隠す。

Head のローカル原点／接続基準を `Head` bone に統一する。

Head を別キャラクターの Body へ載せた際に、追加修正なしで自然に見えることを目標とする。

---

# Step 5 — Bind to Master Skeleton

Tripo の元 Armature から Master Skeleton へウェイトを移す。

優先順位:

1. existing weights transfer
2. automatic weights
3. local manual correction

特に以下をチェックする。

```text
shoulders
elbows
wrists
hips
knees
neck
cape attachment
robe/skirt lower section
```

肩とローブは破綻しやすいため重点的に確認する。

---

# Step 6 — Sockets

Master Skeleton / character setup に以下を用意する。

```text
HeadSocket
WeaponSocket_R
WeaponSocket_L
```

必要であれば:

```text
ShieldSocket
BackSocket
```

Right Hand weapon は `Hand_R` を基準にする。

Left Hand weapon/shield は `Hand_L` を基準にする。

---

# Step 7 — Palette Mask

Body の主要色を変更できるように palette mask を作る。

```text
R = primary
G = secondary
B = accent
A = reserved
```

最低でも:

```text
primary
secondary
```

の2色を独立変更できること。

肌・目・髪など Body 色替え対象外の部分は mask から外す。

元テクスチャを破壊せず、別テクスチャとして出力する。

---

# Step 8 — Cape Emblem

マントが存在するキャラクターについてのみ実施。

マント上の紋章配置領域が安定するように UV を確認する。

既存絵柄を完全に焼き直すのではなく、Godot shader から `emblem_texture` を重ねられる構造を優先する。

必要なら Blender 内に `EmblemGuide` 用の非出力オブジェクトを作ってよい。

---

# Step 9 — Test Animations

Phase 1 では高度な完成アニメーションを作り込む必要はない。

まず共通 Skeleton が成立するかを確認するため、簡易アニメーションを作る。

```text
idle
walk
attack_melee
cast_magic
hit
```

全て Master Skeleton の Action として作成する。

`walk` は In-place。

チェック:

```text
Adventure -> all animations
Knight -> same animations
Black Mage -> same animations
```

キャラクターごとに Action を複製しない。

---

# Step 10 — Head Swap Validation

最低限以下を確認する。

```text
Adventure Body + Knight Head
Adventure Body + Black Mage Head
Knight Body + Adventure Head
Knight Body + Black Mage Head
Black Mage Body + Adventure Head
Black Mage Body + Knight Head
```

確認項目:

```text
neck gap
neck penetration
head scale
head position
hair/body collision
shoulder collision
animation follow
```

完全な無干渉を要求しないが、通常の SRPG カメラ距離で目立つ破綻を残さない。

---

# Step 11 — Output

各キャラクターの `prepared/` に以下を出力する。

```text
character.blend
body.glb
head_default.glb
palette_mask.png
```

マントがある場合は必要に応じて:

```text
cape_mask.png
```

Shared:

```text
assets/characters/_shared/master_rig/master_rig.blend
assets/characters/_shared/master_rig/master_rig.glb
assets/characters/_shared/animations/common_combat.blend
assets/characters/_shared/animations/common_combat.glb
```

---

# Step 12 — Do Not Do Yet

Phase 1 では以下はまだ行わない。

```text
- 全9体への一括変換
- facial animation rig
- lip sync
- complex finger animation
- physics bones final tuning
- LOD generation
- texture atlas consolidation
- destructive mesh optimization
```

3体で方式を確定してから行う。

---

# Completion Report

作業完了時には以下を報告する。

```text
1. Master Skeleton bone list
2. 3 characters' mesh/material/bone stats
3. files created/changed
4. animation reuse result
5. head swap result
6. palette change result
7. cape emblem result
8. remaining visual problems
9. changes required for character_model_standard_v1
```

規格と実モデルが合わない場合は、無理にモデルを破壊して規格へ合わせず、規格変更案を提示すること。
