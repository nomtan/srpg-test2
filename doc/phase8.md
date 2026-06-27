# Godot SRPGプロトタイプ Phase 8 開発指示書

## 目的

Phase 8では、既存のSRPG戦闘システムに対して、
**ジョブ・スキル・属性・精霊システムの基礎**を追加する。

これまでのPhaseでは、移動・通常攻撃・敵AI・地形・射線・向き・ステージ進行を実装してきた。

Phase 8では、通常攻撃だけの戦闘から一段進めて、
ユニットごとの役割や個性が出るようにする。

今回のゴールは、以下のような状態を作ること。

```text
ヴェインは土属性の剣士として近接スキルを使える
アクレアは水属性の魔法剣士として水属性攻撃を使える
グレンは弓ユニットとして遠距離スキルを使える
敵も簡単なスキルを使える
スキルごとに射程・範囲・消費MP・属性・命中率・威力が異なる
攻撃前にスキルの予測UIを表示できる
```

---

## 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 移動
* 通常攻撃
* HP
* 命中率
* 回避率
* 高低差補正
* 地形効果
* 射線判定
* 向き補正
* 戦闘予測UI
* CombatConfirmPanel
* 敵AI
* 敵移動アニメーション
* 勝利/敗北条件
* StageManager
* EventManager
* TriggerManager
* MissionUI
* BattleMessage

---

# 今回の実装範囲

Phase 8では、以下を実装する。

* MP
* ジョブ情報
* 属性情報
* 精霊属性
* スキルデータ
* スキル選択UI
* スキル範囲表示
* スキル確認UI
* スキル実行
* 単体攻撃スキル
* 範囲攻撃スキル
* 回復スキル
* 属性相性
* 敵AIのスキル使用

ただし、今回はまだ以下は実装しない。

* ジョブチェンジ
* スキル習得
* レベルアップ
* 装備
* アイテム
* 複雑な状態異常
* 召喚演出
* 大規模なエフェクト

---

# 1. BattleUnit にMP・ジョブ・属性を追加する

`BattleUnit.gd` に以下を追加する。

```gdscript
enum ElementType {
    NONE,
    EARTH,
    WATER,
    WIND,
    FIRE,
    THUNDER,
    ICE,
    LIGHT,
    DARK
}

var job_id: String = ""
var job_name: String = ""

var element: ElementType = ElementType.NONE

var max_mp: int = 30
var mp: int = 30

var skill_ids: Array[String] = []
```

既存の `hp` と同じように、`mp` も初期化時に `max_mp` と同じ値にする。

---

# 2. 初期ユニット設定

既存の味方ユニットにジョブと属性を設定する。

```text
Vain:
  job_id = "swordsman"
  job_name = "剣術師"
  element = EARTH
  max_mp = 30
  skill_ids = [
    "power_slash",
    "earth_break"
  ]

Acrea:
  job_id = "magic_swordsman"
  job_name = "魔法剣士"
  element = WATER
  max_mp = 45
  skill_ids = [
    "aqua_edge",
    "healing_water"
  ]

Glen:
  job_id = "archer"
  job_name = "弓術師"
  element = WIND
  max_mp = 25
  skill_ids = [
    "aimed_shot",
    "piercing_arrow"
  ]
```

敵ユニットにも簡易スキルを設定する。

```text
Bandit_A:
  job_id = "bandit"
  job_name = "盗賊"
  element = NONE
  max_mp = 15
  skill_ids = [
    "heavy_attack"
  ]

Bandit_B:
  job_id = "enemy_archer"
  job_name = "敵弓兵"
  element = WIND
  max_mp = 20
  skill_ids = [
    "aimed_shot"
  ]
```

---

# 3. SkillData を追加する

スキルをデータとして扱う。

追加ファイル:

```text
res://scripts/skill/SkillData.gd
```

`SkillData.gd` は `Resource` として作成する。

```gdscript
class_name SkillData
extends Resource

enum SkillType {
    ATTACK,
    HEAL,
    BUFF,
    DEBUFF
}

enum TargetType {
    ENEMY,
    ALLY,
    SELF,
    EMPTY_CELL
}

enum RangeType {
    MELEE,
    RANGED,
    MAGIC
}

@export var skill_id: String
@export var skill_name: String
@export var description: String

@export var skill_type: SkillType
@export var target_type: TargetType
@export var range_type: RangeType

@export var element: BattleUnit.ElementType = BattleUnit.ElementType.NONE

@export var mp_cost: int = 0
@export var power: int = 0
@export var accuracy_modifier: int = 0

@export var min_range: int = 1
@export var max_range: int = 1
@export var area_radius: int = 0

@export var requires_line_of_sight: bool = true
@export var can_target_self: bool = false
```

---

# 4. SkillDatabase を追加する

スキルデータを一元管理する。

追加ファイル:

```text
res://scripts/skill/SkillDatabase.gd
```

責務:

* skill_id から SkillData を取得する
* 初期スキル一覧をコード上で登録する
* 後からResourceファイル化しやすい構造にする

想定メソッド:

```gdscript
func get_skill(skill_id: String) -> SkillData:
    return skills.get(skill_id)

func get_skills_for_unit(unit: BattleUnit) -> Array[SkillData]:
    var result: Array[SkillData] = []
    for skill_id in unit.skill_ids:
        var skill = get_skill(skill_id)
        if skill != null:
            result.append(skill)
    return result
```

Phase 8では、`.tres` ファイルを大量に作るより、まずはコード上で登録してよい。

---

# 5. 初期スキル一覧

Phase 8で実装するスキルは、まず以下に絞る。

## power_slash

ヴェイン用の強攻撃。

```text
skill_id: power_slash
skill_name: 強斬り
type: ATTACK
target: ENEMY
range: MELEE
element: NONE
mp_cost: 5
power: 12
accuracy_modifier: -5
min_range: 1
max_range: 1
area_radius: 0
requires_line_of_sight: false
```

## earth_break

ヴェイン用の土属性範囲攻撃。

```text
skill_id: earth_break
skill_name: アースブレイク
type: ATTACK
target: ENEMY
range: MAGIC
element: EARTH
mp_cost: 10
power: 18
accuracy_modifier: -10
min_range: 1
max_range: 2
area_radius: 1
requires_line_of_sight: false
```

## aqua_edge

アクレア用の水属性魔法剣攻撃。

```text
skill_id: aqua_edge
skill_name: アクアエッジ
type: ATTACK
target: ENEMY
range: MAGIC
element: WATER
mp_cost: 8
power: 14
accuracy_modifier: 0
min_range: 1
max_range: 2
area_radius: 0
requires_line_of_sight: false
```

## healing_water

アクレア用の回復スキル。

```text
skill_id: healing_water
skill_name: 癒しの水
type: HEAL
target: ALLY
range: MAGIC
element: WATER
mp_cost: 8
power: 25
accuracy_modifier: 0
min_range: 1
max_range: 3
area_radius: 0
requires_line_of_sight: false
```

## aimed_shot

弓ユニット用の命中重視攻撃。

```text
skill_id: aimed_shot
skill_name: 狙い撃ち
type: ATTACK
target: ENEMY
range: RANGED
element: NONE
mp_cost: 5
power: 8
accuracy_modifier: 15
min_range: 2
max_range: 4
area_radius: 0
requires_line_of_sight: true
```

## piercing_arrow

グレン用の直線貫通攻撃。

```text
skill_id: piercing_arrow
skill_name: 貫通矢
type: ATTACK
target: ENEMY
range: RANGED
element: WIND
mp_cost: 9
power: 10
accuracy_modifier: -5
min_range: 2
max_range: 4
area_radius: 0
requires_line_of_sight: true
```

Phase 8では、貫通処理はまだ厳密でなくてよい。
まずは通常の単体遠距離攻撃として実装し、名前だけ貫通矢にしてよい。

## heavy_attack

敵盗賊用の強攻撃。

```text
skill_id: heavy_attack
skill_name: 強打
type: ATTACK
target: ENEMY
range: MELEE
element: NONE
mp_cost: 4
power: 10
accuracy_modifier: -5
min_range: 1
max_range: 1
area_radius: 0
requires_line_of_sight: false
```

---

# 6. 属性相性を追加する

属性相性を管理する。

追加ファイル:

```text
res://scripts/battle/ElementSystem.gd
```

まずはシンプルな相性でよい。

```text
FIRE > ICE
ICE > WIND
WIND > EARTH
EARTH > THUNDER
THUNDER > WATER
WATER > FIRE
LIGHT > DARK
DARK > LIGHT
```

有利属性の場合:

```text
ダメージ +25%
命中率 +5%
```

不利属性の場合:

```text
ダメージ -25%
命中率 -5%
```

それ以外:

```text
補正なし
```

想定メソッド:

```gdscript
func get_element_damage_multiplier(
    attack_element: BattleUnit.ElementType,
    target_element: BattleUnit.ElementType
) -> float:
    # 有利 1.25 / 不利 0.75 / 通常 1.0

func get_element_hit_modifier(
    attack_element: BattleUnit.ElementType,
    target_element: BattleUnit.ElementType
) -> int:
    # 有利 +5 / 不利 -5 / 通常 0
```

`NONE` 属性は常に補正なし。

---

# 7. SkillSystem を追加する

スキル実行処理を管理する。

追加ファイル:

```text
res://scripts/battle/SkillSystem.gd
```

責務:

* スキル使用可能か判定する
* MPが足りるか判定する
* スキル射程を計算する
* スキル対象が有効か判定する
* スキル範囲を取得する
* スキル予測値を計算する
* スキルを実行する
* MPを消費する
* ダメージまたは回復を適用する

想定メソッド:

```gdscript
func can_use_skill(user: BattleUnit, skill: SkillData) -> bool:
    return user.mp >= skill.mp_cost and user.is_alive()

func get_skill_range_cells(user: BattleUnit, skill: SkillData) -> Array:
    # min_range / max_range / 高低差 / 射線を考慮して対象候補マスを返す

func get_skill_area_cells(center_cell: GridCell, skill: SkillData) -> Array:
    # area_radius に応じて効果範囲を返す

func can_target_skill(
    user: BattleUnit,
    skill: SkillData,
    target_cell: GridCell
) -> bool:
    # 対象が敵か味方か、射程内か、射線が必要かなどを判定する

func calculate_skill_preview(
    user: BattleUnit,
    skill: SkillData,
    target_cell: GridCell
) -> Dictionary:
    # ダメージ/回復/命中率/対象一覧などを返す

func execute_skill(
    user: BattleUnit,
    skill: SkillData,
    target_cell: GridCell
) -> Dictionary:
    # MP消費、ダメージ/回復適用、ログ用結果を返す
```

---

# 8. スキルダメージ計算

スキル攻撃のダメージは、通常攻撃をベースに以下で計算する。

```text
基本ダメージ = attacker.attack_power + skill.power - target.defense - terrain.defense_bonus
```

その後、属性補正をかける。

```text
最終ダメージ = 基本ダメージ × 属性倍率
```

最低ダメージは1。

```gdscript
damage = max(1, int(base_damage * element_multiplier))
```

---

# 9. スキル命中率計算

命中率は通常攻撃をベースにしつつ、スキル補正を加える。

```text
命中率 = 攻撃者 accuracy
       - 対象 evasion
       - 対象マス evasion_bonus
       + 高低差補正
       + 向き補正
       + 属性補正
       + skill.accuracy_modifier
```

最終的に以下へ丸める。

```text
最低 5%
最高 100%
```

回復スキルは命中判定不要で、必ず成功する。

---

# 10. 回復スキル

`healing_water` は味方を回復する。

回復量:

```text
回復量 = skill.power
```

ただし、最大HPを超えない。

```gdscript
target.hp = min(target.max_hp, target.hp + heal_amount)
```

回復対象条件:

* team が user と同じ
* 生存している
* HPが最大未満
* 射程内

Phase 8では範囲回復は不要。

---

# 11. 範囲スキル

`earth_break` は `area_radius = 1` の範囲攻撃とする。

中心マスを選択し、その周囲1マス以内の敵にダメージを与える。

範囲はマンハッタン距離でよい。

```text
center_cell から distance <= 1
```

対象:

* user と敵対しているユニット
* 生存している
* 範囲内にいる

味方には当たらない仕様でよい。
将来的にはフレンドリーファイアを検討するが、今回は不要。

---

# 12. ActionMenu に「スキル」を追加する

既存の行動メニューを以下にする。

```text
攻撃
スキル
待機
向き変更
キャンセル
```

「スキル」を選択すると、スキル一覧UIを表示する。

---

# 13. SkillMenu を追加する

追加ファイル:

```text
res://scripts/ui/SkillMenu.gd
```

UIノード例:

```text
UI
└── SkillMenu
    ├── SkillList
    ├── SkillDescriptionLabel
    └── CancelButton
```

表示内容:

```text
強斬り      MP 5
アースブレイク MP 10
```

選択中スキルの説明:

```text
アースブレイク
土属性 / 範囲攻撃
射程 1-2 / 範囲 1
MP 10
```

MP不足のスキルは選択できない、またはグレー表示にする。

---

# 14. SkillTargeting モードを追加する

`BattleCursor.gd` の状態にスキル用モードを追加する。

```gdscript
enum CursorMode {
    IDLE,
    UNIT_SELECTED,
    ACTION_MENU,
    ATTACK_TARGETING,
    COMBAT_CONFIRM,
    SKILL_MENU,
    SKILL_TARGETING,
    SKILL_CONFIRM,
    FACING_SELECT,
    ENEMY_PROCESSING,
    BATTLE_RESULT
}
```

---

# 15. スキル使用の流れ

スキル使用の流れは以下。

```text
味方ユニットを選択
↓
移動
↓
行動メニュー
↓
スキル
↓
SkillMenu表示
↓
スキル選択
↓
スキル射程表示
↓
対象マスまたは対象ユニットを選択
↓
SkillConfirmPanel表示
↓
決定
↓
スキル実行
↓
MP消費
↓
ダメージ/回復適用
↓
BattleLog表示
↓
行動済み
```

---

# 16. SkillConfirmPanel を追加する

通常攻撃用の `CombatConfirmPanel` を流用してもよいが、
スキル用の情報が増えるため、分離を推奨する。

追加ファイル:

```text
res://scripts/ui/SkillConfirmPanel.gd
```

UIノード例:

```text
UI
└── SkillConfirmPanel
    ├── SkillNameLabel
    ├── UserLabel
    ├── TargetLabel
    ├── DamageOrHealLabel
    ├── HitRateLabel
    ├── MpCostLabel
    ├── ElementLabel
    ├── AreaLabel
    ├── ConfirmButton
    └── CancelButton
```

表示例:

```text
Skill: アースブレイク
User: Vain
Target: x=5, z=4

Element: Earth
MP Cost: 10
Damage: 34
Hit Rate: 72%
Area: 1
Targets: Bandit_A, Bandit_B

Confirm / Cancel
```

回復スキルの場合:

```text
Skill: 癒しの水
User: Acrea
Target: Vain

MP Cost: 8
Heal: 25
Hit Rate: Always
After HP: 95 / 120

Confirm / Cancel
```

---

# 17. スキル範囲ハイライト

通常攻撃範囲とは別に、スキル範囲を表示する。

表示色の例:

```text
攻撃スキル射程:
  オレンジ

回復スキル射程:
  緑

範囲効果マス:
  黄色
```

既存のハイライト管理に以下を追加する。

```gdscript
func show_skill_range(cells: Array, skill: SkillData) -> void
func show_skill_area(cells: Array, skill: SkillData) -> void
func clear_skill_highlights() -> void
```

---

# 18. MP表示

既存の `BattleHUD` / `UnitInfoPanel` にMPを追加する。

表示例:

```text
Vain
HP: 120 / 120
MP: 30 / 30
Job: 剣術師
Element: Earth
```

スキル使用後にMPが減ることを確認できるようにする。

---

# 19. BattleLog のスキル対応

スキル使用時のログを追加する。

攻撃スキル成功:

```text
Vain uses アースブレイク
Bandit_A takes 34 damage
Bandit_B takes 28 damage
```

Miss:

```text
Glen uses 狙い撃ち
Miss!
```

回復:

```text
Acrea uses 癒しの水
Vain recovers 25 HP
```

MP不足:

```text
Not enough MP
```

---

# 20. 敵AIのスキル使用

敵AIもスキルを使えるようにする。

Phase 8では簡易ルールでよい。

敵AIの優先順位:

```text
1. スキルで撃破できる対象がいるなら使う
2. 通常攻撃よりスキルの予測ダメージが高い場合、MPがあれば使う
3. 範囲スキルで複数対象を巻き込めるなら使う
4. MPが足りなければ通常攻撃
```

ただし、敵のスキル使用は最初は `heavy_attack` と `aimed_shot` だけでよい。

---

# 21. ThreatSystem のスキル対応

Phase 7.5で実装した危険マス判定に、スキルの射程も考慮する。

紫マス判定に含めるもの:

* 敵の通常攻撃
* 敵の使用可能スキル
* 敵のMPが足りているスキル
* スキルの射程
* スキルの射線
* 高低差
* 範囲スキル

ただし、Phase 8ではまず単体スキルのみでもよい。
`earth_break` のような範囲スキルは、可能ならThreatSystemに反映する。

---

# 22. CombatConfirmPanel との関係

通常攻撃:

```text
CombatConfirmPanel
```

スキル:

```text
SkillConfirmPanel
```

として分ける。

ただし、内部的な予測計算は以下に分離する。

```text
AttackSystem:
  通常攻撃

SkillSystem:
  スキル
```

---

# 23. 新規追加ファイル

以下を追加する。

```text
res://scripts/skill/SkillData.gd
res://scripts/skill/SkillDatabase.gd
res://scripts/battle/SkillSystem.gd
res://scripts/battle/ElementSystem.gd
res://scripts/ui/SkillMenu.gd
res://scripts/ui/SkillConfirmPanel.gd
```

---

# 24. 既存ファイルの主な変更対象

以下を修正する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/ThreatSystem.gd
res://scripts/battle/Pathfinding.gd
res://scripts/ui/ActionMenu.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/BattleLog.gd
res://scripts/Main.gd
```

---

# 25. 推奨ノード構成

`Main.tscn` を以下のように拡張する。

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── UnitMover
├── BattleCursor
├── Pathfinding
├── AttackSystem
├── SkillSystem
├── ElementSystem
├── LineOfSight
├── ThreatSystem
├── ThreatArrowManager
├── EnemyAI
├── TurnManager
├── StageManager
├── SkillDatabase
├── CameraController
└── UI
    ├── BattleHUD
    ├── ActionMenu
    ├── SkillMenu
    ├── CombatConfirmPanel
    ├── SkillConfirmPanel
    ├── UnitInfoPanel
    ├── BattleLog
    ├── MissionUI
    └── BattleMessage
```

---

# 26. 完了条件

以下がすべて動作すれば完了。

1. 各ユニットにMPがある
2. 各ユニットにジョブ名がある
3. 各ユニットに属性がある
4. 各ユニットがスキル一覧を持つ
5. 行動メニューに「スキル」が表示される
6. スキルメニューが表示される
7. MP不足のスキルは使用できない
8. スキル選択後、スキル射程が表示される
9. 攻撃スキルで敵にダメージを与えられる
10. 回復スキルで味方を回復できる
11. 範囲スキルで複数敵にダメージを与えられる
12. スキル使用時にMPが消費される
13. 属性相性でダメージが変わる
14. 属性相性で命中率が変わる
15. SkillConfirmPanelで予測値を確認してから実行できる
16. SkillConfirmPanelでキャンセルできる
17. スキル使用結果がBattleLogに表示される
18. 敵AIがスキルを使用できる
19. ThreatSystemが敵スキルの危険範囲を考慮できる
20. 既存の通常攻撃・移動・キャンセル・勝敗判定が壊れていない

---

# 27. 今回は実装しないもの

以下はPhase 8では実装しない。

* ジョブチェンジ
* スキル習得
* スキルツリー
* レベルアップ
* 経験値
* 装備
* アイテム
* 状態異常
* 召喚
* 反撃
* 連携攻撃
* 複雑な範囲形状
* 大規模エフェクト
* 攻撃アニメーション
* ダメージポップアップ
* 会話イベント
* セーブロード
* スマホUI

---

# 28. 実装時の注意

* 通常攻撃は `AttackSystem`、スキルは `SkillSystem` に分ける
* 属性補正は `ElementSystem` に分離する
* スキルデータは `SkillData` と `SkillDatabase` で管理する
* スキルの実行前には必ず `SkillConfirmPanel` を挟む
* MP不足時はスキルを実行しない
* 回復スキルは敵に使えない
* 攻撃スキルは味方に当てない仕様でよい
* 範囲攻撃はPhase 8では敵だけ巻き込む仕様でよい
* スキル使用後は通常攻撃と同様に行動済みにする
* Victory / Defeat 判定はスキル実行後にも必ず行う
* ThreatSystemの紫マス判定が重くなりすぎないよう注意する
* 実装が複雑になりすぎる場合、敵AIのスキル使用は単体スキルから始める

---

# 29. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* BattleUnitに追加した項目
* SkillDataの仕様
* SkillDatabaseの仕様
* SkillSystemの処理フロー
* ElementSystemの属性相性
* スキルメニューの操作方法
* SkillConfirmPanelの仕様
* スキル使用時の処理フロー
* 範囲スキルの仕様
* 回復スキルの仕様
* 敵AIのスキル使用仕様
* ThreatSystemへのスキル反映内容
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**ジョブ・スキル・属性・MPの基礎システム**を追加してください。

具体的には以下を実装してください。

* BattleUnitにMP・ジョブ・属性・スキル一覧を追加
* SkillData / SkillDatabase を追加
* SkillSystem を追加
* ElementSystem を追加
* ActionMenuに「スキル」を追加
* SkillMenuを追加
* SkillConfirmPanelを追加
* 攻撃スキルを実行できるようにする
* 回復スキルを実行できるようにする
* 範囲スキルを実行できるようにする
* スキル使用時にMPを消費する
* 属性相性でダメージと命中率を補正する
* 敵AIが簡易的にスキルを使えるようにする
* ThreatSystemの危険マス判定に敵スキルを反映する

ジョブチェンジ、レベルアップ、装備、スキル習得はまだ不要です。
まずは、SRPGとしての個性を出すための
**スキル行動と属性戦闘の土台**を完成させてください。
