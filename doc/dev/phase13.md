# Godot SRPGプロトタイプ Phase 13 開発指示書

## 目的

Phase 13では、既存のSRPG戦闘システムに対して、
**装備・武器種・武器攻撃力・装備補正システム** を追加する。

Phase 11.5では、基礎ステータスとBuild値を整理した。

Phase 12では、Build値の `speed` を使ってCT制の行動順を実装した。

Phase 13では、キャラクターの強さをジョブとステータスだけでなく、
**装備している武器・防具・アクセサリ** によって変化させる。

今回のゴールは以下。

```text
戦闘前セットアップで武器を装備する
↓
武器種によって参照ステータスが変わる
↓
剣はSTRとDEXを参照する
↓
弓はDEXとSTRを参照する
↓
杖はINTとMNDを参照する
↓
装備補正がBuild値に反映される
↓
通常攻撃と物理スキルの威力が武器によって変わる
↓
ジョブごとに装備可能武器が異なる
```

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 通常攻撃
* スキル
* AP
* 属性
* メインジョブ / サブジョブ
* ジョブレベル
* セットスキル
* 戦闘前セットアップ
* 経験値
* セーブ / ロード
* 基礎ステータス
* BuildStats
* StatusCalculator
* ジョブ補正
* CT制
* UnitInfoPanel
* PreBattleSetupPanel

---

# 今回の実装範囲

Phase 13では以下を実装する。

* EquipmentData
* WeaponData
* ArmorData
* AccessoryData
* EquipmentDatabase
* 装備スロット
* 装備可能武器種
* 武器種
* 武器攻撃力計算
* 装備ステータス補正
* 装備による属性耐性補正
* 戦闘前装備変更UI
* 通常攻撃の武器参照化
* 物理スキルの武器参照化
* セーブデータへの装備反映

ただし、今回は以下はまだ実装しない。

* アイテム所持数管理
* ショップ
* ドロップ
* 強化
* 鍛冶
* 耐久度
* レアリティ演出
* 装備スキル
* 武器固有アニメーション
* 本格的なインベントリUI

---

# 1. 武器種を定義する

`EquipmentData.gd` または `WeaponData.gd` に武器種Enumを定義する。

```gdscript
enum WeaponType {
    NONE,
    SWORD,
    AXE,
    SPEAR,
    BOW,
    DAGGER,
    DUAL_BLADE,
    STAFF,
    MACE,
    FIST
}
```

各武器種の方針は以下。

```text
SWORD:
  STR + DEX
  バランス型

AXE:
  STR
  高威力・低命中

SPEAR:
  STR + AGI
  射程・高低差に強い

BOW:
  DEX + STR
  高命中・高会心

DAGGER:
  DEX + AGI
  会心・状態異常向き

DUAL_BLADE:
  AGI + DEX
  手数・回避・会心向き

STAFF:
  INT + MND
  魔法攻撃・補助向き

MACE:
  STR + MND
  物理＋聖職者向き

FIST:
  STR + AGI
  格闘・連撃向き
```

---

# 2. 装備スロットを定義する

`BattleUnit.gd` に装備スロットを追加する。

```gdscript
var equipped_weapon_id: String = ""
var equipped_armor_id: String = ""
var equipped_accessory_id: String = ""
```

将来的に複数アクセサリや盾を追加できるように、
今は最小構成にする。

Phase 13の装備スロット:

```text
Weapon:
  武器

Armor:
  防具

Accessory:
  アクセサリ
```

---

# 3. EquipmentDataを追加する

追加ファイル:

```text
res://scripts/equipment/EquipmentData.gd
```

共通装備データとして作成する。

```gdscript
class_name EquipmentData
extends Resource

enum EquipmentType {
    WEAPON,
    ARMOR,
    ACCESSORY
}

@export var equipment_id: String
@export var equipment_name: String
@export var description: String
@export var equipment_type: EquipmentType

@export var price: int = 0

@export var stat_bonus: Dictionary = {
    "str": 0,
    "dex": 0,
    "vit": 0,
    "mnd": 0,
    "int": 0,
    "agi": 0
}

@export var build_bonus: Dictionary = {
    "accuracy": 0,
    "critical_rate": 0,
    "evasion": 0,
    "move_range": 0,
    "jump_height": 0
}

@export var elemental_resistance_bonus: Dictionary = {
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

# 4. WeaponDataを追加する

追加ファイル:

```text
res://scripts/equipment/WeaponData.gd
```

```gdscript
class_name WeaponData
extends EquipmentData

@export var weapon_type: WeaponType = WeaponType.NONE

@export var weapon_power: int = 0
@export var weapon_accuracy_modifier: int = 0
@export var weapon_critical_modifier: int = 0

@export var min_range: int = 1
@export var max_range: int = 1

@export var attack_element: BattleUnit.ElementType = BattleUnit.ElementType.NONE
@export var requires_line_of_sight: bool = false
```

武器によって通常攻撃の射程も変える。

例:

```text
剣:
  range 1-1

槍:
  range 1-2

弓:
  range 2-4

杖:
  range 1-2

格闘:
  range 1-1
```

---

# 5. ArmorDataを追加する

追加ファイル:

```text
res://scripts/equipment/ArmorData.gd
```

```gdscript
class_name ArmorData
extends EquipmentData

@export var armor_category: String = "light"
```

カテゴリ例:

```text
light:
  軽装

medium:
  中装

heavy:
  重装

robe:
  ローブ
```

Phase 13ではカテゴリは表示用だけでよい。

---

# 6. AccessoryDataを追加する

追加ファイル:

```text
res://scripts/equipment/AccessoryData.gd
```

```gdscript
class_name AccessoryData
extends EquipmentData

@export var accessory_category: String = "general"
```

Phase 13では、アクセサリはステータス補正のみでよい。

---

# 7. EquipmentDatabaseを追加する

追加ファイル:

```text
res://scripts/equipment/EquipmentDatabase.gd
```

責務:

```text
- equipment_id から装備データを取得する
- weapon_id からWeaponDataを取得する
- 初期装備をコード上で登録する
- 装備種別ごとの一覧を返す
```

想定メソッド:

```gdscript
func get_equipment(equipment_id: String) -> EquipmentData:
    return equipments.get(equipment_id)

func get_weapon(weapon_id: String) -> WeaponData:
    var equipment = get_equipment(weapon_id)
    if equipment is WeaponData:
        return equipment
    return null

func get_all_weapons() -> Array[WeaponData]:
    var result: Array[WeaponData] = []
    for equipment in equipments.values():
        if equipment is WeaponData:
            result.append(equipment)
    return result
```

Phase 13では `.tres` ではなくコード登録でよい。

---

# 8. 初期武器データ

Phase 13では、まず以下の武器を登録する。

## iron_sword

```text
equipment_id: iron_sword
name: 鉄の剣
type: SWORD
weapon_power: 5
accuracy_modifier: 0
critical_modifier: 0
range: 1-1
stat_bonus:
  str +1
  dex +1
```

## iron_axe

```text
equipment_id: iron_axe
name: 鉄の斧
type: AXE
weapon_power: 8
accuracy_modifier: -10
critical_modifier: 0
range: 1-1
stat_bonus:
  str +2
  agi -1
```

## iron_spear

```text
equipment_id: iron_spear
name: 鉄の槍
type: SPEAR
weapon_power: 5
accuracy_modifier: 0
critical_modifier: 0
range: 1-2
stat_bonus:
  str +1
  agi +1
```

## short_bow

```text
equipment_id: short_bow
name: ショートボウ
type: BOW
weapon_power: 4
accuracy_modifier: 5
critical_modifier: 5
range: 2-4
requires_line_of_sight: true
stat_bonus:
  dex +2
```

## dagger

```text
equipment_id: dagger
name: ダガー
type: DAGGER
weapon_power: 3
accuracy_modifier: 5
critical_modifier: 10
range: 1-1
stat_bonus:
  dex +1
  agi +1
```

## twin_blades

```text
equipment_id: twin_blades
name: 双剣
type: DUAL_BLADE
weapon_power: 4
accuracy_modifier: 0
critical_modifier: 8
range: 1-1
stat_bonus:
  dex +1
  agi +2
```

## wooden_staff

```text
equipment_id: wooden_staff
name: 木の杖
type: STAFF
weapon_power: 3
accuracy_modifier: 0
critical_modifier: 0
range: 1-2
stat_bonus:
  int +2
  mnd +1
```

## iron_mace

```text
equipment_id: iron_mace
name: 鉄のメイス
type: MACE
weapon_power: 5
accuracy_modifier: -5
critical_modifier: 0
range: 1-1
stat_bonus:
  str +1
  mnd +1
```

## leather_glove

```text
equipment_id: leather_glove
name: レザーグローブ
type: FIST
weapon_power: 4
accuracy_modifier: 0
critical_modifier: 5
range: 1-1
stat_bonus:
  str +1
  agi +1
```

---

# 9. 初期防具データ

## leather_armor

```text
equipment_id: leather_armor
name: レザーアーマー
type: ARMOR
category: light
stat_bonus:
  vit +1
  agi +1
```

## chain_mail

```text
equipment_id: chain_mail
name: チェインメイル
type: ARMOR
category: medium
stat_bonus:
  vit +3
  agi -1
```

## plate_armor

```text
equipment_id: plate_armor
name: プレートアーマー
type: ARMOR
category: heavy
stat_bonus:
  vit +5
  agi -2
build_bonus:
  evasion -5
```

## mage_robe

```text
equipment_id: mage_robe
name: 魔術師のローブ
type: ARMOR
category: robe
stat_bonus:
  int +2
  mnd +2
  vit +1
```

---

# 10. 初期アクセサリデータ

## power_ring

```text
equipment_id: power_ring
name: 力の指輪
type: ACCESSORY
stat_bonus:
  str +2
```

## mind_charm

```text
equipment_id: mind_charm
name: 精神のお守り
type: ACCESSORY
stat_bonus:
  mnd +2
```

## speed_boots

```text
equipment_id: speed_boots
name: 俊足の靴
type: ACCESSORY
stat_bonus:
  agi +2
build_bonus:
  move_range +1
```

## accuracy_lens

```text
equipment_id: accuracy_lens
name: 精密レンズ
type: ACCESSORY
stat_bonus:
  dex +2
build_bonus:
  accuracy +5
```

---

# 11. ジョブごとの装備可能武器種

`JobData.gd` に装備可能武器種を追加する。

```gdscript
@export var allowed_weapon_types: Array[WeaponData.WeaponType] = []
```

設定例:

```text
格闘師:
  FIST

剣術師:
  SWORD

槍術師:
  SPEAR

斧術師:
  AXE

弓術師:
  BOW

双剣師:
  DAGGER
  DUAL_BLADE

治癒師:
  STAFF
  MACE

魔術師:
  STAFF
```

上位ジョブや最上位ジョブは複数武器を許可してよい。

例:

```text
聖騎士:
  SWORD
  MACE

竜騎士:
  SPEAR
  SWORD

重騎士:
  AXE
  SPEAR

スナイパー:
  BOW
  DAGGER

忍者:
  DAGGER
  DUAL_BLADE

プリースト:
  STAFF
  MACE

ソーサラー:
  STAFF

魔法剣士:
  SWORD
  STAFF
```

---

# 12. 装備可能判定

`EquipmentSystem.gd` を追加する。

追加ファイル:

```text
res://scripts/equipment/EquipmentSystem.gd
```

責務:

```text
- 指定ユニットが指定装備を装備できるか判定する
- 武器種がメインジョブまたはサブジョブで許可されているか確認する
- 装備を変更する
- 装備変更後にBuild値を再計算する
```

想定メソッド:

```gdscript
func can_equip(unit: BattleUnit, equipment: EquipmentData) -> bool:
    if equipment == null:
        return false

    if equipment.equipment_type == EquipmentData.EquipmentType.WEAPON:
        return can_equip_weapon(unit, equipment as WeaponData)

    return true

func can_equip_weapon(unit: BattleUnit, weapon: WeaponData) -> bool:
    var allowed_types = get_allowed_weapon_types(unit)
    return allowed_types.has(weapon.weapon_type)

func get_allowed_weapon_types(unit: BattleUnit) -> Array:
    var result = []

    var main_job = job_database.get_job(unit.main_job_id)
    if main_job != null:
        result.append_array(main_job.allowed_weapon_types)

    var sub_job = job_database.get_job(unit.sub_job_id)
    if sub_job != null:
        result.append_array(sub_job.allowed_weapon_types)

    return result

func equip_weapon(unit: BattleUnit, weapon_id: String) -> bool:
    var weapon = equipment_database.get_weapon(weapon_id)
    if weapon == null:
        return false

    if not can_equip_weapon(unit, weapon):
        return false

    unit.equipped_weapon_id = weapon_id
    unit.refresh_build_stats(status_calculator)
    return true
```

Phase 13では、防具・アクセサリは全ジョブ装備可能でよい。

---

# 13. 装備補正をStatusCalculatorへ反映する

Phase 11.5の計算順に、装備補正を正式に入れる。

計算順:

```text
1. キャラクター基礎値
2. メインジョブ補正
3. サブジョブ補正
4. 装備補正
5. パッシブ補正
6. バフ / デバフ補正
7. 最終基礎ステータス
8. Build値
```

`StatusCalculator.gd` の `get_equipment_bonus()` を実装する。

```gdscript
func get_equipment_bonus(unit: BattleUnit) -> Dictionary:
    var bonus = {
        "str": 0,
        "dex": 0,
        "vit": 0,
        "mnd": 0,
        "int": 0,
        "agi": 0
    }

    var equipment_ids = [
        unit.equipped_weapon_id,
        unit.equipped_armor_id,
        unit.equipped_accessory_id
    ]

    for equipment_id in equipment_ids:
        var equipment = equipment_database.get_equipment(equipment_id)
        if equipment == null:
            continue

        bonus = add_stat_bonus(bonus, equipment.stat_bonus, 1.0)

    return bonus
```

---

# 14. Build補正をStatusCalculatorへ反映する

装備には基礎ステータスではなく、Build値へ直接加算する補正もある。

例:

```text
accuracy +5
critical_rate +5
move_range +1
evasion -5
```

`StatusCalculator.gd` に追加する。

```gdscript
func apply_equipment_build_bonus(unit: BattleUnit, build: BuildStats) -> BuildStats:
    var equipment_ids = [
        unit.equipped_weapon_id,
        unit.equipped_armor_id,
        unit.equipped_accessory_id
    ]

    for equipment_id in equipment_ids:
        var equipment = equipment_database.get_equipment(equipment_id)
        if equipment == null:
            continue

        build.accuracy += int(equipment.build_bonus.get("accuracy", 0))
        build.critical_rate += int(equipment.build_bonus.get("critical_rate", 0))
        build.evasion += int(equipment.build_bonus.get("evasion", 0))
        build.move_range += int(equipment.build_bonus.get("move_range", 0))
        build.jump_height += int(equipment.build_bonus.get("jump_height", 0))

    build.evasion = clampi(build.evasion, 0, 60)
    build.critical_rate = clampi(build.critical_rate, 0, 50)

    return build
```

---

# 15. 属性耐性補正を装備から反映する

装備の `elemental_resistance_bonus` を `BuildStats.elemental_resistances` に加算する。

```gdscript
func apply_equipment_resistance_bonus(unit: BattleUnit, build: BuildStats) -> BuildStats:
    var equipment_ids = [
        unit.equipped_weapon_id,
        unit.equipped_armor_id,
        unit.equipped_accessory_id
    ]

    for equipment_id in equipment_ids:
        var equipment = equipment_database.get_equipment(equipment_id)
        if equipment == null:
            continue

        for element_key in equipment.elemental_resistance_bonus.keys():
            var current = int(build.elemental_resistances.get(element_key, 0))
            var add = int(equipment.elemental_resistance_bonus.get(element_key, 0))
            build.elemental_resistances[element_key] = clampi(current + add, -100, 100)

    return build
```

---

# 16. 武器攻撃力計算を追加する

`WeaponPowerCalculator.gd` を追加する。

追加ファイル:

```text
res://scripts/equipment/WeaponPowerCalculator.gd
```

責務:

```text
- 武器種ごとの参照ステータスで武器攻撃力を算出する
- 通常攻撃と物理スキルに渡す
```

想定メソッド:

```gdscript
func calculate_weapon_attack_power(unit: BattleUnit, weapon: WeaponData) -> int:
    var stats = status_calculator.calculate_final_base_stats(unit)

    match weapon.weapon_type:
        WeaponData.WeaponType.SWORD:
            return floori(stats["str"] * 0.8) + floori(stats["dex"] * 0.2) + weapon.weapon_power

        WeaponData.WeaponType.AXE:
            return floori(stats["str"] * 1.0) + weapon.weapon_power

        WeaponData.WeaponType.SPEAR:
            return floori(stats["str"] * 0.8) + floori(stats["agi"] * 0.2) + weapon.weapon_power

        WeaponData.WeaponType.BOW:
            return floori(stats["dex"] * 0.7) + floori(stats["str"] * 0.3) + weapon.weapon_power

        WeaponData.WeaponType.DAGGER:
            return floori(stats["dex"] * 0.6) + floori(stats["agi"] * 0.4) + weapon.weapon_power

        WeaponData.WeaponType.DUAL_BLADE:
            return floori(stats["agi"] * 0.6) + floori(stats["dex"] * 0.4) + weapon.weapon_power

        WeaponData.WeaponType.STAFF:
            return floori(stats["int"] * 0.7) + floori(stats["mnd"] * 0.3) + weapon.weapon_power

        WeaponData.WeaponType.MACE:
            return floori(stats["str"] * 0.7) + floori(stats["mnd"] * 0.3) + weapon.weapon_power

        WeaponData.WeaponType.FIST:
            return floori(stats["str"] * 0.7) + floori(stats["agi"] * 0.3) + weapon.weapon_power

    return unit.build_stats.attack_power
```

---

# 17. 通常攻撃を武器参照に変更する

`AttackSystem.gd` の通常攻撃ダメージ計算を変更する。

変更前:

```text
物理ダメージ = max(1, 攻撃力 - 防御力)
```

変更後:

```text
通常攻撃ダメージ = max(1, 武器攻撃力 - 防御力)
```

実装例:

```gdscript
func calculate_normal_attack_damage(attacker: BattleUnit, target: BattleUnit) -> int:
    var weapon = equipment_database.get_weapon(attacker.equipped_weapon_id)

    var attack_value: int

    if weapon != null:
        attack_value = weapon_power_calculator.calculate_weapon_attack_power(attacker, weapon)
    else:
        attack_value = attacker.build_stats.attack_power

    var defense_value = target.build_stats.defense

    return max(1, attack_value - defense_value)
```

---

# 18. 物理スキルを武器参照に変更する

`SkillSystem.gd` の物理スキル計算を変更する。

```text
物理スキルダメージ = max(1, 武器攻撃力 + スキル威力 - 防御力)
```

```gdscript
func calculate_physical_skill_damage(
    user: BattleUnit,
    target: BattleUnit,
    skill: SkillData
) -> int:
    var weapon = equipment_database.get_weapon(user.equipped_weapon_id)

    var attack_value: int

    if weapon != null:
        attack_value = weapon_power_calculator.calculate_weapon_attack_power(user, weapon)
    else:
        attack_value = user.build_stats.attack_power

    var defense_value = target.build_stats.defense

    return max(1, attack_value + skill.power - defense_value)
```

魔法スキルは従来どおり `magic_attack_power` を参照する。

回復スキルも従来どおりMNDを参照する。

---

# 19. 武器による命中補正

通常攻撃と物理スキルの命中率に、
武器の `weapon_accuracy_modifier` を加算する。

```gdscript
func calculate_hit_rate(attacker: BattleUnit, target: BattleUnit, skill_accuracy_modifier: int = 0) -> int:
    var hit = attacker.build_stats.accuracy
    var evade = target.build_stats.evasion

    var weapon_modifier = 0
    var weapon = equipment_database.get_weapon(attacker.equipped_weapon_id)
    if weapon != null:
        weapon_modifier = weapon.weapon_accuracy_modifier

    var final_hit = hit - evade + skill_accuracy_modifier + weapon_modifier + terrain_modifier + height_modifier

    return clampi(final_hit, 5, 95)
```

斧は低命中、弓や短剣は高命中になりやすい。

---

# 20. 武器による会心補正

通常攻撃と物理スキルの会心率に、
武器の `weapon_critical_modifier` を加算する。

```gdscript
func calculate_critical_rate(attacker: BattleUnit, target: BattleUnit, skill: SkillData = null) -> int:
    var rate = attacker.build_stats.critical_rate

    var weapon = equipment_database.get_weapon(attacker.equipped_weapon_id)
    if weapon != null:
        rate += weapon.weapon_critical_modifier

    if skill != null:
        rate += skill.critical_modifier

    return clampi(rate, 0, 50)
```

---

# 21. 武器射程を通常攻撃へ反映する

通常攻撃の射程を、ユニット固定ではなく武器から取得する。

`AttackSystem.gd` に追加。

```gdscript
func get_normal_attack_min_range(unit: BattleUnit) -> int:
    var weapon = equipment_database.get_weapon(unit.equipped_weapon_id)
    if weapon != null:
        return weapon.min_range
    return unit.min_attack_range

func get_normal_attack_max_range(unit: BattleUnit) -> int:
    var weapon = equipment_database.get_weapon(unit.equipped_weapon_id)
    if weapon != null:
        return weapon.max_range
    return unit.max_attack_range
```

攻撃範囲ハイライトも武器射程を使う。

---

# 22. 武器の射線判定

弓など `requires_line_of_sight = true` の武器は射線判定を行う。

```gdscript
func normal_attack_requires_line_of_sight(unit: BattleUnit) -> bool:
    var weapon = equipment_database.get_weapon(unit.equipped_weapon_id)
    if weapon != null:
        return weapon.requires_line_of_sight
    return unit.attack_type == BattleUnit.AttackType.RANGED
```

---

# 23. 戦闘前セットアップに装備UIを追加する

`PreBattleSetupPanel.gd` に装備欄を追加する。

UI例:

```text
PreBattleSetupPanel
├── UnitList
├── UnitDetailPanel
│   ├── NameLabel
│   ├── LevelLabel
│   ├── MainJobSelector
│   ├── SubJobSelector
│   ├── WeaponSelector
│   ├── ArmorSelector
│   ├── AccessorySelector
│   ├── StatPreviewPanel
│   ├── EquippedSkillList
│   └── AvailableSkillList
├── StartBattleButton
└── BackButton
```

---

# 24. 装備変更時のプレビュー

装備を変更したとき、変更前後のステータスを表示する。

表示例:

```text
Weapon: 鉄の剣 -> 鉄の斧

STR: 30 -> 31
DEX: 24 -> 23
AGI: 22 -> 21

ATK: 30 -> 31
ACC: 82 -> 72
CRIT: 9% -> 9%
MOVE: 5 -> 5
```

Phase 13では簡易的に、変更後の数値だけ表示でもよい。

---

# 25. 装備可能でない武器の表示

装備できない武器は、以下のどちらかで扱う。

```text
案A:
  リストに表示しない

案B:
  グレー表示して選択不可
```

Phase 13では案Aでよい。

---

# 26. UnitInfoPanelに装備情報を表示する

`UnitInfoPanel` に装備情報を追加する。

表示例:

```text
Vain
Lv: 3
HP: 270 / 270
AP: 32 / 32

Main Job: 剣術師 Lv 3
Sub Job: 弓術師

Weapon: 鉄の剣
Armor: レザーアーマー
Accessory: 力の指輪

ATK: 35
DEF: 28
ACC: 82
CRIT: 9%
MOVE: 5
JUMP: 1
```

---

# 27. セーブデータに装備を追加する

Phase 11のUnitProgressDataに以下を追加する。

```gdscript
"equipped_weapon_id": "iron_sword",
"equipped_armor_id": "leather_armor",
"equipped_accessory_id": "power_ring"
```

ロード時にBattleUnitへ反映する。

```gdscript
unit.equipped_weapon_id = data.get("equipped_weapon_id", "")
unit.equipped_armor_id = data.get("equipped_armor_id", "")
unit.equipped_accessory_id = data.get("equipped_accessory_id", "")
```

ロード後は必ずBuild値を再計算する。

```gdscript
unit.refresh_build_stats(status_calculator)
```

---

# 28. 初期装備設定

New Game時の初期装備を設定する。

```text
Vain:
  weapon: iron_sword
  armor: leather_armor
  accessory: power_ring

Acrea:
  weapon: wooden_staff
  armor: mage_robe
  accessory: mind_charm

Glen:
  weapon: short_bow
  armor: leather_armor
  accessory: accuracy_lens
```

敵ユニットにも装備を設定する。

```text
Bandit_A:
  weapon: iron_axe
  armor: leather_armor

Bandit_B:
  weapon: short_bow
  armor: leather_armor
```

---

# 29. 敵AIへの影響

敵AIは、通常攻撃範囲を武器射程から取得する。

```text
Bandit_A:
  斧なので射程1

Bandit_B:
  弓なので射程2-4
```

ThreatSystemも武器射程を使うようにする。

---

# 30. ThreatSystemへの装備反映

ThreatSystemの通常攻撃危険範囲は、
ユニット固定射程ではなく武器射程を参照する。

```gdscript
var min_range = attack_system.get_normal_attack_min_range(enemy)
var max_range = attack_system.get_normal_attack_max_range(enemy)
```

スキル危険範囲は従来どおりSkillDataを参照する。

---

# 31. CombatConfirmPanelへの表示追加

通常攻撃確認UIに武器名を表示する。

表示例:

```text
Attacker: Vain
Weapon: 鉄の剣
Target: Bandit_A

Damage: 26
Hit Rate: 87%
Critical: 9%
```

---

# 32. SkillConfirmPanelへの表示追加

物理スキルの場合、参照武器を表示する。

表示例:

```text
Skill: 強斬り
Weapon: 鉄の剣
Damage: 34
Hit Rate: 82%
Critical: 9%
```

魔法スキルの場合は武器名表示は任意。

---

# 33. 新規追加ファイル

以下を追加する。

```text
res://scripts/equipment/EquipmentData.gd
res://scripts/equipment/WeaponData.gd
res://scripts/equipment/ArmorData.gd
res://scripts/equipment/AccessoryData.gd
res://scripts/equipment/EquipmentDatabase.gd
res://scripts/equipment/EquipmentSystem.gd
res://scripts/equipment/WeaponPowerCalculator.gd
```

---

# 34. 既存ファイルの主な変更対象

以下を修正する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/status/StatusCalculator.gd
res://scripts/status/BuildStats.gd
res://scripts/job/JobData.gd
res://scripts/job/JobDatabase.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/SkillSystem.gd
res://scripts/battle/ThreatSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/save/UnitProgressManager.gd
res://scripts/ui/PreBattleSetupPanel.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/CombatConfirmPanel.gd
res://scripts/ui/SkillConfirmPanel.gd
res://scripts/Main.gd
```

---

# 35. 推奨ノード構成

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
├── EquipmentDatabase
├── EquipmentSystem
├── WeaponPowerCalculator
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
    ├── TurnOrderPanel
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

# 36. 完了条件

以下がすべて動作すれば完了。

1. EquipmentDataが存在する
2. WeaponDataが存在する
3. ArmorDataが存在する
4. AccessoryDataが存在する
5. EquipmentDatabaseが存在する
6. EquipmentSystemが存在する
7. WeaponPowerCalculatorが存在する
8. BattleUnitが武器・防具・アクセサリIDを持つ
9. JobDataが装備可能武器種を持つ
10. ジョブごとに装備可能武器が異なる
11. 装備できない武器はセットできない
12. 装備変更時にBuild値が再計算される
13. 装備の基礎ステータス補正がBuild値に反映される
14. 装備のBuild補正がBuild値に反映される
15. 装備の属性耐性補正がBuild値に反映される
16. 通常攻撃が武器攻撃力を参照する
17. 物理スキルが武器攻撃力を参照する
18. 魔法スキルは魔法攻撃力を参照する
19. 回復スキルはMNDを参照する
20. 武器の命中補正が命中率に反映される
21. 武器の会心補正が会心率に反映される
22. 通常攻撃の射程が武器から決まる
23. 弓は射線判定を行う
24. ThreatSystemが武器射程を考慮する
25. 敵AIが武器射程を考慮する
26. PreBattleSetupPanelで装備を変更できる
27. UnitInfoPanelに装備情報が表示される
28. CombatConfirmPanelに武器名と会心率が表示される
29. 装備情報がセーブされる
30. ロード後も装備が維持される
31. 既存の戦闘・スキル・CT・成長・セーブ/ロードが壊れていない

---

# 37. 今回は実装しないもの

以下はPhase 13では実装しない。

```text
- アイテム所持数
- インベントリ管理
- ショップ
- 装備購入
- 装備売却
- ドロップ
- 宝箱報酬
- 装備強化
- 鍛冶
- レアリティ
- 武器耐久度
- 装備固有スキル
- 防具カテゴリ制限
- アクセサリ複数装備
- 盾
- 武器ごとの専用攻撃アニメーション
```

---

# 38. 実装時の注意

```text
- 既存のBuild値計算を壊さない
- 装備補正はStatusCalculatorに集約する
- 通常攻撃は武器攻撃力を参照する
- 魔法スキルは武器攻撃力を参照しない
- 回復スキルはMNDを参照する
- 武器射程は通常攻撃に反映する
- スキル射程はSkillDataを優先する
- ThreatSystemは通常攻撃では武器射程を使う
- セーブするのは装備IDだけ
- 装備データそのものは保存しない
- ロード後に必ずBuild値を再計算する
- 装備できない武器をセットできないようにする
- Phase 13では防具とアクセサリは全ジョブ装備可能でよい
```

---

# 39. 実装後に提示してほしい内容

実装後、以下を説明してください。

```text
- 追加・変更したファイル一覧
- 追加したノード構成
- EquipmentDataの仕様
- WeaponDataの仕様
- ArmorDataの仕様
- AccessoryDataの仕様
- EquipmentDatabaseの仕様
- EquipmentSystemの仕様
- WeaponPowerCalculatorの仕様
- 武器種ごとの参照ステータス
- 装備可能武器種の仕様
- StatusCalculatorへの装備補正反映
- 通常攻撃計算の変更点
- 物理スキル計算の変更点
- 武器射程の仕様
- ThreatSystemへの反映内容
- PreBattleSetupPanelの装備UI
- セーブデータ変更点
- 動作確認手順
- 現時点の制限事項
- 次に実装しやすい項目
```

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**装備・武器種・武器攻撃力・装備補正システム** を追加してください。

具体的には以下を実装してください。

```text
- EquipmentDataを追加
- WeaponDataを追加
- ArmorDataを追加
- AccessoryDataを追加
- EquipmentDatabaseを追加
- EquipmentSystemを追加
- WeaponPowerCalculatorを追加
- BattleUnitに装備スロットを追加
- JobDataに装備可能武器種を追加
- ジョブごとに装備可能武器を設定
- 戦闘前セットアップで装備を変更できるようにする
- 装備変更時にBuild値を再計算する
- 装備補正をStatusCalculatorに反映する
- 通常攻撃を武器攻撃力参照に変更する
- 物理スキルを武器攻撃力参照に変更する
- 武器の命中補正・会心補正を反映する
- 通常攻撃射程を武器から取得する
- ThreatSystemとEnemyAIを武器射程に対応させる
- 装備IDをセーブデータに保存する
- ロード後も装備状態が維持されるようにする
```

ショップ・インベントリ・ドロップ・装備強化はまだ不要です。
まずは、ジョブとステータスの個性を戦闘に反映するための
**武器・装備の基礎システム** を完成させてください。
