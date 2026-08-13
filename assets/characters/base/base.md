# SRPGキャラクター素体 分解・アニメーション作成指示書

## 1. 目的

1枚の完成済み male キャラクター素体画像を基準として、身体を複数のパーツへ分解し、Godot上で再構成する。

分解した素体を利用して、

* Idle
* Walk
* Attack
* Damage
* Skill
* Casting
* Death

などのキャラクターアニメーションを効率的に作成できる構造を構築する。

最終的には、同一の身体アニメーションを利用して、

* 髪型
* 顔
* 服
* 鎧
* 武器
* 盾
* マント

などを差し替えられるキャラクターシステムへ発展できる構造とする。

---

# 2. 入力画像

入力として以下を使用する。

* male 素体キャラクター 1体
* 背景透過PNG
* 左前向き
* ピクセルアート
* 完成状態の立ちポーズ

画像のキャラクターサイズ、頭身、手足の長さ、太さ、輪郭、陰影は変更しない。

元画像をキャラクター造形の基準とする。

---

# 3. 最重要ルール

元画像のデザインを変更してはならない。

以下は完全に維持する。

* 頭の大きさ
* 頭身
* 胴体の長さ
* 腕の長さ
* 腕の太さ
* 脚の長さ
* 脚の太さ
* 手の大きさ
* 足の大きさ
* 顔の位置
* 目の位置
* 輪郭線
* ピクセル密度
* 陰影
* 色数
* カラーパレット

「アニメーションしやすくするため」という理由で身体形状を変更してはならない。

---

# 4. パーツ分割

male素体を以下のパーツへ分割する。

## Body

```text
head
torso
waist
```

## Left Arm

```text
arm_l_upper
arm_l_lower
hand_l
```

## Right Arm

```text
arm_r_upper
arm_r_lower
hand_r
```

## Left Leg

```text
leg_l_upper
leg_l_lower
foot_l
```

## Right Leg

```text
leg_r_upper
leg_r_lower
foot_r
```

合計15パーツを基本とする。

---

# 5. 各パーツの定義

## head

含めるもの：

* 頭部
* 顔
* 耳
* 首の上部

含めないもの：

* 胴体
* 肩
* 腕

回転中心：

```text
首の付け根
```

---

## torso

含めるもの：

* 首下
* 胸
* 腹部上部
* 肩の根本

回転中心：

```text
腰との接続部分
```

---

## waist

含めるもの：

* 腹部下部
* 腰
* 骨盤部分

キャラクター全体の基準となるパーツとする。

原則としてキャラクターアニメーションのRootに最も近いパーツとする。

---

## arm_upper

含める範囲：

```text
肩 → 肘
```

回転中心：

```text
肩関節
```

---

## arm_lower

含める範囲：

```text
肘 → 手首
```

回転中心：

```text
肘関節
```

---

## hand

含める範囲：

```text
手首 → 指先
```

回転中心：

```text
手首
```

---

## leg_upper

含める範囲：

```text
股関節 → 膝
```

回転中心：

```text
股関節
```

---

## leg_lower

含める範囲：

```text
膝 → 足首
```

回転中心：

```text
膝
```

---

## foot

含める範囲：

```text
足首 → 足先
```

回転中心：

```text
足首
```

---

# 6. パーツ分割時の重要ルール

単純に元画像を切り抜くだけではなく、関節部分には隠れていた領域を補完する。

例えば腕を分離した場合、元画像では腕に隠れている胴体部分を復元する。

同様に、

* 肩の裏
* 肘の接続部
* 股関節
* 膝
* 首
* 足首

についても必要なピクセルを補完する。

目的は、パーツを回転させたときに、

```text
黒い穴
透明部分
身体の欠け
```

が発生しないようにすることである。

---

# 7. オーバーラップ

関節ではパーツ同士を数px重ねる。

例：

```text
Torso
   ↓
UpperArm

UpperArm
   ↓
LowerArm

LowerArm
   ↓
Hand
```

完全に境界線で切断しない。

2〜数px程度の重なりを持たせる。

ピクセルアートとして不自然にならない範囲で調整する。

---

# 8. 出力PNG

各パーツは独立した背景透過PNGとして出力する。

例：

```text
character/
└─ male/
   └─ front_left/
      ├─ head.png
      ├─ torso.png
      ├─ waist.png

      ├─ arm_l_upper.png
      ├─ arm_l_lower.png
      ├─ hand_l.png

      ├─ arm_r_upper.png
      ├─ arm_r_lower.png
      ├─ hand_r.png

      ├─ leg_l_upper.png
      ├─ leg_l_lower.png
      ├─ foot_l.png

      ├─ leg_r_upper.png
      ├─ leg_r_lower.png
      └─ foot_r.png
```

全PNGは元画像と同じピクセル密度を維持する。

画像補間やアンチエイリアスを入れない。

---

# 9. Canvasサイズ

すべてのパーツPNGは、可能であれば元キャラクター画像と同一Canvasサイズを使用する。

例：

元素体：

```text
128 × 128
```

なら、

```text
head.png       128 × 128
torso.png      128 × 128
arm_l.png      128 × 128
...
```

とする。

各パーツを元画像と同じ座標へ配置した場合に、元キャラクターが完全に復元される状態を作る。

これによりGodot上で初期位置調整を容易にする。

---

# 10. Godotでのシーン構造

Godotでは以下のようなNode2D構造を基本とする。

```text
CharacterRig
│
└─ Root
   │
   └─ Waist
      │
      ├─ Torso
      │  │
      │  ├─ Head
      │  │
      │  ├─ ArmLUpper
      │  │  └─ ArmLLower
      │  │     └─ HandL
      │  │
      │  └─ ArmRUpper
      │     └─ ArmRLower
      │        └─ HandR
      │
      ├─ LegLUpper
      │  └─ LegLLower
      │     └─ FootL
      │
      └─ LegRUpper
         └─ LegRLower
            └─ FootR
```

各関節を親子構造にする。

---

# 11. Godot Node

各身体パーツは基本的に、

```text
Node2D
└─ Sprite2D
```

とする。

例：

```text
ArmLUpper : Node2D
└─ Sprite2D
```

Node2Dの原点を関節位置として使用する。

Sprite2D側をオフセットして、画像上の関節位置とNode2D原点を一致させる。

---

# 12. Pivot設定

各Node2Dの原点を以下へ設定する。

```text
Head
→ 首

Torso
→ 腰

UpperArm
→ 肩

LowerArm
→ 肘

Hand
→ 手首

UpperLeg
→ 股関節

LowerLeg
→ 膝

Foot
→ 足首
```

Rotationを変更した際に、正しい関節位置から回転することを確認する。

---

# 13. 描画順序

左前向きの場合、身体の前後関係を固定する。

例：

```text
奥側の腕
奥側の脚

↓

胴体

↓

手前側の脚
手前側の腕

↓

頭
```

具体的なz_indexは元画像を見て調整する。

身体の前後関係が元素体と完全に一致することを優先する。

---

# 14. Godot Import設定

ピクセルアートのため、Texture Filterは無効化する。

補間表示を行わない。

基本方針：

```text
Nearest / Filter Off
```

とする。

拡大縮小する場合も整数倍率を優先する。

例：

```text
1x
2x
3x
4x
```

---

# 15. Transformルール

可能な限り位置は整数値を使用する。

推奨：

```text
position.x = 整数
position.y = 整数
```

小数ピクセル移動は避ける。

例：

避ける：

```text
x = 10.42
y = 23.65
```

推奨：

```text
x = 10
y = 24
```

---

# 16. 回転について

ピクセルアートでは自由角度回転によって輪郭が崩れる可能性がある。

そのため大きく角度を変更する場合は、

```text
-30
-20
-10
0
10
20
30
```

など比較的限定した角度を使用する。

必要に応じて回転後のSpriteをピクセル単位で補正する。

---

# 17. AnimationPlayer

アニメーション制御にはGodotのAnimationPlayerを基本として使用する。

```text
CharacterRig
├─ Root
│  └─ ...
│
└─ AnimationPlayer
```

AnimationPlayerから、

```text
position
rotation
scale
visible
```

などを制御する。

ただし、scaleによる身体サイズ変更は原則使用しない。

---

# 18. 最初に作るアニメーション

以下の順番で作成する。

```text
1. idle
2. walk
3. attack
4. damage
5. skill
6. death
```

最初にidleとwalkを完成させて、パーツ構造が正しいことを確認してから他アニメーションを作成する。

---

# 19. Idle

まず6フレーム相当で作成する。

想定：

```text
Frame 1
通常

Frame 2
腰をわずかに下げる

Frame 3
通常

Frame 4
腰をわずかに上げる

Frame 5
通常

Frame 6
通常
```

必要に応じて、

```text
Head
±1〜2°

Torso
±1°

Arm
±1〜3°
```

程度の小さな動きを追加する。

Idleではキャラクター造形を崩さない。

---

# 20. Walk

基本6フレーム。

```text
Frame 1
左足前
右足後

Frame 2
左足接地

Frame 3
両足中央

Frame 4
右足前
左足後

Frame 5
右足接地

Frame 6
両足中央
```

必ず、

```text
左足前
↓
右腕前

右足前
↓
左腕前
```

となるよう腕を振る。

---

# 21. 歩行時の腰

腰は完全固定しない。

歩行に合わせて1〜2px程度上下させる。

例：

```text
Frame 1   0px
Frame 2  -1px
Frame 3  +1px
Frame 4   0px
Frame 5  -1px
Frame 6  +1px
```

実際の見た目を優先して調整する。

---

# 22. 頭の動き

歩行中でも頭は大きく動かさない。

基本的には腰の上下運動に追従するだけとする。

必要なら1px程度の遅れを作る。

頭を激しく振らない。

---

# 23. 足の接地

SRPGキャラクターでは特に足元の位置を安定させる。

歩行フレームごとにキャラクター全体が左右へズレないようにする。

Root座標を一定にして、

```text
Leg
Foot
Waist
```

側で歩行を表現する。

---

# 24. Attack

片手剣など武器を使用する場合は、

```text
Hand
└─ WeaponSocket
```

を作る。

WeaponSocketへ武器Spriteを配置する。

構造：

```text
ArmUpper
└─ ArmLower
   └─ Hand
      └─ WeaponSocket
         └─ Weapon
```

手を動かすだけで武器が追従する状態にする。

---

# 25. 装備差し替え対応

将来的に以下を追加可能な構造とする。

```text
Body
ArmorBody

Head
Hair
Helmet

Arm
ArmorArm

Leg
ArmorLeg

Back
Cape

Hand
Weapon

Hand
Shield
```

身体アニメーションと装備アニメーションを可能な限り共有する。

---

# 26. パーツの命名規則

Node名：

```text
Head
Torso
Waist

ArmLUpper
ArmLLower
HandL

ArmRUpper
ArmRLower
HandR

LegLUpper
LegLLower
FootL

LegRUpper
LegRLower
FootR
```

画像：

```text
head.png
torso.png
waist.png

arm_l_upper.png
arm_l_lower.png
hand_l.png

arm_r_upper.png
arm_r_lower.png
hand_r.png

leg_l_upper.png
leg_l_lower.png
foot_l.png

leg_r_upper.png
leg_r_lower.png
foot_r.png
```

---

# 27. Direction管理

最終的には最低限、

```text
front_left
back_right
```

の2方向を用意する。

それぞれ独立したRigとしてもよい。

例：

```text
rig/
├─ male_front_left.tscn
└─ male_back_right.tscn
```

または同一CharacterRig内で方向ごとのSpriteを切り替えてもよい。

最初はfront_leftのみ完成させる。

---

# 28. アニメーション名

Godot内では統一する。

```text
idle
walk
attack
damage
skill
cast
death
```

方向別にする場合：

```text
idle_front_left
walk_front_left
attack_front_left

idle_back_right
walk_back_right
attack_back_right
```

---

# 29. SpriteSheet書き出し

ゲーム内でパーツアニメーションをそのまま使用する方法と、完成アニメーションをSpriteSheet化する方法の両方を想定する。

推奨方式は、

```text
パーツRig
↓
AnimationPlayer
↓
アニメーション制作
↓
各フレームをPNG出力
↓
SpriteSheet作成
↓
ゲーム本編ではSprite2D / AnimatedSprite2D
```

とする。

パーツRigは「アニメーション制作ツール」として使用する。

---

# 30. SpriteSheet仕様

例として6フレームWalkの場合、

```text
walk_front_left.png

[1][2][3][4][5][6]
```

の横一列とする。

Idleも、

```text
idle_front_left.png

[1][2][3][4][5][6]
```

の形式とする。

将来的にGodotのSpriteFramesへ登録する。

---

# 31. アニメーション制作時の禁止事項

以下は禁止。

* キャラクターの頭身変更
* 頭サイズ変更
* 腕を長くする
* 腕を短くする
* 脚を長くする
* 脚を短くする
* 身体を細くする
* 身体を太くする
* 手を巨大化する
* 足を巨大化する
* アンチエイリアス追加
* ぼかし
* スムージング
* グロー
* モーションブラー
* AIによる形状の再解釈

---

# 32. 最終確認

パーツをすべて初期位置へ戻したとき、

入力されたmale素体と見た目がほぼ完全一致することを確認する。

確認項目：

```text
頭位置
肩位置
腕位置
手位置
腰位置
股関節位置
膝位置
足位置

シルエット
ピクセル密度
陰影
輪郭
```

---

# 33. 完了条件

以下を満たした時点で基本Rig完成とする。

* male front_left を15パーツ前後へ分割
* 各パーツPNGを背景透過で出力
* 関節部を補完
* Godot CharacterRigを作成
* 正しい親子関係を設定
* Pivot設定完了
* 元素体の立ち姿を再現
* Idle完成
* Walk 6フレーム完成
* ピクセル崩れなし
* 足元の位置が安定
* SpriteSheetとして出力可能

---

# 34. 作業順序

必ず以下の順番で進める。

```text
STEP 1
male front_left 素体画像読み込み

STEP 2
15パーツへ分割

STEP 3
関節の隠れ部分を補完

STEP 4
各パーツを透過PNGとして保存

STEP 5
Godot CharacterRig作成

STEP 6
親子構造設定

STEP 7
Pivot設定

STEP 8
初期姿勢を元素体と一致させる

STEP 9
Idle作成

STEP 10
Walk 6フレーム作成

STEP 11
SpriteSheet書き出し確認

STEP 12
Attack等へ展開
```

---

# 35. 最終目標

この素体を基準として、

```text
BODY ANIMATION
        +
HAIR
        +
FACE
        +
ARMOR
        +
CLOTHES
        +
WEAPON
        +
SHIELD
        +
CAPE
```

を組み合わせるだけで、多数のSRPGキャラクターを制作できる共通アニメーション基盤を構築する。

身体アニメーションをキャラクターごとに作り直すのではなく、

**共通male/female素体アニメーションを中心として、外見パーツを差し替える方式**

を最終的な設計方針とする。
