# Character Model Standard v1.1 Addendum

この文書は `character_model_standard_v1.md` の Phase 1 検証結果を受けた補足・修正规格である。

矛盾する記述がある場合は、この v1.1 Addendum を優先する。

参照:

- `character_model_standard_v1.md`
- `character_model_phase1_report.md`

---

## 1. Skeleton の共通化定義を修正する

### 1.1 共通化するもの

全キャラクターで以下を共通化する。

- 必須ボーン名
- 必須ボーンの親子関係
- 各ボーンの意味
- 左右命名規則
- ローカル軸の向き
- T-pose の基準方向
- Socket の意味と命名

### 1.2 完全一致を要求しないもの

キャラクター固有の体型を維持するため、以下は完全一致を必須としない。

- 必須ボーンの絶対位置
- ボーン長
- キャラクター固有の Rest / Bind matrix

**Master Skeleton の Rest 行列へ頂点を大きく移動させて外観を合わせる処理は禁止する。**

Phase 1 で Black Mage に大きな形状変化が発生したため、今後は「モデルをMaster Restへ変形する」のではなく、「共通Semantic Skeletonへマッピングし、AnimationをRetargetする」を基本とする。

### 1.3 Master Rig の役割

`assets/characters/_shared/master_rig/master_rig.blend` は以下の基準として使用する。

- アニメーション制作元
- ボーン命名・階層の基準
- 軸方向の基準
- Socket名の基準
- Retarget元

各 prepared character は Master Rig と同じ semantic skeleton を持つが、体型固有の Rest / Bind を持ってよい。

### 1.4 Animation の共通化

共通アニメーションは **1つのMaster Rig上のSource Animationを唯一の正本** とする。

```text
master_rig
  ↓
common animation source
  ↓
retarget
  ├─ adventure
  ├─ knight
  └─ black_mage
```

Runtimeで同一AnimationLibraryを直接共有できる場合は共有してよいが、外観維持のために必要なら prepared 時にキャラクター別へRetarget/Bakeしてよい。

重要なのは「アニメーション制作をキャラごとにやり直さない」ことであり、「全キャラが完全に同一のGLB Animation Trackを持つこと」ではない。

共通Actionでは可能な限り必須ボーンの Rotation を中心に使用し、キャラクター固有の骨長へ依存する Translation Track を増やさない。

---

## 2. Head / Body の意味的分割

Head / Body は高さによる水平カットだけで決定してはならない。

### Head に含めるもの

- 顔
- 頭部
- 髪
- 長髪
- 目
- 眉
- 髭
- 帽子・兜などの頭部装備
- 頭部に属するアクセサリー

長髪は首より下、肩や背中まで伸びても Head 側に含める。

### Body に含めるもの

- 首より下の肌
- 胴体
- 腕・手
- 脚・足
- 服
- 鎧
- 襟
- 肩装備
- ローブ
- マント
- 腰装備

髪ポリゴンを Body に残してはならない。

### 2.1 Neck connection

統一対象は「水平カット面」ではなく以下とする。

- `HeadSocket` 基準
- Head root transform
- Neck 接続領域
- Head forward/up axes

首の隙間対策として、Head側の首下端をBodyの襟・首内部へ少量オーバーラップさせてよい。

推奨 overlap: `0.01m - 0.02m` 程度を初期値とし、外側から二重面が見えない位置へ収める。

Bodyごとの個別位置補正を常用しない。必要な場合はBody/Headの互換性問題として記録し、汎用補正で吸収できない組み合わせは compatibility tag で除外する。

---

## 3. Hair / Eyes の扱い

量産用正式アセットでは、可能な限り以下を別パーツ化する。

```text
HeadSet
├─ HeadBase
├─ Hair
├─ Eyes
├─ Eyebrows
├─ Beard
└─ HeadAccessory
```

Tripo raw が一体メッシュの場合、単純 connected-component split だけで安全に分離できないことを前提とする。

分離には以下を併用してよい。

- UV / texture領域
- vertex group
- manual selection
- geometry boundary
- material slot
- Blender上での手動修正

Phase 1.5では最低限、長髪を含む `Head + Hair` がBodyへ残らない状態を必須とする。Eyes単体分離はPhase 2以降へ持ち越してよい。

---

## 4. Palette Mask Acceptance

Palette Mask はチャンネルが存在するだけでは合格としない。

### Channel

```text
R = primary
G = secondary
B = accent
A = reserved
```

### 必須条件

色替え対象外の以下は原則0にする。

- skin
- hair
- eyes
- teeth
- metallic equipment
- weapon
- fixed ornaments

実描画で以下を確認する。

- primaryのみ変更
- secondaryのみ変更
- accentのみ変更（使用する場合）
- 全色変更
- original colors

自動推定マスクは初期生成として利用してよいが、正式アセットではUV上で意味領域を確認・修正する。

---

## 5. Cape Emblem Acceptance

新規Tripoモデルでは、差し替える可能性がある勢力紋章を Albedo に焼き込まない。

### 既存モデルに紋章が焼き込み済みの場合

raw GLB / raw texture は保持し、prepared 側に **無紋章のclean albedo** を作成する。

```text
body_albedo_original
        ↓
prepared clean texture
        ↓
Godot emblem overlay
```

透明Emblem Textureを重ねたときに元紋章が見える状態は不合格。

Emblem用の面積が狭すぎるBodyは無理に対応させず、以下のmetadataを持たせてよい。

```text
supports_emblem = false
```

---

## 6. Character deformation acceptance

Master Skeletonへの変換時に、元の体型・衣装シルエットを大きく変えてはならない。

重点確認箇所:

- shoulder
- armpit
- sleeve
- elbow
- crotch
- skirt / robe
- knee
- ankle
- foot contact
- cape
- neck seam

ローブやマントなどの大面積布は、必要に応じて `Skirt_*` / `Cape_*` ボーンへ適切にweightを割り当てる。

共通Animationを適用した際に、局所的な極端な伸び・潰れ・穴・裏返りが見える場合は不合格とする。

---

## 7. Coordinate rule clarification

制作空間とRuntime空間を区別する。

### Blender

- Z-up
- +Y forward を制作基準としてよい

### GLB / Godot

- Y-up
- character forward = -Z

Head rigid asset の local basis と `HeadSocket` の basis を一致させ、二重変換を行わない。

---

## 8. Migration path

検証中は既存preparedを上書きしない。

```text
prepared/phase1/
prepared/phase1_5/
```

Phase 1.5 が外観Acceptanceまで合格した後にのみ、正式な

```text
prepared/body.glb
prepared/head_default.glb
```

へ昇格する。

---

## 9. Phase 1.5 exit criteria

Adventure / Knight / Black Mage の3体で以下を満たすこと。

1. 共通Semantic Skeleton名・階層・軸が一致する
2. キャラクター固有Restを維持して元シルエットを大きく崩さない
3. Master Animation Sourceから3体へRetargetできる
4. `idle / walk / attack_melee / cast_magic / hit` が大きく破綻しない
5. 6通りのHead swapで髪残留・顎下の穴がない
6. Palette変更でskin/hair/metalへの誤混入が目立たない
7. Knightの元紋章を消した状態で別紋章を表示できる
8. WeaponSocket_R/L、HeadSocket、BackSocketが追従する
9. Godot上でprepared GLBを実描画確認する
10. raw / legacy preparedを変更しない

上記を満たしてから Phase 2 のRuntime Character Builder実装へ進む。
