# Godot SRPGプロトタイプ Phase 11.5 開発指示書

## 目的

Phase 11.5では、既存のSRPG戦闘システムに対して、
新しく作成した **ジョブ設計** と **ステータス / Build値仕様** を反映する。

今回の目的は、単にジョブ名を増やすことではなく、
キャラクターの基礎ステータス、ジョブ補正、Build値、戦闘計算を整理し、
今後の装備・パッシブスキル・バフデバフ・ジョブチェンジ・上位ジョブ解放に耐えられる設計へ移行することである。

Phase 11までで以下は実装済み。

* 通常攻撃
* スキル
* AP
* 属性
* メインジョブ / サブジョブ
* ジョブレベル
* ジョブEXP
* セットスキル
* スキル解放
* 経験値
* レベルアップ
* セーブ / ロード
* ユニット永続データ
* 戦闘前セットアップ

Phase 11.5では、これらの上に以下を追加・整理する。

* 下位ジョブ / 上位ジョブ / 最上位ジョブの定義
* ジョブランク
* ジョブ解放条件
* 基礎ステータス
* Build値
* ステータス計算順
* ジョブ補正
* 属性耐性
* 物理 / 魔法 / 回復 / 地形スキルの計算整理
* 命中率 / 会心率 / 回避率の再計算
* 既存の攻撃・スキル計算をBuild値参照へ移行

---

# 今回の実装方針

今回のPhase 11.5では、以下を優先する。

```text
1. データ構造を整える
2. 既存戦闘が壊れないようにBuild値へ移行する
3. ジョブ補正を反映する
4. 計算式をStatusCalculatorへ集約する
5. 上位ジョブ・最上位ジョブはデータ定義まで行う
6. 実際のジョブチェンジUIはまだ最小限でよい
```

以下はまだ本格実装しない。

```text
- 装備システム
- パッシブスキルシステム
- バフ / デバフの本格管理
- CT行動順への完全移行
- 状態異常の本格実装
- ジョブツリー画面
- 最上位ジョブへの転職UI
```

ただし、後から実装できるようにデータ構造だけは考慮する。

---

# 1. ジョブ体系を実装する

## 1.1 下位ジョブ

以下の8種を下位ジョブとして登録する。

```text
格闘師
剣術師
槍術師
斧術師
弓術師
双剣師
治癒師
魔術師
```

内部ID例:

```text
fighter
swordsman
lancer
axeman
archer
dual_blader
healer
mage
```

---

## 1.2 上位ジョブ

以下の8種を上位ジョブとして登録する。

```text
モンク
聖騎士
竜騎士
重騎士
スナイパー
忍者
プリースト
ソーサラー
```

内部ID例:

```text
monk
holy_knight
dragoon
heavy_knight
sniper
ninja
priest
sorcerer
```

下位ジョブとの対応:

```text
格闘師   -> モンク
剣術師   -> 聖騎士
槍術師   -> 竜騎士
斧術師   -> 重騎士
弓術師   -> スナイパー
双剣師   -> 忍者
治癒師   -> プリースト
魔術師   -> ソーサラー
```

---

## 1.3 最上位ジョブ

以下の12種を最上位ジョブとして登録する。

```text
剣聖
パラディン
魔法剣士
フォートレスナイト
槍聖
ガンスリンガー
武神
拳聖
アサシン
アルケミスト
学者
ネクロマンサー
```

内部ID例:

```text
sword_saint
paladin
magic_swordsman
fortress_knight
spear_saint
gunslinger
war_god
fist_saint
assassin
alchemist
scholar
necromancer
```

---

# 2. ジョブランクを追加する

`JobData.gd` にジョブランクを追加する。

```gdscript
enum JobRank {
    BASIC,
    ADVANCED,
    MASTER
}

@export var job_rank: JobRank = JobRank.BASIC
```

意味:

```text
BASIC:
  下位ジョブ

ADVANCED:
  上位ジョブ

MASTER:
  最上位ジョブ
```

---

# 3. ジョブ解放条件を追加する

`JobData.gd` に解放条件を追加する。

```gdscript
@export var required_jobs: Array[String] = []
@export var required_job_levels: Dictionary = {}
```

例:

```gdscript
# 聖騎士
required_jobs = ["swordsman"]
required_job_levels = {
    "swordsman": 5
}
```

最上位ジョブの場合:

```gdscript
# 剣聖
required_jobs = ["holy_knight", "heavy_knight"]
required_job_levels = {
    "holy_knight": 5,
    "heavy_knight": 5
}
```

Phase 11.5では、必要レベルは仮でよい。

推奨:

```text
上位ジョブ解放:
  対応する下位ジョブLv5

最上位ジョブ解放:
  必要上位ジョブ2つがLv5
```

---

# 4. JobUnlockSystem を追加する

ジョブ解放判定を管理する。

追加ファイル:

```text
res://scripts/job/JobUnlockSystem.gd
```

責務:

```text
- ユニットがジョブを解放済みか判定する
- ジョブ解放条件を満たしているか判定する
- 条件を満たしたジョブを unlocked_job_ids に追加する
- PreBattleSetupPanelで選択可能なジョブ一覧を返す
```

想定メソッド:

```gdscript
func can_unlock_job(unit: BattleUnit, job_id: String) -> bool:
    var job = job_database.get_job(job_id)
    if job == null:
        return false

    for required_job_id in job.required_jobs:
        var required_level = int(job.required_job_levels.get(required_job_id, 1))
        if unit.get_job_level(required_job_id) < required_level:
            return false

    return true

func unlock_available_jobs(unit: BattleUnit) -> Array[String]:
    var unlocked: Array[String] = []

    for job_id in job_database.get_all_job_ids():
        if unit.unlocked_job_ids.has(job_id):
            continue

        if can_unlock_job(unit, job_id):
            unit.unlocked_job_ids.append(job_id)
            unlocked.append(job_id)

    return unlocked

func get_selectable_jobs(unit: BattleUnit) -> Array[String]:
    return unit.unlocked_job_ids
```

---

# 5. 基礎ステータスを正式化する

`BattleUnit.gd` に以下の基礎ステータスを正式に持たせる。

```gdscript
var base_str: int = 10
var base_dex: int = 10
var base_vit: int = 10
var base_mnd: int = 10
var base_int: int = 10
var base_agi: int = 10
```

既存に以下がある場合:

```gdscript
strength
dexterity
vitality
mind
intelligence
agility
```

以下のどちらかに統一する。

## 推奨

内部名は短く統一する。

```gdscript
base_str
base_dex
base_vit
base_mnd
base_int
base_agi
```

ただし、既存コードを壊さないため、移行用メソッドを用意してもよい。

---

# 6. Build値を追加する

戦闘中に参照する最終評価値として、Build値を導入する。

`BattleUnit.gd` に直接持たせるか、`BuildStats` として分離する。

推奨は `BuildStats.gd` を追加する。

追加ファイル:

```text
res://scripts/status/BuildStats.gd
```

内容例:

```gdscript
class_name BuildStats
extends Resource

var attack_power: int = 0
var magic_attack_power: int = 0
var defense: int = 0
var magic_defense: int = 0
var speed: int = 0
var move_range: int = 0
var jump_height: int = 0
var accuracy: int = 0
var critical_rate: int = 0
var evasion: int = 0
var status_resistance: int = 0

var elemental_resistances: Dictionary = {}
```

属性耐性:

```gdscript
elemental_resistances = {
    "fire": 0,
    "earth": 0,
    "water": 0,
    "thunder": 0,
    "wind": 0,
    "ice": 0,
    "dark": 0,
    "light": 0
}
```

---

# 7. StatusCalculator を追加する

基礎ステータスからBuild値を算出する処理を集約する。

追加ファイル:

```text
res://scripts/status/StatusCalculator.gd
```

責務:

```text
- 最終基礎ステータスを計算する
- ジョブ補正を加算する
- 装備補正用の入口を用意する
- パッシブ補正用の入口を用意する
- バフ / デバフ補正用の入口を用意する
- Build値を算出する
```

想定メソッド:

```gdscript
func calculate_final_base_stats(unit: BattleUnit) -> Dictionary:
    # base + job + equipment + passive + buff/debuff

func calculate_build_stats(unit: BattleUnit) -> BuildStats:
    var final_stats = calculate_final_base_stats(unit)
    var build = BuildStats.new()

    build.attack_power = calculate_attack_power(final_stats)
    build.magic_attack_power = calculate_magic_attack_power(final_stats)
    build.defense = calculate_defense(final_stats)
    build.magic_defense = calculate_magic_defense(final_stats)
    build.speed = calculate_speed(final_stats)
    build.move_range = calculate_move_range(unit, final_stats)
    build.jump_height = calculate_jump_height(unit, final_stats)
    build.accuracy = calculate_accuracy(final_stats)
    build.critical_rate = calculate_critical_rate(final_stats)
    build.evasion = calculate_evasion(final_stats)
    build.status_resistance = calculate_status_resistance(final_stats)
    build.elemental_resistances = calculate_elemental_resistances(unit, final_stats)

    return build
```

---

# 8. ステータス計算順

計算順は以下にする。

```text
1. キャラクター基礎値を取得
2. メインジョブ補正を加算
3. サブジョブ補正を加算
4. 装備補正を加算
5. パッシブスキル補正を加算
6. バフ・デバフ補正を加算
7. 最終ステータスを算出
8. 最終ステータスからBuild値を算出
```

Phase 11.5では、装備・パッシブ・バフデバフは未実装でもよい。
ただし、空の補正として入口を用意する。

```gdscript
func get_equipment_bonus(unit: BattleUnit) -> Dictionary:
    return {}

func get_passive_bonus(unit: BattleUnit) -> Dictionary:
    return {}

func get_buff_debuff_bonus(unit: BattleUnit) -> Dictionary:
    return {}
```

---

# 9. ジョブ補正をJobDataに追加する

`JobData.gd` に基礎ステータス補正を追加する。

```gdscript
@export var stat_bonus: Dictionary = {
    "str": 0,
    "dex": 0,
    "vit": 0,
    "mnd": 0,
    "int": 0,
    "agi": 0
}

@export var hp_bonus: int = 0
@export var base_move_range: int = 4
@export var base_jump_height: int = 1
@export var speed_modifier: float = 1.0
```

---

# 10. メインジョブ / サブジョブ補正

補正の扱いは以下とする。

```text
メインジョブ補正:
  100%反映

サブジョブ補正:
  50%反映
```

例:

```text
メインジョブ stat_bonus STR +6
サブジョブ stat_bonus DEX +4

最終補正:
  STR +6
  DEX +2
```

実装例:

```gdscript
func apply_job_bonus(stats: Dictionary, unit: BattleUnit) -> Dictionary:
    var main_job = job_database.get_job(unit.main_job_id)
    if main_job != null:
        stats = add_stat_bonus(stats, main_job.stat_bonus, 1.0)

    var sub_job = job_database.get_job(unit.sub_job_id)
    if sub_job != null and unit.sub_job_id != unit.main_job_id:
        stats = add_stat_bonus(stats, sub_job.stat_bonus, 0.5)

    return stats
```

---

# 11. 各ジョブのステータス補正を登録する

添付のジョブ傾向に基づき、まずは仮数値で登録する。

## 下位ジョブ

```text
格闘師:
  STR +4
  DEX +2
  VIT +3
  MND +0
  INT +0
  AGI +2

剣術師:
  STR +3
  DEX +2
  VIT +2
  MND +2
  INT +0
  AGI +2

槍術師:
  STR +3
  DEX +2
  VIT +2
  MND -1
  INT +0
  AGI +4

斧術師:
  STR +6
  DEX -1
  VIT +4
  MND +0
  INT -1
  AGI -2

弓術師:
  STR +2
  DEX +5
  VIT -1
  MND +0
  INT +0
  AGI +3

双剣師:
  STR +2
  DEX +4
  VIT -2
  MND +0
  INT +0
  AGI +6

治癒師:
  STR -1
  DEX +0
  VIT -1
  MND +5
  INT +2
  AGI -1

魔術師:
  STR -2
  DEX +0
  VIT -2
  MND +2
  INT +6
  AGI -1
```

---

## 上位ジョブ

```text
モンク:
  STR +7
  DEX +3
  VIT +5
  MND +1
  INT +0
  AGI +3

聖騎士:
  STR +5
  DEX +3
  VIT +5
  MND +4
  INT +1
  AGI +2

竜騎士:
  STR +5
  DEX +3
  VIT +4
  MND -1
  INT +0
  AGI +6

重騎士:
  STR +7
  DEX -1
  VIT +8
  MND +1
  INT -1
  AGI -2

スナイパー:
  STR +3
  DEX +8
  VIT +0
  MND +1
  INT +0
  AGI +4

忍者:
  STR +3
  DEX +6
  VIT -1
  MND +1
  INT +1
  AGI +8

プリースト:
  STR +0
  DEX +1
  VIT +0
  MND +8
  INT +3
  AGI +0

ソーサラー:
  STR -2
  DEX +1
  VIT -1
  MND +4
  INT +9
  AGI +0
```

---

## 最上位ジョブ

最上位ジョブはPhase 11.5ではデータ登録まで行う。

実際の転職UI・解放演出は後のPhaseでよい。

```text
剣聖:
  STR +10
  DEX +7
  VIT +8
  MND +3
  INT +0
  AGI +5

パラディン:
  STR +5
  DEX +3
  VIT +8
  MND +10
  INT +4
  AGI +1

魔法剣士:
  STR +7
  DEX +4
  VIT +5
  MND +6
  INT +7
  AGI +4

フォートレスナイト:
  STR +7
  DEX +3
  VIT +11
  MND +4
  INT +0
  AGI +3

槍聖:
  STR +7
  DEX +9
  VIT +5
  MND +3
  INT +0
  AGI +10

ガンスリンガー:
  STR +1
  DEX +11
  VIT +3
  MND +3
  INT +6
  AGI +7

武神:
  STR +11
  DEX +6
  VIT +10
  MND +3
  INT +0
  AGI +4

拳聖:
  STR +8
  DEX +9
  VIT +5
  MND +3
  INT +0
  AGI +11

アサシン:
  STR +4
  DEX +10
  VIT -1
  MND +0
  INT +3
  AGI +11

アルケミスト:
  STR +0
  DEX +7
  VIT +4
  MND +7
  INT +7
  AGI +4

学者:
  STR -1
  DEX +3
  VIT +3
  MND +11
  INT +11
  AGI +0

ネクロマンサー:
  STR -2
  DEX +6
  VIT -1
  MND +7
  INT +11
  AGI +7
```

---

# 12. Build値の計算式

`StatusCalculator.gd` に以下の計算式を実装する。

## 攻撃力

```text
攻撃力 = 最終STR
```

```gdscript
func calculate_attack_power(stats: Dictionary) -> int:
    return int(stats.get("str", 0))
```

---

## 魔法攻撃力

```text
魔法攻撃力 = 最終INT
```

```gdscript
func calculate_magic_attack_power(stats: Dictionary) -> int:
    return int(stats.get("int", 0))
```

---

## 防御力

```text
防御力 = 最終VIT
```

```gdscript
func calculate_defense(stats: Dictionary) -> int:
    return int(stats.get("vit", 0))
```

---

## 魔法防御力

```text
魔法防御力 = 最終MND
```

```gdscript
func calculate_magic_defense(stats: Dictionary) -> int:
    return int(stats.get("mnd", 0))
```

---

## 素早さ

```text
素早さ = 最終AGI
```

```gdscript
func calculate_speed(stats: Dictionary) -> int:
    return int(stats.get("agi", 0))
```

---

## 移動量

```text
移動量 = 基本移動量 + floor(最終AGI / 20)
```

```gdscript
func calculate_move_range(unit: BattleUnit, stats: Dictionary) -> int:
    var base_move = get_base_move_range(unit)
    return base_move + floori(int(stats.get("agi", 0)) / 20)
```

---

## 跳躍量

```text
跳躍量 = 基本跳躍量 + floor(最終AGI / 30)
```

```gdscript
func calculate_jump_height(unit: BattleUnit, stats: Dictionary) -> int:
    var base_jump = get_base_jump_height(unit)
    return base_jump + floori(int(stats.get("agi", 0)) / 30)
```

---

## 命中率

```text
命中率 = 基本命中率 + floor(最終DEX / 2)
```

```gdscript
func calculate_accuracy(stats: Dictionary) -> int:
    var base_accuracy = 70
    return base_accuracy + floori(int(stats.get("dex", 0)) / 2)
```

---

## 会心率

```text
会心率 = 基本会心率 + floor(最終DEX / 5)
```

```gdscript
func calculate_critical_rate(stats: Dictionary) -> int:
    var base_critical = 5
    return base_critical + floori(int(stats.get("dex", 0)) / 5)
```

---

## 回避率

```text
回避率 = 基本回避率 + floor(最終AGI / 3) + floor(最終DEX / 10)
```

```gdscript
func calculate_evasion(stats: Dictionary) -> int:
    var base_evasion = 5
    var agi = int(stats.get("agi", 0))
    var dex = int(stats.get("dex", 0))
    return min(60, base_evasion + floori(agi / 3) + floori(dex / 10))
```

---

## 状態異常耐性

```text
状態異常耐性 = 基本耐性 + floor(最終MND / 2)
```

```gdscript
func calculate_status_resistance(stats: Dictionary) -> int:
    var base_resistance = 0
    return base_resistance + floori(int(stats.get("mnd", 0)) / 2)
```

---

## 最大HP

```text
最大HP = 基本HP + floor(最終VIT × 5) + ジョブHP補正
```

```gdscript
func calculate_max_hp(unit: BattleUnit, stats: Dictionary) -> int:
    var base_hp = 100
    var vit = int(stats.get("vit", 0))
    var job_hp_bonus = get_job_hp_bonus(unit)
    return base_hp + floori(vit * 5) + job_hp_bonus
```

---

# 13. BattleUnitにBuildStatsを反映する

`BattleUnit.gd` に以下を追加する。

```gdscript
var build_stats: BuildStats
```

更新メソッド:

```gdscript
func refresh_build_stats(status_calculator: StatusCalculator) -> void:
    build_stats = status_calculator.calculate_build_stats(self)

    max_hp = status_calculator.calculate_max_hp(self, status_calculator.calculate_final_base_stats(self))

    attack_power = build_stats.attack_power
    defense = build_stats.defense
    accuracy = build_stats.accuracy
    evasion = build_stats.evasion
    move_range = build_stats.move_range
    jump_height = build_stats.jump_height
```

既存の処理が `attack_power` や `defense` を直接見ている場合は、
互換性のため当面これらの値にもBuild値を同期する。

---

# 14. 攻撃計算をBuild値参照へ変更する

`AttackSystem.gd` の通常攻撃計算を修正する。

変更前の想定:

```text
damage = attacker.attack_power - target.defense
```

変更後:

```text
物理ダメージ = max(1, 攻撃力 + スキル威力 - 防御力)
```

通常攻撃の場合、スキル威力は0として扱う。

```gdscript
func calculate_physical_damage(attacker: BattleUnit, target: BattleUnit, skill_power: int = 0) -> int:
    var atk = attacker.build_stats.attack_power
    var def = target.build_stats.defense
    return max(1, atk + skill_power - def)
```

---

# 15. 魔法ダメージ計算を追加する

`SkillSystem.gd` で魔法攻撃スキルを扱えるようにする。

```gdscript
func calculate_magic_damage(user: BattleUnit, target: BattleUnit, skill: SkillData) -> int:
    var matk = user.build_stats.magic_attack_power
    var mdef = target.build_stats.magic_defense
    var base_damage = max(1, matk + skill.power - mdef)

    var element_multiplier = element_system.get_element_damage_multiplier(skill.element, target.element)
    return max(1, int(base_damage * element_multiplier))
```

---

# 16. SkillDataに参照タイプを追加する

スキルが物理か魔法か回復かを明確にする。

`SkillData.gd` に追加。

```gdscript
enum ScalingType {
    PHYSICAL,
    MAGICAL,
    HEALING,
    FIXED,
    TERRAIN
}

@export var scaling_type: ScalingType = ScalingType.PHYSICAL
```

意味:

```text
PHYSICAL:
  攻撃力 / 防御力を参照

MAGICAL:
  魔法攻撃力 / 魔法防御力を参照

HEALING:
  MNDとスキル回復力を参照

FIXED:
  固定値

TERRAIN:
  地形変化・地形ダメージ用
```

---

# 17. 回復量計算をBuild値へ対応する

回復量はMNDを主軸にする。

```text
回復量 = スキル回復力 + floor(最終MND × 1.5)
```

```gdscript
func calculate_heal_amount(user: BattleUnit, skill: SkillData) -> int:
    var final_stats = status_calculator.calculate_final_base_stats(user)
    var mnd = int(final_stats.get("mnd", 0))
    return skill.power + floori(mnd * 1.5)
```

---

# 18. 命中判定をBuild値へ対応する

命中判定は以下に変更する。

```text
最終命中率 = 攻撃側命中率 - 防御側回避率 + スキル命中補正 + 地形補正 + 高低差補正
```

下限・上限:

```text
最終命中率下限 = 5%
最終命中率上限 = 95%
```

実装例:

```gdscript
func calculate_hit_rate(attacker: BattleUnit, target: BattleUnit, skill_accuracy_modifier: int = 0) -> int:
    var hit = attacker.build_stats.accuracy
    var evade = target.build_stats.evasion

    var terrain_modifier = get_terrain_hit_modifier(attacker, target)
    var height_modifier = get_height_hit_modifier(attacker, target)

    var final_hit = hit - evade + skill_accuracy_modifier + terrain_modifier + height_modifier

    return clampi(final_hit, 5, 95)
```

---

# 19. 会心判定を追加する

Phase 11.5では、通常攻撃と物理スキルに会心判定を追加する。

```text
会心判定は攻撃が命中した後に行う
```

計算式:

```text
最終会心率 = 会心率 + 武器会心補正 + スキル会心補正 - 対象会心耐性
```

Phase 11.5では、武器会心補正と対象会心耐性は0でよい。

`SkillData.gd` に追加:

```gdscript
@export var critical_modifier: int = 0
```

`AttackSystem.gd` に追加:

```gdscript
func calculate_critical_rate(attacker: BattleUnit, target: BattleUnit, skill: SkillData = null) -> int:
    var rate = attacker.build_stats.critical_rate

    if skill != null:
        rate += skill.critical_modifier

    return clampi(rate, 0, 50)
```

会心時:

```text
会心ダメージ = 通常ダメージ × 1.5
```

結果Dictionaryには以下を含める。

```gdscript
{
    "critical": true
}
```

FloatingNumberやBattleLogでもCriticalが分かるようにする。

---

# 20. SkillDatabaseの既存スキルを更新する

既存スキルに `scaling_type` を設定する。

例:

```text
power_slash:
  scaling_type = PHYSICAL

earth_break:
  scaling_type = MAGICAL

aqua_edge:
  scaling_type = MAGICAL

healing_water:
  scaling_type = HEALING

aimed_shot:
  scaling_type = PHYSICAL

piercing_arrow:
  scaling_type = PHYSICAL

heavy_attack:
  scaling_type = PHYSICAL

guard_stance:
  scaling_type = FIXED
```

---

# 21. 属性耐性を導入する

`BuildStats` に属性耐性を持たせる。

```gdscript
var elemental_resistances: Dictionary = {
    "fire": 0,
    "earth": 0,
    "water": 0,
    "thunder": 0,
    "wind": 0,
    "ice": 0,
    "dark": 0,
    "light": 0
}
```

耐性値は -100〜100 の範囲とする。

```text
+20:
  20%軽減

-20:
  20%増加
```

計算式:

```text
属性補正後ダメージ = ダメージ × (1.0 - 耐性値 / 100.0)
```

例:

```text
火耐性 +20:
  火ダメージ 20%軽減

火耐性 -20:
  火ダメージ 20%増加
```

---

# 22. ElementSystemを耐性対応に更新する

既存の属性相性に加えて、対象の属性耐性を反映する。

```gdscript
func apply_element_modifiers(
    base_damage: int,
    attack_element: BattleUnit.ElementType,
    target: BattleUnit
) -> int:
    var affinity_multiplier = get_element_damage_multiplier(attack_element, target.element)

    var resistance = get_target_resistance(target, attack_element)
    var resistance_multiplier = 1.0 - float(resistance) / 100.0

    return max(1, int(base_damage * affinity_multiplier * resistance_multiplier))
```

---

# 23. UnitInfoPanelにステータス表示を追加する

`UnitInfoPanel` に以下を表示する。

```text
Vain
Lv: 3
HP: 270 / 270
AP: 32 / 32

Main Job: 剣術師 Lv 3
Sub Job: 弓術師

STR: 30
DEX: 24
VIT: 28
MND: 18
INT: 12
AGI: 22

ATK: 30
MATK: 12
DEF: 28
MDEF: 18
ACC: 82
CRIT: 9%
EVA: 14%
MOVE: 5
JUMP: 1
```

Phase 11.5では簡易表示でよい。

---

# 24. PreBattleSetupPanelにジョブ補正プレビューを追加する

メインジョブやサブジョブを変更したとき、
最終ステータスとBuild値の変化が分かるようにする。

表示例:

```text
STR 30 -> 34
DEX 24 -> 25
VIT 28 -> 31

ATK 30 -> 34
DEF 28 -> 31
MOVE 5 -> 5
```

Phase 11.5では、数値プレビューが難しければ、
選択中ジョブの補正一覧を表示するだけでもよい。

---

# 25. セーブデータへの反映

Phase 11で実装したセーブデータに以下を含める。

```text
base_str
base_dex
base_vit
base_mnd
base_int
base_agi
```

既存の以下も維持する。

```text
level
exp
main_job_id
sub_job_id
job_levels
job_exps
equipped_skill_ids
unlocked_job_ids
```

Build値は保存しない。

Build値はロード後に再計算する。

```text
保存する:
  基礎ステータス

保存しない:
  Build値
```

---

# 26. Build値の再計算タイミング

以下のタイミングで `refresh_build_stats()` を呼ぶ。

```text
- ユニット生成時
- セーブデータロード後
- メインジョブ変更時
- サブジョブ変更時
- レベルアップ時
- ジョブレベルアップ時
- バフ / デバフ付与時
- バフ / デバフ解除時
- 装備変更時
- 戦闘開始前
```

Phase 11.5では、装備・バフデバフは未実装でもよい。

---

# 27. 既存のステータス互換対応

既存コードが以下を直接参照している場合がある。

```text
attack_power
defense
accuracy
evasion
move_range
jump_height
```

これらは当面残す。

ただし、中身はBuild値から同期する。

```gdscript
attack_power = build_stats.attack_power
defense = build_stats.defense
accuracy = build_stats.accuracy
evasion = build_stats.evasion
move_range = build_stats.move_range
jump_height = build_stats.jump_height
```

将来的には直接参照を減らし、`build_stats` を参照する。

---

# 28. CT・行動順について

添付仕様では、素早さからCT蓄積速度を決める案がある。

ただしPhase 11.5では、既存のターン制を壊さないため、
CT制への完全移行は行わない。

今回は以下のみ実装する。

```text
- Build値に speed を追加
- speed = 最終AGI
- UIに表示する
- 将来のCT制に備える
```

CT行動順への移行は別Phaseで行う。

---

# 29. 状態異常耐性について

Phase 11.5では、Build値として `status_resistance` を計算する。

ただし、状態異常の本格処理はまだ不要。

今回は以下だけ行う。

```text
- MNDから状態異常耐性を算出する
- UnitInfoPanelに表示する
- 将来の状態異常成功率計算に使えるようにする
```

---

# 30. 地形補正との連動

既存の地形補正は維持する。

今後、以下のようにBuild値と組み合わせる。

```text
物理ダメージ:
  Build防御力 + 地形防御補正

魔法ダメージ:
  Build魔法防御力 + 地形魔法補正

命中:
  Build命中率 - Build回避率 + 地形補正 + 高低差補正
```

Phase 11.5では、既存地形補正を大きく変更しない。

ただし、計算式がStatusCalculator / AttackSystem / SkillSystem に分かれて整理されている状態にする。

---

# 31. 新規追加ファイル

以下を追加する。

```text
res://scripts/status/BuildStats.gd
res://scripts/status/StatusCalculator.gd
res://scripts/job/JobUnlockSystem.gd
```

必要に応じて以下も追加する。

```text
res://scripts/status/FinalBaseStats.gd
```

---

# 32. 既存ファイルの主な変更対象

以下を修正する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/job/JobData.gd
res://scripts/job/JobDatabase.gd
res://scripts/job/JobSystem.gd
res://scripts/skill/SkillData.gd
res://scripts/skill/SkillDatabase.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/SkillSystem.gd
res://scripts/battle/ElementSystem.gd
res://scripts/battle/ExperienceSystem.gd
res://scripts/save/UnitProgressManager.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/PreBattleSetupPanel.gd
res://scripts/ui/CombatConfirmPanel.gd
res://scripts/ui/SkillConfirmPanel.gd
res://scripts/Main.gd
```

---

# 33. 推奨ノード構成

`Main.tscn` を以下のように拡張する。

```text
Main.tscn
├── SaveManager
├── PlayerProfileData
├── UnitProgressManager
├── StageProgressManager
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
├── StatusCalculator
├── JobSystem
├── JobDatabase
├── JobUnlockSystem
├── SkillUnlockSystem
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
    ├── PreBattleSetupPanel
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

# 34. 完了条件

以下がすべて動作すれば完了。

1. 下位ジョブ8種がJobDatabaseに登録されている
2. 上位ジョブ8種がJobDatabaseに登録されている
3. 最上位ジョブ12種がJobDatabaseに登録されている
4. JobDataにJobRankがある
5. JobDataに解放条件がある
6. JobUnlockSystemでジョブ解放判定ができる
7. BattleUnitが基礎ステータス STR / DEX / VIT / MND / INT / AGI を持つ
8. BuildStatsが存在する
9. StatusCalculatorが存在する
10. 基礎ステータスからBuild値が算出される
11. メインジョブ補正がBuild値に反映される
12. サブジョブ補正が50%でBuild値に反映される
13. 攻撃力がSTRから算出される
14. 魔法攻撃力がINTから算出される
15. 防御力がVITから算出される
16. 魔法防御力がMNDから算出される
17. 命中率がDEXから算出される
18. 会心率がDEXから算出される
19. 回避率がAGIとDEXから算出される
20. 移動量がAGIから段階的に算出される
21. 跳躍量がAGIから段階的に算出される
22. 最大HPがVITから算出される
23. 通常攻撃がBuild値を参照している
24. 物理スキルがBuild値を参照している
25. 魔法スキルがBuild値を参照している
26. 回復スキルがMNDを参照している
27. 命中判定がBuild命中率とBuild回避率を参照している
28. 会心判定が実装されている
29. 属性耐性がBuildStatsに存在する
30. UnitInfoPanelに基礎ステータスとBuild値が表示される
31. PreBattleSetupPanelでジョブ変更時の補正が確認できる
32. セーブデータに基礎ステータスが保存される
33. Build値は保存せず、ロード後に再計算される
34. 既存の戦闘、スキル、AP、成長、セーブ/ロードが壊れていない

---

# 35. 今回は実装しないもの

以下はPhase 11.5では実装しない。

```text
- 装備システム
- パッシブスキルの本格実装
- バフ / デバフの本格実装
- 状態異常の本格実装
- CT制への完全移行
- ジョブツリーUI
- 最上位ジョブへの転職演出
- 武器種ごとの攻撃力計算の完全実装
- 地形コンボ
- 属性地形変化
- スキルツリー
- 装備補正の保存
```

ただし、将来実装できるように、計算入口だけは用意する。

---

# 36. 実装時の注意

```text
- 既存戦闘を壊さないことを最優先にする
- 既存の attack_power / defense / accuracy / evasion は当面残す
- ただし中身はBuild値と同期する
- Build値は保存しない
- Build値は毎回再計算する
- メインジョブ補正は100%
- サブジョブ補正は50%
- 最上位ジョブはデータ登録まででよい
- CT制はまだ導入しない
- 状態異常はまだ本格実装しない
- 会心は通常攻撃と物理スキルだけでよい
- 魔法スキルはINT / MNDで計算する
- 回復スキルはMNDで計算する
- セーブデータには基礎ステータスを保存する
- ロード後に必ず refresh_build_stats() を呼ぶ
```

---

# 37. 実装後に提示してほしい内容

実装後、以下を説明してください。

```text
- 追加・変更したファイル一覧
- 追加したノード構成
- JobDataの拡張内容
- JobDatabaseに登録したジョブ一覧
- JobUnlockSystemの仕様
- BattleUnitに追加した基礎ステータス
- BuildStatsの仕様
- StatusCalculatorの仕様
- ステータス計算順
- メインジョブ補正 / サブジョブ補正の仕様
- Build値の計算式
- 通常攻撃計算の変更点
- 物理スキル計算の変更点
- 魔法スキル計算の変更点
- 回復スキル計算の変更点
- 命中判定の変更点
- 会心判定の仕様
- 属性耐性の仕様
- UnitInfoPanelの表示変更
- PreBattleSetupPanelの表示変更
- セーブデータ変更点
- 動作確認手順
- 現時点の制限事項
- 次に実装しやすい項目
```

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**ジョブ体系・基礎ステータス・Build値・ステータス計算式** を反映してください。

具体的には以下を実装してください。

```text
- 下位ジョブ8種を登録
- 上位ジョブ8種を登録
- 最上位ジョブ12種を登録
- JobDataにJobRankを追加
- JobDataにジョブ解放条件を追加
- JobUnlockSystemを追加
- BattleUnitにSTR / DEX / VIT / MND / INT / AGIを追加
- BuildStatsを追加
- StatusCalculatorを追加
- メインジョブ補正100%、サブジョブ補正50%で最終ステータスを計算
- 最終ステータスからBuild値を算出
- 通常攻撃・物理スキル・魔法スキル・回復スキルをBuild値参照に変更
- 命中率・会心率・回避率をBuild値から算出
- 会心判定を追加
- 属性耐性をBuildStatsに追加
- UnitInfoPanelに基礎ステータスとBuild値を表示
- PreBattleSetupPanelでジョブ補正を確認できるようにする
- セーブデータに基礎ステータスを保存
- Build値は保存せずロード後に再計算
```

装備・パッシブ・バフデバフ・CT制・状態異常の本格実装はまだ不要です。
まずは、今後の成長・装備・スキル拡張の土台になる
**ステータス計算基盤** を完成させてください。
