# Character Model Phase 1.5 — Correction Task

この文書は `character_model_phase1_report.md` の未合格項目を修正し、Phase 2へ進める状態にするための作業指示。

参照:

- `character_model_standard_v1.md`
- `character_model_standard_v1_1_addendum.md`
- `character_model_phase1_report.md`

対象はPhase 1と同じ3体のみ。

```text
assets/characters/tripo_adventure/adventure.glb
assets/characters/tripo_knight2/knigth.glb
assets/characters/tripo_black_mage/black_mage.glb
```

既存raw、legacy prepared、`prepared/phase1/` は変更しないこと。

新規出力は以下へ作成する。

```text
prepared/phase1_5/
```

---

# Goal

Phase 1で成立した構造検証を維持しながら、以下の外観未合格を解消する。

1. Master Rest強制による体型崩れ
2. shoulder / sleeve / crotch / robe の変形
3. Head swap時の首の隙間
4. Black MageのBody側へ残る髪
5. Palette maskの誤領域
6. Knightの焼き込み紋章
7. walk時の足裏沈み込み

Phase 1.5では新しい機能を増やすより、**3体が量産規格として安全に成立すること**を優先する。

---

# Step 1 — Skeleton conversion policyを変更

Phase 1で使用した「3体のRest Matrixを完全一致させる」方式を廃止する。

## 必須

3体で以下を共通にする。

- bone names
- hierarchy
- semantic role
- local axis convention
- T-pose direction
- socket naming

ただし各モデルの体型を維持するため、以下はモデル固有値を許容する。

- bone head/tail position
- bone length
- Rest / Bind matrix

### 禁止

Master RigのRest位置へ合わせる目的で、元メッシュの頂点を大きく移動させない。

特にBlack MageはPhase 1で最大約0.447mの頂点移動が発生しているため、raw silhouetteを基準に再構築する。

### Master Rig

`assets/characters/_shared/master_rig/master_rig.blend` はAnimation Source / naming / hierarchy / axesの基準として維持する。

---

# Step 2 — Retarget pipelineを作る

`common_combat.blend` のMaster animationをSourceとして使用する。

対象:

```text
idle
walk
attack_melee
cast_magic
hit
```

Source Animationを各キャラクターのsemantic skeletonへRetargetする。

## 方針

- rotationを優先
- 不要なbone translation trackを作らない
- root motionは使用しない
- walkはin-place
- character-specific cloth bonesは必要に応じて追加補正してよい

Godot Runtimeで同一AnimationLibraryを直接共有して外観が維持できるなら共有してよい。

維持できない場合はprepared時にretarget/bakeし、以下のように出力してよい。

```text
prepared/phase1_5/animations/common_combat.glb
```

ただし元アニメーションの正本は `_shared/animations/common_combat.blend` 1つだけとする。

---

# Step 3 — Weight修正

以下を重点修正する。

```text
shoulder
armpit
upper sleeve
elbow
crotch
robe / skirt
knee
ankle
foot
cape
```

特にBlack Mageはローブを脚だけへ追従させない。

必要であれば既存の

```text
Skirt_01
Skirt_02
Cape_01_L
Cape_02_L
Cape_01_R
Cape_02_R
```

を使用してweightを再配分する。

必要ならcloth用boneを追加してよいが、共通必須bone hierarchyは変更しない。

### Acceptance

5共通Animationで以下が目立たないこと。

- 極端な三角形伸長
- 肩の潰れ
- 袖のねじれ
- 股下の引き裂き
- ローブの脚への貼り付き
- 足首の破綻

---

# Step 4 — Foot contact修正

`idle` と `walk` を確認する。

- idle時に足裏がgroundへ自然に接地
- walk時に接地脚が床へ大きく沈まない
- CharacterRootは移動させない
- animationはin-placeを維持

必要ならMaster Animation側を修正し、その後3体へ再Retargetする。

キャラクター別にwalk motionを独自編集するのは避ける。

---

# Step 5 — Head / Body semantic splitをやり直す

Phase 1の単純水平cutを最終方式にしない。

## Headへ含める

```text
face
head
hair
long hair
eyes if safely separable
head accessory
```

長髪は首より下へ伸びていてもHead扱い。

## Bodyへ含めない

Black Mageの髪ポリゴンをBodyへ残さない。

### 分離手段

必要に応じて以下を併用する。

- manual vertex selection
- UV / texture region
- geometry inspection
- vertex group
- material / color boundary

完全自動化を優先しなくてよい。

まず正しい意味分割を確立する。

---

# Step 6 — Neck seamを修正

HeadSocketの位置・向きは全キャラで同じルールにする。

Head下端には必要に応じて `0.01m - 0.02m` 程度のneck overlapを作り、Bodyの襟または首内部へ隠す。

以下の6組を再検証する。

```text
Adventure Body + Knight Head
Adventure Body + Black Mage Head
Knight Body + Adventure Head
Knight Body + Black Mage Head
Black Mage Body + Adventure Head
Black Mage Body + Knight Head
```

### 合格条件

- 顎下に背景が見える穴がない
- Body側へ元Hairが残らない
- Headが浮いて見えない
- Headが襟へ極端に埋まらない
- 追加の組み合わせ別offsetを原則不要とする

どうしても特定BodyとHeadが干渉する場合は、無理な変形をせずcompatibilityとして記録する。

---

# Step 7 — Palette Maskを手直し

Phase 1の自動生成maskを叩き台として使用してよい。

正式maskでは意味領域を目視確認し、UV上で修正する。

```text
R = primary
G = secondary
B = accent
A = reserved
```

### 色替え対象外

```text
skin
hair
eyes
teeth
metal
fixed ornaments
```

特にBlack MageのBody側Hair問題を解消した後にmaskを再生成する。

### Godot render test

各キャラで以下を保存する。

1. original
2. primary changed
3. secondary changed
4. primary + secondary changed
5. accent changed（使用している場合）

---

# Step 8 — Knight Emblemをclean化

Knightの元Albedoへ焼き込まれた金色紋章をprepared assetでは残さない。

raw textureを変更してはならない。

prepared側へ無紋章textureを作る。

推奨名:

```text
body_albedo_clean.png
```

方法は以下のいずれでもよい。

- texture paint clone/heal
- 周辺textureからpatch作成
- UV areaの再ペイント

clean albedoを使用した状態で

```text
emblem_enabled = false
```

なら完全に無紋章になること。

そのうえで別emblemをoverlayする。

### Adventure

垂れ布が狭く、紋章表示領域として不自然なら無理に対応させない。

その場合はvalidationへ

```text
supports_emblem: false
```

を記録する。

---

# Step 9 — Socket verification

以下を再検証する。

```text
HeadSocket
WeaponSocket_R
WeaponSocket_L
BackSocket
```

- HeadSocket follows Head
- WeaponSocket_R follows Hand_R
- WeaponSocket_L follows Hand_L
- BackSocket follows Chest / back reference

Restがキャラクター固有になった後でも追従が正しいことを確認する。

---

# Step 10 — Output

各キャラ:

```text
assets/characters/tripo_<character>/prepared/phase1_5/
  character.blend
  body.glb
  head_default.glb
  palette_mask.png
  validation.json
  body_albedo_clean.png   # 必要な場合
  cape_mask.png           # 必要な場合
  animations/
    common_combat.glb     # bake方式を採用した場合のみ
```

raw / legacy prepared / phase1 outputは変更しない。

---

# Step 11 — Visual validation

Godotで実描画し、最低限以下のcontact sheetを作る。

```text
artifacts/character_phase1_5/
  animations_contact_sheet.jpg
  head_swaps_contact_sheet.jpg
  palette_contact_sheet.jpg
  emblem_contact_sheet.jpg
```

Animation contact sheetは3キャラ × 5アニメーションを確認できること。

Head swapは6組すべて確認できること。

---

# Step 12 — Phase 1.5 Report

以下へ結果を記録する。

```text
docs/asset/character_model_phase1_5_report.md
```

最低限記載する。

- skeleton strategy
- Rest差異
- retarget方法
- weight修正内容
- 3体のanimation結果
- 6 Head swap結果
- palette結果
- emblem結果
- socket結果
- 未解決事項
- Phase 2へ進めるかの判定

---

# Acceptance Criteria

以下をすべて満たしたらPhase 2へ進む。

- [ ] 共通bone names / hierarchy / axesを維持
- [ ] 3体の元シルエットを大きく崩していない
- [ ] Master Sourceから共通Animationをretargetできる
- [ ] idleが外観合格
- [ ] walkが外観合格
- [ ] attack_meleeが外観合格
- [ ] cast_magicが外観合格
- [ ] hitが外観合格
- [ ] walkの足裏沈み込みが目立たない
- [ ] 6 Head swapで穴がない
- [ ] Black Mage BodyにHairが残らない
- [ ] palette maskにskin/hair/metalの目立つ誤混入がない
- [ ] Knightを完全な無紋章状態にできる
- [ ] 別emblemを表示できる
- [ ] Head / Weapon / Back Socketが追従する
- [ ] Godotでprepared GLBを実描画確認済み
- [ ] raw / legacy prepared / phase1を変更していない

一項目でも外観上重大な未合格が残る場合、Phase 2のRuntime Character Builder実装へ進まない。
