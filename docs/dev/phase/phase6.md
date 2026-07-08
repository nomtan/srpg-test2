# Godot SRPGプロトタイプ Phase 6 開発指示書

## 前提

Godot 4.x / GDScript で、ボクセル風の立体マップ上で展開するSRPGプロトタイプを開発している。

すでに以下は実装済み。

### Phase 1 実装済み

* 8×8のボクセル風SRPGマップ表示
* 斜め見下ろしカメラ
* SRPG用グリッド
* ユニット配置
* カーソル操作
* ユニット選択
* 移動可能範囲表示
* 高低差を考慮した移動
* 通行不可マス判定
* 選択したマスへのユニット移動

### Phase 2 実装済み

* 味方ユニット3体
* 敵ユニット2体
* 複数ユニット管理
* 行動済み状態
* ターン制
* 敵ターンの処理
* ターン数とフェーズのUI表示

### Phase 3 実装済み

* HP
* 攻撃力
* 防御力
* 攻撃射程
* 行動メニュー
* 攻撃
* 待機
* 通常攻撃
* HP減少
* 撃破処理
* Victory / Defeat 判定
* HP表示

### Phase 4 実装済み

* 敵移動AI
* 敵の移動後攻撃
* 味方行動キャンセル
* 移動後キャンセル
* 攻撃対象選択キャンセル
* ダメージ予測UI
* 攻撃対象ハイライト
* 勝敗後の入力停止

### Phase 5 実装済み

* 近接攻撃と遠距離攻撃の区別
* `min_attack_range` / `max_attack_range`
* 弓ユニット
* 高低差による射程補正
* 高低差による命中補正
* 命中率
* 回避率
* Miss処理
* 戦闘予測UI
* BattleLog
* 敵AIの射程対応

---

## 今回の目的

Phase 6 では、SRPGの戦術性をさらに高めるため、
**射線判定・遮蔽物・地形効果・向き補正** を追加する。

Phase 5までは、射程内であれば高低差だけを見て攻撃できていた。
Phase 6では、以下のような判断が成立する状態を目指す。

```text
弓は射程内でも、壁や高い障害物に遮られていると攻撃できない
森や岩陰のマスにいるユニットは回避率が上がる
高台や草地など、地形ごとの効果がある
正面・側面・背面によって命中率やダメージが変わる
攻撃後にユニットの向きを選べる
敵AIも遮蔽物と向きを考慮して攻撃する
```

今回のゴールは、
**マップの立体構造と地形が戦闘結果に影響する状態** を作ることである。

---

## 今回追加する主な機能

* 射線判定
* 遮蔽物ブロック
* 攻撃不可ラインの判定
* 地形効果
* 地形による移動コスト・回避補正
* 向きシステム
* 正面・側面・背面判定
* 向きによる命中率・ダメージ補正
* 行動終了時の向き選択
* 敵AIの遮蔽物・地形・向き対応

---

## 1. 地形情報の拡張

`GridCell.gd` に地形効果用の情報を追加する。

```gdscript
var terrain: String = "grass"
var walkable: bool = true
var move_cost: int = 1
var height: int = 1

var evasion_bonus: int = 0
var defense_bonus: int = 0
var blocks_line_of_sight: bool = false
var blocks_movement: bool = false
```

既存の `walkable` と `blocks_movement` が重複する場合は、以下の方針にする。

```text
walkable:
  ユニットがそのマスに立てるか

blocks_movement:
  移動経路として通れないか

blocks_line_of_sight:
  弓や魔法などの射線を遮るか
```

通常の地面は以下。

```gdscript
terrain = "grass"
walkable = true
move_cost = 1
evasion_bonus = 0
defense_bonus = 0
blocks_line_of_sight = false
blocks_movement = false
```

---

## 2. 地形タイプの追加

以下の地形タイプを追加する。

```text
grass
soil
stone
forest
rock
water
high_ground
wall
```

各地形の効果は以下。

```text
grass:
  move_cost = 1
  evasion_bonus = 0
  defense_bonus = 0
  blocks_line_of_sight = false

soil:
  move_cost = 1
  evasion_bonus = 0
  defense_bonus = 0
  blocks_line_of_sight = false

stone:
  move_cost = 1
  evasion_bonus = 0
  defense_bonus = 1
  blocks_line_of_sight = false

forest:
  move_cost = 2
  evasion_bonus = 15
  defense_bonus = 0
  blocks_line_of_sight = false

rock:
  walkable = false
  blocks_movement = true
  blocks_line_of_sight = true

water:
  move_cost = 2
  evasion_bonus = -10
  defense_bonus = 0
  blocks_line_of_sight = false

high_ground:
  move_cost = 1
  evasion_bonus = 5
  defense_bonus = 1
  blocks_line_of_sight = false

wall:
  walkable = false
  blocks_movement = true
  blocks_line_of_sight = true
```

---

## 3. マップへの地形配置

既存の8×8マップに、以下を追加する。

```text
森マス: 2〜3箇所
岩マス: 2箇所
水マス: 1〜2箇所
壁または高い遮蔽物: 1〜2箇所
高台マス: 既存の高さ2〜3の場所を high_ground 扱いにする
```

例:

```text
forest:
  x=3, z=2
  x=3, z=3

rock:
  x=4, z=4
  x=5, z=4

water:
  x=2, z=5
  x=2, z=6

wall:
  x=4, z=2
```

実際の配置は既存マップとの整合性を優先してよい。

---

## 4. 地形効果の表示

カーソルをマスに合わせたとき、UIに地形情報を表示する。

表示例:

```text
Terrain: Forest
Move Cost: 2
Evasion: +15%
Defense: +0
LOS Block: No
```

岩や壁の場合:

```text
Terrain: Rock
Walkable: No
LOS Block: Yes
```

`UnitInfoPanel` または `BattleHUD` に表示してよい。

---

## 5. 移動処理への地形効果反映

`Pathfinding.gd` で、地形ごとの `move_cost` を正しく使う。

森や水は移動コスト2。

```text
move_range = 4 のユニットが森を通る場合、
森マスに入るだけで移動力を2消費する
```

通行不可地形は移動不可。

```text
rock
wall
walkable = false
blocks_movement = true
```

既存の高低差・占有マス判定も維持する。

---

## 6. 射線判定の追加

遠距離攻撃に射線判定を追加する。

追加ファイル:

```text
res://scripts/battle/LineOfSight.gd
```

責務:

* 攻撃者と対象の間のマスを取得する
* 射線を遮る地形があるか確認する
* 高さ差を考慮して遮蔽判定する
* 攻撃可能かどうかを `AttackSystem` に返す

想定メソッド:

```gdscript
func has_line_of_sight(attacker: BattleUnit, target: BattleUnit) -> bool:
    # attacker から target まで射線が通っているか判定する

func get_cells_between(from_x: int, from_z: int, to_x: int, to_z: int) -> Array:
    # 2点間の中間セルを返す

func is_cell_blocking_los(cell: GridCell, attacker_height: int, target_height: int) -> bool:
    # 指定セルが射線を遮るか判定する
```

---

## 7. 射線判定の簡易仕様

最初は厳密な3Dレイキャストではなく、グリッドベースの簡易判定でよい。

### 基本ルール

```text
攻撃者と対象の間に blocks_line_of_sight = true のマスがある場合、
遠距離攻撃は不可
```

### 高さを考慮する簡易ルール

遮蔽物マスの高さが、攻撃者と対象の低い方より高い場合、射線を遮る。

```text
attacker height = 2
target height = 1
blocking cell height = 2
=> 遮る

attacker height = 3
target height = 1
blocking cell height = 1
=> 遮らない
```

簡易式:

```gdscript
var low_height = min(attacker_cell.height, target_cell.height)
if cell.blocks_line_of_sight and cell.height > low_height:
    return true
```

厳密でなくてよい。
Phase 6では「遮蔽物の概念が動くこと」を優先する。

---

## 8. 攻撃可能判定への射線反映

`AttackSystem.can_attack()` を修正する。

遠距離攻撃の場合、以下を追加する。

```gdscript
if attacker.attack_type == BattleUnit.AttackType.RANGED:
    if not line_of_sight.has_line_of_sight(attacker, target):
        return false
```

近接攻撃には射線判定は不要。

---

## 9. 攻撃範囲ハイライトの改善

遠距離攻撃の攻撃範囲ハイライトでは、
射線が通らないマスを攻撃可能として表示しない。

つまり、以下を区別する。

```text
射程内だが射線が通る:
  攻撃可能として赤ハイライト

射程内だが遮蔽物で射線が通らない:
  攻撃不可として表示しない
  または暗い赤で表示
```

最初は「攻撃不可として表示しない」でよい。

---

## 10. 戦闘予測UIへの射線情報追加

攻撃対象選択中、射線が通らない場合はUIに理由を表示する。

表示例:

```text
Target: Bandit_A
Cannot Attack
Reason: Line of sight blocked
```

射線が通る場合:

```text
Attacker: Glen
Target: Bandit_A

Damage: 18
Hit Rate: 82%
Target HP: 80 / 80
After HP: 62 / 80
Line of Sight: Clear
```

---

## 11. 地形補正を命中・防御へ反映

`AttackSystem.calculate_hit_rate()` に対象マスの `evasion_bonus` を反映する。

```text
命中率 = 攻撃者 accuracy - 対象 evasion - 対象マス evasion_bonus + 高低差補正 + 向き補正
```

森にいる対象は回避が上がるため、攻撃側の命中率が下がる。

例:

```text
攻撃者 accuracy = 90
対象 evasion = 10
対象が森にいる evasion_bonus = 15

命中率 = 90 - 10 - 15 = 65%
```

`AttackSystem.calculate_damage()` に対象マスの `defense_bonus` を反映する。

```text
ダメージ = max(1, attacker.attack_power - target.defense - target_cell.defense_bonus)
```

---

## 12. 向きシステムの追加

`BattleUnit.gd` に向きを追加する。

```gdscript
enum FacingDirection {
    NORTH,
    EAST,
    SOUTH,
    WEST
}

var facing: FacingDirection = FacingDirection.SOUTH
```

向きはグリッド上の方向として扱う。

```text
NORTH: z - 1
SOUTH: z + 1
EAST : x + 1
WEST : x - 1
```

---

## 13. 移動時の向き変更

ユニットが移動した場合、最後に移動した方向へ向きを変える。

例:

```text
x=1,z=1 から x=2,z=1 へ移動
=> EAST を向く

x=2,z=1 から x=2,z=2 へ移動
=> SOUTH を向く
```

`UnitManager.move_unit_to_cell()` または移動確定処理で更新する。

---

## 14. 攻撃時の向き変更

攻撃した場合、攻撃対象の方向へ向きを変える。

例:

```text
Vain が右側の敵を攻撃
=> EAST を向く
```

`AttackSystem.execute_attack()` の成功時、または攻撃確定直前に更新する。

---

## 15. 向きによる命中・ダメージ補正

攻撃者が対象のどの方向から攻撃しているかを判定する。

### 正面攻撃

対象の向いている方向から攻撃される。

```text
命中補正: -5%
ダメージ補正: 0
```

### 側面攻撃

対象の横から攻撃される。

```text
命中補正: +10%
ダメージ補正: +2
```

### 背面攻撃

対象の背後から攻撃される。

```text
命中補正: +20%
ダメージ補正: +5
```

---

## 16. 攻撃方向判定

`AttackSystem.gd` に以下を追加する。

```gdscript
enum AttackDirection {
    FRONT,
    SIDE,
    BACK
}

func get_attack_direction(attacker: BattleUnit, target: BattleUnit) -> AttackDirection:
    # target の facing と attacker の位置から、正面・側面・背面を判定する
```

判定は簡易でよい。

例:

```text
target.facing = NORTH

targetより北側から攻撃:
  FRONT

targetより南側から攻撃:
  BACK

targetより東または西から攻撃:
  SIDE
```

斜め位置からの攻撃は、x差とz差の大きい方で判定する。
同じ場合は SIDE 扱いでよい。

---

## 17. 行動終了時の向き選択

味方ユニットが「待機」または「攻撃後」に行動終了する前に、
向きを選択できるようにする。

ただし、Phase 6では簡易実装でよい。

### 推奨実装

行動メニューに以下を追加する。

```text
攻撃
待機
向き変更
キャンセル
```

「向き変更」を選択したら、以下を選べる。

```text
North
East
South
West
```

選択後、ユニットの facing を変更する。

---

## 18. 待機時の向き選択

待機を選んだ場合、すぐ行動終了ではなく、向きを選ばせる。

流れ:

```text
移動
↓
行動メニュー
↓
待機
↓
向き選択
↓
行動終了
```

ただし、実装が複雑になる場合は、Phase 6では以下でもよい。

```text
待機を選ぶ
↓
現在の向きのまま行動終了
```

ただし、最低限「向き変更」メニューから手動で向きを変えられるようにする。

---

## 19. 向き表示

ユニットの向きが分かるようにする。

簡易実装でよい。

候補:

* ユニットの前方に小さな矢印を表示
* CapsuleやMeshを少し回転させる
* ユニット頭上に向きマーカーを出す

最初は矢印Meshまたは小さな三角形をユニットの前方に置く形でよい。

---

## 20. 戦闘予測UIへの向き情報追加

攻撃対象選択中に、攻撃方向を表示する。

表示例:

```text
Attacker: Vain
Target: Bandit_A

Attack Direction: Back
Damage: 31
Hit Rate: 95%
Target HP: 58 / 80
After HP: 27 / 80
Terrain: Forest
Line of Sight: Clear
```

正面の場合:

```text
Attack Direction: Front
Damage: 26
Hit Rate: 82%
```

---

## 21. 敵AIの向き対応

敵AIの行動終了時にも向きを設定する。

基本方針:

```text
敵が攻撃した場合:
  攻撃対象の方向を向く

敵が移動だけした場合:
  最も近い味方の方向を向く

敵が何もしない場合:
  最も近い味方の方向を向く
```

敵AIは、可能なら側面や背面を狙うようにしてもよい。
ただし、Phase 6では必須ではない。

---

## 22. 敵AIの射線対応

敵AIは、遠距離攻撃時に射線が通る対象だけを攻撃対象とする。

以下を徹底する。

```text
EnemyAI は AttackSystem.can_attack() を使う
AttackSystem.can_attack() は LineOfSight を含めて判定する
```

敵AI内で独自に射線判定を重複実装しない。

---

## 23. 新規追加ファイル

以下を追加する。

```text
res://scripts/battle/LineOfSight.gd
```

必要であれば以下も追加する。

```text
res://scripts/ui/FacingSelector.gd
```

---

## 24. 既存ファイルの主な変更対象

以下を拡張する。

```text
res://scripts/grid/GridCell.gd
res://scripts/grid/GridSystem.gd
res://scripts/map/VoxelMap.gd
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/Pathfinding.gd
res://scripts/ui/ActionMenu.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/Main.gd
```

---

## 25. 推奨ノード構成

既存の `Main.tscn` を以下のように拡張する。

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── BattleCursor
├── Pathfinding
├── AttackSystem
├── LineOfSight
├── EnemyAI
├── TurnManager
├── CameraController
└── UI
    ├── BattleHUD
    ├── ActionMenu
    ├── UnitInfoPanel
    ├── BattleLog
    └── FacingSelector
        ├── NorthButton
        ├── EastButton
        ├── SouthButton
        └── WestButton
```

---

## 26. 今回の完了条件

以下がすべて動作すれば完了。

1. 地形ごとに移動コストが異なる
2. 森や水などの地形がマップ上に存在する
3. 森にいるユニットは回避補正を受ける
4. 石や高台にいるユニットは防御補正を受ける
5. 岩や壁は通行不可になる
6. 岩や壁は遠距離攻撃の射線を遮る
7. 遠距離攻撃は射線が通らない対象へ攻撃できない
8. 攻撃範囲ハイライトは射線が通るマスを考慮する
9. 戦闘予測UIに地形効果が反映される
10. 戦闘予測UIに射線状態が表示される
11. 各ユニットが向きを持つ
12. 移動時に最後の移動方向へ向きが変わる
13. 攻撃時に攻撃対象の方向へ向きが変わる
14. 正面・側面・背面攻撃を判定できる
15. 側面・背面攻撃で命中率やダメージが変わる
16. 行動メニューから向きを変更できる
17. ユニットの向きが画面上で分かる
18. 敵AIも射線・地形・向きを考慮して行動する
19. 既存の移動・攻撃・命中・キャンセル・勝敗判定が壊れていない

---

## 27. 今回はまだ実装しないもの

以下はPhase 6では実装しない。

* 厳密な3Dレイキャスト射線
* 曲射
* 魔法
* スキル
* 範囲攻撃
* 回復
* 状態異常
* 属性相性
* 反撃
* 連携攻撃
* 装備
* ジョブ
* レベルアップ
* 経験値
* 攻撃アニメーション
* ダメージポップアップ
* 本格的な戦闘演出
* 会話イベント
* ステージクリア演出
* セーブ/ロード
* スマホ操作
* マップエディタ

---

## 28. 実装時の注意

* 既存のPhase 1〜5の機能を壊さない
* 射線判定は `LineOfSight.gd` に分離する
* 攻撃可能判定は必ず `AttackSystem.can_attack()` に集約する
* 敵AIは独自判定ではなく `AttackSystem.can_attack()` を使う
* 地形効果は `GridCell` に持たせる
* 移動コストは `Pathfinding` に反映する
* 命中・ダメージ計算は地形効果と向き補正を反映する
* 向き変更時にUIと見た目を更新する
* 射線が通らない対象は攻撃できないことを確認する
* 攻撃予測と実際の攻撃結果で同じ計算式を使う
* 実装が複雑になりすぎる場合、向き選択UIは簡易でよい

---

## 29. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* 地形効果の仕様
* 移動コストの仕様
* 射線判定の仕様
* 遮蔽物判定の仕様
* AttackSystem の変更点
* 向きシステムの仕様
* 正面・側面・背面判定の仕様
* 戦闘予測UIへの反映内容
* EnemyAI の変更点
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

## まず実装してください

既存の8×8ボクセル風SRPGマップ上で、
**地形効果・射線判定・向き補正** を実装してください。

具体的には以下を実装してください。

* 森・岩・水・壁・高台などの地形効果
* 地形ごとの移動コスト
* 地形による回避補正・防御補正
* 遠距離攻撃の射線判定
* 岩や壁による射線遮断
* ユニットの向き
* 正面・側面・背面攻撃判定
* 向きによる命中率・ダメージ補正
* 行動メニューからの向き変更
* 戦闘予測UIへの地形・射線・向き情報表示
* 敵AIの射線・地形・向き対応

魔法、スキル、反撃、範囲攻撃、アニメーションはまだ不要です。
まずはSRPGとしての戦術性を高めるため、
**マップ地形を活かした戦闘判定** を完成させてください。
