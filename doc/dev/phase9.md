# Godot SRPGプロトタイプ Phase 9 開発指示書

## 目的

Phase 9では、既存のSRPG戦闘システムに対して、
**経験値・レベルアップ・ジョブ成長・スキル習得の基礎システム**を追加する。

Phase 8 / Phase 8.5 では、以下を実装した。

* ジョブ
* スキル
* 属性
* AP
* SkillData
* SkillDatabase
* SkillSystem
* ElementSystem
* スキル確認UI
* スキル使用
* 回復スキル
* 範囲スキル
* AP消費
* FloatingNumber演出
* ThreatSystemのスキル対応

Phase 9では、戦闘中の行動や敵撃破によってユニットが成長し、
新しいスキルを覚えられる状態を目指す。

今回のゴールは以下。

```text id="jlhuw6"
敵にダメージを与える
↓
経験値を得る
↓
敵を撃破すると追加経験値を得る
↓
経験値が一定値に達するとレベルアップ
↓
ステータスが上昇する
↓
ジョブ経験値も得る
↓
ジョブレベルが上がる
↓
新しいスキルを習得する
↓
次の戦闘で使えるようになる
```

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 通常攻撃
* HP
* AP
* 攻撃力
* 防御力
* 命中率
* 回避率
* 地形効果
* 射線判定
* 向き補正
* 戦闘予測UI
* CombatConfirmPanel
* SkillMenu
* SkillConfirmPanel
* SkillSystem
* ElementSystem
* ThreatSystem
* EnemyAI
* StageManager
* Victory / Defeat
* BattleLog
* FloatingNumber

---

# 今回の実装範囲

Phase 9では以下を実装する。

* ユニットレベル
* 経験値
* レベルアップ
* ステータス成長
* ジョブレベル
* ジョブ経験値
* ジョブデータ
* ジョブ成長テーブル
* スキル習得条件
* 戦闘中の経験値獲得
* ステージ終了後の成長結果表示
* レベルアップ演出
* スキル習得ログ

ただし、今回は以下はまだ実装しない。

* ジョブチェンジ
* 装備
* アイテム
* スキルツリーUI
* クラスチェンジ
* 複雑な成長補正
* 拠点画面
* セーブ/ロード

---

# 1. BattleUnit にレベル・経験値を追加する

`BattleUnit.gd` に以下を追加する。

```gdscript id="r2klyr"
var level: int = 1
var exp: int = 0
var exp_to_next_level: int = 100
```

レベルアップ判定用メソッドを追加する。

```gdscript id="ic7ajh"
func add_exp(amount: int) -> Array:
    exp += amount

    var level_up_results: Array = []

    while exp >= exp_to_next_level:
        exp -= exp_to_next_level
        var result = level_up()
        level_up_results.append(result)

    return level_up_results

func level_up() -> Dictionary:
    level += 1

    var growth_result = apply_level_growth()

    return {
        "unit": self,
        "new_level": level,
        "growth": growth_result
    }
```

---

# 2. 基本ステータスを整理する

Phase 9以降、将来的なジョブ・装備・成長に備えて、
ユニットのステータスを以下のように整理する。

既存のステータスがある場合は、互換性を壊さないように追加する。

```gdscript id="hjm6vi"
var strength: int = 10
var dexterity: int = 10
var vitality: int = 10
var mind: int = 10
var intelligence: int = 10
var agility: int = 10
```

既存の戦闘用ステータスは、当面は以下のように維持してよい。

```gdscript id="lm3wai"
var max_hp: int
var hp: int

var max_ap: int
var ap: int

var attack_power: int
var defense: int
var accuracy: int
var evasion: int
```

ただし、将来的には基本ステータスから戦闘値を算出できる構成にする。

---

# 3. レベルアップ時の成長

レベルアップ時にステータスを上昇させる。

まずは固定成長でよい。

```gdscript id="oikfcl"
func apply_level_growth() -> Dictionary:
    var growth = {
        "max_hp": 5,
        "max_ap": 1,
        "attack_power": 1,
        "defense": 1,
        "accuracy": 1,
        "evasion": 1
    }

    max_hp += growth["max_hp"]
    max_ap += growth["max_ap"]
    attack_power += growth["attack_power"]
    defense += growth["defense"]
    accuracy += growth["accuracy"]
    evasion += growth["evasion"]

    hp = max_hp
    ap = max_ap

    return growth
```

Phase 9ではランダム成長ではなく、固定成長でよい。
後からジョブ成長率に置き換えやすいよう、メソッド化しておく。

---

# 4. ユニットごとの初期レベル

既存ユニットに初期レベルを設定する。

```text id="mkwj4y"
Vain:
  level = 1
  exp = 0

Acrea:
  level = 1
  exp = 0

Glen:
  level = 1
  exp = 0

Bandit_A:
  level = 1

Bandit_B:
  level = 1
```

敵もレベルを持つ。
経験値計算時に、敵レベルを参照できるようにする。

---

# 5. ExperienceSystem を追加する

経験値獲得処理を `ExperienceSystem.gd` に分離する。

追加ファイル:

```text id="0uzpoe"
res://scripts/battle/ExperienceSystem.gd
```

責務:

* ダメージ時の経験値計算
* 撃破時の経験値計算
* 回復時の経験値計算
* スキル使用時の経験値計算
* 経験値付与
* レベルアップ結果の収集
* BattleLog / BattleMessage用の結果返却

想定メソッド:

```gdscript id="k2j5br"
func calculate_damage_exp(
    actor: BattleUnit,
    target: BattleUnit,
    damage: int
) -> int:
    # ダメージを与えた時の経験値

func calculate_defeat_exp(
    actor: BattleUnit,
    target: BattleUnit
) -> int:
    # 敵を撃破した時の追加経験値

func calculate_heal_exp(
    actor: BattleUnit,
    target: BattleUnit,
    heal_amount: int
) -> int:
    # 回復した時の経験値

func grant_exp(
    actor: BattleUnit,
    amount: int
) -> Dictionary:
    # 経験値を付与し、レベルアップ結果を返す
```

---

# 6. 経験値獲得ルール

Phase 9では簡易ルールでよい。

## ダメージを与えた時

```text id="7r8q8t"
獲得EXP = 10
```

ただし、Missやダメージ0の場合は獲得しない。

## 敵を撃破した時

```text id="mlv6x4"
追加EXP = 30
```

つまり、攻撃して撃破した場合は以下。

```text id="tujf5j"
ダメージEXP 10 + 撃破EXP 30 = 40
```

## 回復した時

```text id="pl8qpr"
獲得EXP = 10
```

ただし、実際にHPが回復した場合のみ。
HP満タンの味方に回復を使ってもEXPは得ない。

## レベル差補正

Phase 9では、可能なら以下を追加する。

```text id="934pzk"
対象のレベルが自分より高い:
  EXP +5

対象のレベルが自分より低い:
  EXP -5

最低EXP:
  1
```

難しければ、Phase 9では固定EXPのみでよい。

---

# 7. 攻撃結果から経験値を付与する

通常攻撃後、攻撃結果に応じて経験値を付与する。

想定処理:

```gdscript id="gg31k7"
var result = attack_system.execute_attack(attacker, target)

if result.hit and result.damage > 0:
    experience_system.grant_exp(
        attacker,
        experience_system.calculate_damage_exp(attacker, target, result.damage)
    )

if result.defeated:
    experience_system.grant_exp(
        attacker,
        experience_system.calculate_defeat_exp(attacker, target)
    )
```

ただし、敵ユニットには経験値を付与しなくてもよい。
Phase 9では、プレイヤーユニットのみ経験値を得る。

---

# 8. スキル結果から経験値を付与する

`SkillSystem.execute_skill()` の結果に応じて経験値を付与する。

攻撃スキルの場合:

```text id="ihh1ze"
Hitしてダメージを与えた対象1体につきEXP 10
撃破した対象1体につき追加EXP 30
```

回復スキルの場合:

```text id="fc433k"
実際にHPを回復した対象1体につきEXP 10
```

範囲スキルの場合、複数対象に当たったら対象ごとに経験値を加算する。

例:

```text id="ewv5an"
earth_breakで2体に命中
1体撃破

ダメージEXP 10 × 2 = 20
撃破EXP 30 × 1 = 30
合計EXP 50
```

---

# 9. 経験値ログ表示

経験値獲得時にBattleLogへ表示する。

例:

```text id="idcfj8"
Vain gains 10 EXP
Vain gains 30 EXP
Vain level up! Lv 2
```

回復時:

```text id="xi1td8"
Acrea gains 10 EXP
```

レベルアップ時:

```text id="6vwet5"
Vain level up! Lv 2
HP +5 / AP +1 / ATK +1 / DEF +1
```

---

# 10. レベルアップ演出

レベルアップ時に簡易演出を出す。

表示例:

```text id="ljja0x"
LEVEL UP!
Vain Lv 2
```

実装候補:

* `BattleMessage` に表示
* `FloatingNumber` のようにユニット上に `Level Up!` を出す
* BattleLogに表示

最低限、BattleLogとBattleMessageに表示すればよい。

---

# 11. JobData を追加する

ジョブ情報をデータ化する。

追加ファイル:

```text id="kvquxa"
res://scripts/job/JobData.gd
```

`JobData.gd` は `Resource` として作る。

```gdscript id="gqps9c"
class_name JobData
extends Resource

@export var job_id: String
@export var job_name: String
@export var description: String

@export var base_move_range: int = 4
@export var base_jump_height: int = 1

@export var hp_growth: int = 5
@export var ap_growth: int = 1
@export var attack_growth: int = 1
@export var defense_growth: int = 1
@export var accuracy_growth: int = 1
@export var evasion_growth: int = 1

@export var learnable_skills: Array[Dictionary] = []
```

`learnable_skills` の例:

```gdscript id="4elclj"
[
    {
        "job_level": 2,
        "skill_id": "guard_stance"
    },
    {
        "job_level": 3,
        "skill_id": "earth_break"
    }
]
```

---

# 12. JobDatabase を追加する

追加ファイル:

```text id="grg6y7"
res://scripts/job/JobDatabase.gd
```

責務:

* job_id から JobData を取得する
* 初期ジョブを登録する
* ユニットのジョブ成長情報を取得する

想定メソッド:

```gdscript id="9jko74"
func get_job(job_id: String) -> JobData:
    return jobs.get(job_id)

func get_growth_for_job(job_id: String) -> Dictionary:
    var job = get_job(job_id)
    if job == null:
        return {}
    return {
        "max_hp": job.hp_growth,
        "max_ap": job.ap_growth,
        "attack_power": job.attack_growth,
        "defense": job.defense_growth,
        "accuracy": job.accuracy_growth,
        "evasion": job.evasion_growth
    }
```

Phase 9では `.tres` ファイルではなく、コード上で初期登録してよい。

---

# 13. ジョブ成長をレベルアップへ反映する

`BattleUnit.apply_level_growth()` を、ジョブ成長値に対応させる。

推奨として、`ExperienceSystem` または `UnitManager` から `JobDatabase` を参照して成長値を渡す。

例:

```gdscript id="cvd3qm"
func apply_level_growth(growth: Dictionary) -> Dictionary:
    max_hp += growth.get("max_hp", 5)
    max_ap += growth.get("max_ap", 1)
    attack_power += growth.get("attack_power", 1)
    defense += growth.get("defense", 1)
    accuracy += growth.get("accuracy", 1)
    evasion += growth.get("evasion", 1)

    hp = max_hp
    ap = max_ap

    return growth
```

ジョブが見つからない場合は固定成長を使う。

---

# 14. 初期ジョブデータ

Phase 9では、以下のジョブを登録する。

## swordsman

```text id="l99w17"
job_id: swordsman
job_name: 剣術師
description: 近接攻撃に優れた基本ジョブ

growth:
  hp +6
  ap +1
  attack +2
  defense +1
  accuracy +1
  evasion +0

learnable_skills:
  job_level 2: guard_stance
```

## magic_swordsman

```text id="dqlb77"
job_id: magic_swordsman
job_name: 魔法剣士
description: 近接攻撃と属性スキルを扱うジョブ

growth:
  hp +4
  ap +2
  attack +1
  defense +1
  accuracy +1
  evasion +1

learnable_skills:
  job_level 2: aqua_edge
  job_level 3: healing_water
```

## archer

```text id="20rqgf"
job_id: archer
job_name: 弓術師
description: 遠距離攻撃と命中に優れたジョブ

growth:
  hp +4
  ap +1
  attack +1
  defense +0
  accuracy +2
  evasion +1

learnable_skills:
  job_level 2: aimed_shot
  job_level 3: piercing_arrow
```

## bandit

```text id="e6oul8"
job_id: bandit
job_name: 盗賊
description: 素早さと回避に優れた敵ジョブ

growth:
  hp +4
  ap +1
  attack +1
  defense +0
  accuracy +1
  evasion +2

learnable_skills:
  job_level 2: heavy_attack
```

---

# 15. ジョブ経験値を追加する

`BattleUnit.gd` に以下を追加する。

```gdscript id="iw4ugb"
var job_level: int = 1
var job_exp: int = 0
var job_exp_to_next_level: int = 50
```

ジョブ経験値用メソッドを追加する。

```gdscript id="0w8nhs"
func add_job_exp(amount: int) -> Array:
    job_exp += amount

    var job_level_up_results: Array = []

    while job_exp >= job_exp_to_next_level:
        job_exp -= job_exp_to_next_level
        job_level += 1
        job_level_up_results.append({
            "unit": self,
            "job_level": job_level
        })

    return job_level_up_results
```

---

# 16. ジョブ経験値獲得ルール

Phase 9では簡易ルールにする。

```text id="netzbv"
通常攻撃を実行:
  JobEXP +5

スキルを使用:
  JobEXP +8

敵を撃破:
  追加 JobEXP +5

回復を実行:
  JobEXP +5
```

Missでも、行動した場合はJobEXPを得てよい。
ただし、キャンセルしただけでは得ない。

---

# 17. JobSystem を追加する

ジョブ経験値・ジョブレベルアップ・スキル習得を管理する。

追加ファイル:

```text id="gy9pfw"
res://scripts/job/JobSystem.gd
```

責務:

* JobEXP付与
* JobLevelUp判定
* 習得可能スキル判定
* 新規スキル習得
* BattleLogへの結果返却

想定メソッド:

```gdscript id="uk6b99"
func grant_job_exp(unit: BattleUnit, amount: int) -> Dictionary:
    # JobEXPを付与し、レベルアップや習得スキルを返す

func check_learned_skills(unit: BattleUnit) -> Array[String]:
    # 現在のjob_levelで習得できる未習得スキルを返す

func learn_skill(unit: BattleUnit, skill_id: String) -> bool:
    # 未習得ならskill_idsへ追加する
```

---

# 18. スキル習得処理

ジョブレベルが上がったとき、
`JobData.learnable_skills` を参照して新しいスキルを習得する。

例:

```text id="0r4ofr"
Vain job_level が2になる
↓
swordsman の learnable_skills を確認
↓
job_level 2 で guard_stance を習得
↓
Vain.skill_ids に guard_stance を追加
↓
BattleLog に表示
```

表示例:

```text id="ajfvyp"
Vain learned Guard Stance
```

---

# 19. 新スキル guard_stance を追加する

Phase 9では、スキル習得確認用として新スキルを1つ追加する。

## guard_stance

ヴェインがジョブレベル2で習得する防御スキル。

```text id="s4rgdl"
skill_id: guard_stance
skill_name: ガードスタンス
type: BUFF
target: SELF
range: MAGIC
element: NONE
ap_cost: 6
power: 0
accuracy_modifier: 0
min_range: 0
max_range: 0
area_radius: 0
requires_line_of_sight: false
can_target_self: true
```

Phase 9では、バフ効果の本格実装はまだ不要。
まずは使用すると `BattleLog` に表示され、APを消費し、行動済みになるだけでもよい。

可能であれば、1ターンだけ防御力 +3 を付与する簡易効果を入れる。

---

# 20. 簡易バフ状態の追加

`guard_stance` を成立させるため、簡易的なバフ状態を追加してもよい。

`BattleUnit.gd` に以下を追加する。

```gdscript id="to9s5f"
var temporary_defense_bonus: int = 0
```

`calculate_damage()` 時に防御値へ加算する。

```gdscript id="a9a1p0"
var total_defense = target.defense + target.temporary_defense_bonus
```

ターン開始時または次の自分の行動開始時にリセットする。

```gdscript id="42usj9"
func reset_temporary_bonuses() -> void:
    temporary_defense_bonus = 0
```

Phase 9では、複雑な状態管理システムは不要。

---

# 21. ステージ終了後の成長結果表示

Victory後に、成長結果を表示するUIを追加する。

追加ファイル:

```text id="qg2zxd"
res://scripts/ui/GrowthResultPanel.gd
```

表示内容:

```text id="o4sezy"
Stage Clear

Vain
Lv 1 -> Lv 2
EXP: 30 / 100
Job: 剣術師 Lv 1 -> Lv 2
Learned: ガードスタンス

Acrea
Lv 1
EXP: 40 / 100
Job: 魔法剣士 Lv 1

Glen
Lv 1
EXP: 20 / 100
Job: 弓術師 Lv 1
```

Phase 9では、Victory時に表示されるだけでよい。
次のステージ遷移や保存は不要。

---

# 22. 成長結果の記録

ステージ中に発生した成長結果を記録するため、
`ExperienceSystem` または `StageManager` に履歴を持たせる。

例:

```gdscript id="63onqz"
var growth_events: Array = []
```

記録するもの:

```text id="mvd0eb"
EXP獲得
レベルアップ
ステータス上昇
JobEXP獲得
JobLevelUp
スキル習得
```

Victory時に `GrowthResultPanel` に渡す。

---

# 23. UnitInfoPanel に成長情報を表示する

`UnitInfoPanel` に以下を追加する。

```text id="2n4acc"
Lv: 2
EXP: 30 / 100
Job: 剣術師 Lv 2
JobEXP: 10 / 50
AP: 28 / 31
```

戦闘中に確認できる程度でよい。

---

# 24. 敵への経験値付与について

Phase 9では、敵には経験値を付与しなくてよい。

ただし、敵も `level` や `job_level` を持つ構造にする。
将来的に敵の強さや報酬EXP計算に使うためである。

---

# 25. BattleLog の拡張

BattleLogに以下を表示できるようにする。

```text id="k0g20l"
Vain gains 10 EXP
Vain gains 5 JobEXP
Vain level up! Lv 2
Vain job level up! 剣術師 Lv 2
Vain learned ガードスタンス
```

---

# 26. BattleMessage の拡張

大きな通知として、以下を表示する。

```text id="nwzon1"
LEVEL UP!
Vain Lv 2
```

ジョブレベルアップ時:

```text id="io8ia5"
JOB LEVEL UP!
Vain 剣術師 Lv 2
```

スキル習得時:

```text id="s4m1yi"
SKILL LEARNED!
ガードスタンス
```

---

# 27. 新規追加ファイル

以下を追加する。

```text id="bxur3q"
res://scripts/battle/ExperienceSystem.gd
res://scripts/job/JobData.gd
res://scripts/job/JobDatabase.gd
res://scripts/job/JobSystem.gd
res://scripts/ui/GrowthResultPanel.gd
```

---

# 28. 既存ファイルの主な変更対象

以下を修正する。

```text id="rlqgdr"
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/SkillSystem.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/TurnManager.gd
res://scripts/battle/StageManager.gd
res://scripts/skill/SkillDatabase.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/BattleLog.gd
res://scripts/ui/BattleMessage.gd
res://scripts/Main.gd
```

---

# 29. 推奨ノード構成

`Main.tscn` を以下のように拡張する。

```text id="yox9zm"
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
├── ExperienceSystem
├── JobSystem
├── JobDatabase
├── LineOfSight
├── ThreatSystem
├── ThreatArrowManager
├── FloatingNumberManager
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
    ├── BattleMessage
    └── GrowthResultPanel
```

---

# 30. 完了条件

以下がすべて動作すれば完了。

1. 味方ユニットがレベルを持つ
2. 味方ユニットがEXPを持つ
3. 敵ユニットもレベルを持つ
4. ダメージを与えるとEXPを得る
5. 敵を撃破すると追加EXPを得る
6. 回復するとEXPを得る
7. EXPが100以上になるとレベルアップする
8. レベルアップ時にステータスが上昇する
9. レベルアップ時にHP/APが回復する
10. BattleLogにEXP獲得とレベルアップが表示される
11. BattleMessageにLEVEL UPが表示される
12. ユニットがJobLevelとJobEXPを持つ
13. 通常攻撃・スキル使用・撃破・回復でJobEXPを得る
14. JobEXPが一定値に達するとJobLevelが上がる
15. JobLevelUp時にBattleLog / BattleMessageへ表示される
16. JobLevel条件を満たすと新しいスキルを習得する
17. 習得したスキルがSkillMenuに表示される
18. `guard_stance` を習得できる
19. `guard_stance` を使用できる
20. UnitInfoPanelにLv / EXP / JobLv / JobEXPが表示される
21. Victory後にGrowthResultPanelが表示される
22. GrowthResultPanelで成長結果を確認できる
23. 既存の通常攻撃・スキル・AP・ThreatSystem・敵AI・勝敗判定が壊れていない

---

# 31. 今回は実装しないもの

以下はPhase 9では実装しない。

* ジョブチェンジ
* クラスチェンジ
* スキルツリー
* スキルポイント
* 装備
* アイテム
* ショップ
* 拠点画面
* セーブ/ロード
* ランダム成長
* 成長率
* 複雑なバフ/デバフ管理
* 状態異常
* 反撃
* 連携攻撃
* ステージ間のユニット永続管理
* スマホUI

---

# 32. 実装時の注意

* Phase 9では成長システムの基礎だけを作る
* レベルアップはまず固定成長でよい
* JobData / JobDatabase を使い、後からジョブ追加しやすくする
* ExperienceSystem と JobSystem の責務を分ける
* スキル習得は JobSystem に集約する
* SkillDatabaseに存在しないskill_idを習得しないようにする
* すでに習得済みのスキルを重複追加しない
* 敵にはEXPを付与しなくてよい
* 回復EXPは実際にHPが回復した場合のみ付与する
* キャンセルした行動にはEXP / JobEXPを付与しない
* Victory後のGrowthResultPanelは簡易UIでよい
* 既存のAP表記を崩さない
* 既存のPhase 8.5のFloatingNumberやThreatArrowを壊さない

---

# 33. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* BattleUnitに追加した成長項目
* ExperienceSystemの仕様
* EXP獲得ルール
* レベルアップ処理
* ステータス成長仕様
* JobDataの仕様
* JobDatabaseの仕様
* JobSystemの仕様
* JobEXP獲得ルール
* JobLevelUp処理
* スキル習得処理
* guard_stanceの仕様
* GrowthResultPanelの表示内容
* UnitInfoPanelの追加表示
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**経験値・レベルアップ・ジョブ成長・スキル習得の基礎システム**を追加してください。

具体的には以下を実装してください。

* BattleUnitに level / exp / job_level / job_exp を追加
* ExperienceSystem を追加
* 攻撃・撃破・回復によるEXP獲得を実装
* EXPが一定値に達したらレベルアップ
* レベルアップ時にステータス上昇
* JobData / JobDatabase を追加
* JobSystem を追加
* 行動によるJobEXP獲得を実装
* JobEXPが一定値に達したらJobLevelUp
* JobLevel条件に応じてスキル習得
* guard_stance を新規スキルとして追加
* UnitInfoPanelにLv / EXP / JobLv / JobEXPを表示
* BattleLog / BattleMessageに成長ログを表示
* Victory後にGrowthResultPanelで成長結果を表示

ジョブチェンジ・装備・アイテム・セーブロードはまだ不要です。
まずは、戦闘中の行動がユニット成長につながる基礎を完成させてください。
