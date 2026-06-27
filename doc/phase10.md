# Godot SRPGプロトタイプ Phase 10 開発指示書

## 目的

Phase 10では、Phase 9までに実装した
**経験値・ジョブ成長・スキル習得システム** を拡張し、
戦闘開始前にキャラクターごとのジョブと使用スキルを設定できるようにする。

今回の主な目的は以下。

* 戦闘前セットアップ画面を追加する
* 1キャラごとに使用スキルを最大6個までセットできるようにする
* メインジョブとサブジョブを設定できるようにする
* ジョブ経験値はメインジョブだけに入るようにする
* サブジョブは成長しない
* スキルはジョブレベルに応じて解放される
* サブジョブ由来のスキルは、メインジョブレベルの半分までの範囲でセット可能にする

Phase 10のゴールは、
**戦闘前にキャラごとの役割を準備し、その設定が戦闘中のSkillMenuに反映される状態** を作ることである。

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 通常攻撃
* HP / AP
* スキル
* 属性
* SkillData
* SkillDatabase
* SkillSystem
* ElementSystem
* SkillMenu
* SkillConfirmPanel
* 経験値
* レベルアップ
* JobData
* JobDatabase
* JobSystem
* JobEXP
* JobLevelUp
* スキル習得
* BattleLog
* BattleMessage
* GrowthResultPanel

---

# 今回の実装範囲

Phase 10では以下を実装する。

* UnitBuildData
* メインジョブ
* サブジョブ
* ジョブレベル管理の整理
* スキル解放条件
* セットスキル
* セットスキル上限
* 戦闘前セットアップ画面
* キャラごとのスキルセットUI
* 戦闘中SkillMenuへのセットスキル反映
* JobEXPをメインジョブだけに入れる処理
* サブジョブスキル使用制限
* セット内容の仮保存

ただし、今回は以下はまだ実装しない。

* 本格的なセーブ/ロード
* 装備
* アイテム
* スキルツリー画面
* ジョブチェンジ演出
* 拠点画面全体
* 複雑なパーティ編成
* ステージ選択画面

---

# 1. スキルは戦闘前にセットする方式へ変更する

現在は、`BattleUnit.skill_ids` に入っているスキルをそのまま戦闘中に使える想定になっている。

Phase 10ではこれを変更する。

## 変更後の考え方

```text id="ijyx2y"
learned_skill_ids:
  そのキャラが習得済みのスキル

equipped_skill_ids:
  戦闘で使用するためにセットしたスキル
```

戦闘中の `SkillMenu` には、
`equipped_skill_ids` のスキルだけを表示する。

---

# 2. BattleUnit のスキル情報を整理する

`BattleUnit.gd` に以下を追加・変更する。

```gdscript id="eehkww"
var learned_skill_ids: Array[String] = []
var equipped_skill_ids: Array[String] = []
```

既存の `skill_ids` がある場合は、以下のどちらかに整理する。

## 推奨

`skill_ids` を廃止し、以下へ移行する。

```gdscript id="gmvy8c"
learned_skill_ids
equipped_skill_ids
```

互換性を残したい場合は、当面以下でもよい。

```gdscript id="40qxa4"
var skill_ids: Array[String] = [] # 旧互換用。将来的に廃止予定
```

ただし、戦闘中に使用するスキルは必ず `equipped_skill_ids` を参照する。

---

# 3. セットスキル上限を定数化する

1キャラにセットできるスキル上限は **6個** とする。

ただし、後から変更できるように定数化する。

追加候補:

```gdscript id="a09p01"
const DEFAULT_MAX_EQUIPPED_SKILLS: int = 6
```

または `GameBalance.gd` のような設定ファイルを追加する。

追加ファイル候補:

```text id="g2gff9"
res://scripts/config/GameBalance.gd
```

内容例:

```gdscript id="pbzida"
class_name GameBalance

const MAX_EQUIPPED_SKILLS: int = 6
```

将来的にキャラやジョブごとにセット枠を増やす可能性があるため、
`BattleUnit` 側にも上書き用の値を持たせてもよい。

```gdscript id="m4ti9v"
var max_equipped_skills: int = GameBalance.MAX_EQUIPPED_SKILLS
```

---

# 4. メインジョブとサブジョブを追加する

現在の `BattleUnit.job_id` を、メインジョブとサブジョブに分ける。

```gdscript id="3xaoa7"
var main_job_id: String = ""
var sub_job_id: String = ""
```

表示用に以下も持ってよい。

```gdscript id="lc59bi"
var main_job_name: String = ""
var sub_job_name: String = ""
```

既存の `job_id` / `job_name` は段階的に廃止する。
ただし、既存処理が壊れる場合は、当面 `main_job_id` と同じ値を入れて互換性を保つ。

```gdscript id="4grrwv"
job_id = main_job_id
job_name = main_job_name
```

---

# 5. ジョブレベル管理をジョブごとにする

Phase 9では `job_level` / `job_exp` がユニットに1つだけ存在していた。

Phase 10では、ジョブごとのレベルを持てるようにする。

`BattleUnit.gd` に以下を追加する。

```gdscript id="z96ka6"
var job_levels: Dictionary = {}
var job_exps: Dictionary = {}
```

例:

```gdscript id="rilgy3"
job_levels = {
    "swordsman": 3,
    "archer": 1
}

job_exps = {
    "swordsman": 20,
    "archer": 0
}
```

ジョブレベル取得メソッドを追加する。

```gdscript id="4kezck"
func get_job_level(job_id: String) -> int:
    return int(job_levels.get(job_id, 1))

func get_job_exp(job_id: String) -> int:
    return int(job_exps.get(job_id, 0))

func set_job_level(job_id: String, level: int) -> void:
    job_levels[job_id] = level

func set_job_exp(job_id: String, exp: int) -> void:
    job_exps[job_id] = exp
```

---

# 6. メインジョブのみ成長する仕様

Phase 10では、JobEXPはメインジョブにのみ入る。

サブジョブは成長しない。

つまり、戦闘中にJobEXPを得た場合は以下。

```text id="8cxsm6"
unit.main_job_id の job_exp に加算する
unit.sub_job_id の job_exp には加算しない
```

`JobSystem.grant_job_exp()` を修正する。

```gdscript id="rd3m56"
func grant_job_exp(unit: BattleUnit, amount: int) -> Dictionary:
    var target_job_id = unit.main_job_id

    if target_job_id == "":
        return {}

    # target_job_id の経験値だけを増やす
```

---

# 7. サブジョブのスキル使用条件

サブジョブは成長しないが、
メインジョブレベルの半分のレベルまでのスキルをセットできる。

## 仕様

```text id="lhl8qu"
サブジョブで使用可能なスキルレベル上限 =
floor(メインジョブレベル / 2)
```

ただし、最低1は許可する。

```gdscript id="gkyxfb"
var sub_job_access_level = max(1, floor(main_job_level / 2))
```

例:

```text id="pgma2d"
メインジョブLv1:
  サブジョブLv1相当のスキルまで使用可能

メインジョブLv2:
  サブジョブLv1相当のスキルまで使用可能

メインジョブLv3:
  サブジョブLv1相当のスキルまで使用可能

メインジョブLv4:
  サブジョブLv2相当のスキルまで使用可能

メインジョブLv6:
  サブジョブLv3相当のスキルまで使用可能
```

---

# 8. スキル解放条件をJobDataに持たせる

`JobData.gd` の `learnable_skills` を、スキル解放条件として使う。

例:

```gdscript id="ue6q56"
@export var learnable_skills: Array[Dictionary] = [
    {
        "job_level": 1,
        "skill_id": "power_slash"
    },
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

メインジョブの場合:

```text id="r8zyp4"
そのジョブの実際の job_level までのスキルが使用候補になる
```

サブジョブの場合:

```text id="7buv1l"
メインジョブレベルの半分までのスキルが使用候補になる
```

---

# 9. SkillUnlockSystem を追加する

スキル解放判定を `JobSystem` に混ぜすぎないため、
`SkillUnlockSystem.gd` を追加する。

追加ファイル:

```text id="9e3i79"
res://scripts/skill/SkillUnlockSystem.gd
```

責務:

* メインジョブ由来の使用可能スキルを取得する
* サブジョブ由来の使用可能スキルを取得する
* セット可能スキル一覧を返す
* そのスキルがセット可能か判定する
* 習得済みスキルとジョブ解放スキルの整合性を取る

想定メソッド:

```gdscript id="qglvvv"
func get_available_skill_ids_for_unit(unit: BattleUnit) -> Array[String]:
    var result: Array[String] = []
    result.append_array(get_main_job_skill_ids(unit))
    result.append_array(get_sub_job_skill_ids(unit))
    return result

func get_main_job_skill_ids(unit: BattleUnit) -> Array[String]:
    # main_job_id の job_level までのスキルを返す

func get_sub_job_skill_ids(unit: BattleUnit) -> Array[String]:
    # sub_job_id のうち、main_job_level / 2 までのスキルを返す

func can_equip_skill(unit: BattleUnit, skill_id: String) -> bool:
    # 使用可能スキル一覧に含まれているかを判定
```

---

# 10. learned_skill_ids の扱い

Phase 9では、ジョブレベルアップ時に `learned_skill_ids` へスキルを追加する方式だった。

Phase 10では、以下の方針にする。

## 方針

```text id="xk6u2i"
ジョブレベルで解放されるスキル:
  JobData.learnable_skills から動的に取得する

learned_skill_ids:
  イベント習得・固有習得・ストーリー習得など、ジョブ外スキル用に残す
```

つまり、セット可能スキルは以下の合算。

```text id="htb7cg"
メインジョブで解放されているスキル
+ サブジョブで使用可能な範囲のスキル
+ learned_skill_ids の固有スキル
```

---

# 11. セットスキル処理

`BattleUnit.gd` に以下を追加する。

```gdscript id="bk9xq0"
func equip_skill(skill_id: String) -> bool:
    if equipped_skill_ids.has(skill_id):
        return true

    if equipped_skill_ids.size() >= max_equipped_skills:
        return false

    equipped_skill_ids.append(skill_id)
    return true

func unequip_skill(skill_id: String) -> void:
    equipped_skill_ids.erase(skill_id)

func clear_equipped_skills() -> void:
    equipped_skill_ids.clear()
```

ただし、実際にセット可能かどうかは `SkillUnlockSystem.can_equip_skill()` で判定する。

---

# 12. スキルセットのバリデーション

メインジョブ・サブジョブが変更された場合、
現在セット中のスキルが使用条件を満たさなくなる可能性がある。

そのため、以下の処理を追加する。

```gdscript id="0q2uzb"
func validate_equipped_skills(unit: BattleUnit) -> void:
    var valid_skill_ids = skill_unlock_system.get_available_skill_ids_for_unit(unit)

    for skill_id in unit.equipped_skill_ids.duplicate():
        if not valid_skill_ids.has(skill_id):
            unit.unequip_skill(skill_id)
```

この処理は以下のタイミングで呼ぶ。

* メインジョブ変更時
* サブジョブ変更時
* ジョブレベルアップ時
* 戦闘開始前
* セットアップ画面を開いた時

---

# 13. 戦闘前セットアップ画面を追加する

Phase 10では、ステージ開始前にセットアップ画面を挟む。

追加ファイル:

```text id="f5z8jk"
res://scripts/ui/PreBattleSetupPanel.gd
```

表示内容:

```text id="flp3uk"
出撃ユニット一覧
選択中ユニット情報
メインジョブ
サブジョブ
セット中スキル
セット可能スキル一覧
開始ボタン
戻るボタン
```

UI例:

```text id="sfw66b"
PreBattleSetupPanel
├── UnitList
├── UnitDetailPanel
│   ├── NameLabel
│   ├── LevelLabel
│   ├── MainJobSelector
│   ├── SubJobSelector
│   ├── EquippedSkillList
│   └── AvailableSkillList
├── StartBattleButton
└── BackButton
```

---

# 14. メインジョブ選択UI

`MainJobSelector` では、ユニットが選択できるメインジョブを表示する。

Phase 10では、選択可能ジョブは仮でよい。

例:

```text id="xjqq5t"
Vain:
  swordsman
  magic_swordsman

Acrea:
  magic_swordsman
  swordsman

Glen:
  archer
  swordsman
```

将来的に「解放済みジョブ」システムにするが、
Phase 10ではユニットごとに使用可能ジョブID配列を持たせる。

`BattleUnit.gd` に追加。

```gdscript id="ty0b9r"
var unlocked_job_ids: Array[String] = []
```

---

# 15. サブジョブ選択UI

`SubJobSelector` では、メインジョブとは別のジョブを選べる。

ルール:

```text id="cbvt8l"
サブジョブは unlocked_job_ids の中から選択できる
メインジョブと同じジョブも許可してよい
ただし同じ場合はサブジョブ由来スキルは重複表示しない
```

同じジョブを禁止したい場合は後で調整する。
Phase 10では同じジョブでも許可してよい。

---

# 16. ジョブ変更時の処理

メインジョブを変更した場合:

```text id="068h3f"
unit.main_job_id を変更
main_job_name を更新
必要なら move_range / jump_height などを更新
validate_equipped_skills を実行
UIを再描画
```

サブジョブを変更した場合:

```text id="9g5n76"
unit.sub_job_id を変更
sub_job_name を更新
validate_equipped_skills を実行
UIを再描画
```

Phase 10では、ステータス再計算は最小限でよい。
ただし、ジョブ名とスキル候補は必ず変わるようにする。

---

# 17. セット可能スキル一覧UI

`AvailableSkillList` には、選択中ユニットがセット可能なスキルを表示する。

表示情報:

```text id="oy7y90"
スキル名
AP Cost
属性
射程
種別
由来ジョブ
必要ジョブLv
```

例:

```text id="50h04t"
強斬り
AP 5 / 攻撃 / 射程1 / Main: 剣術師 Lv1

アースブレイク
AP 10 / 土属性 / 範囲 / Main: 剣術師 Lv3

狙い撃ち
AP 5 / 遠距離 / Sub: 弓術師 Lv2
```

---

# 18. セット中スキル一覧UI

`EquippedSkillList` には、現在セットしているスキルを表示する。

```text id="k2fxdr"
Equipped Skills 3 / 6

1. 強斬り
2. アースブレイク
3. 狙い撃ち
```

スキルを選択して外せるようにする。

---

# 19. スキルセット操作

操作仕様:

```text id="6y6vw4"
AvailableSkillListでスキルを選択
↓
セット枠に空きがある
↓
セット可能条件を満たす
↓
equipped_skill_ids に追加
↓
EquippedSkillList更新
```

セット済みスキルを選択した場合:

```text id="f3kapu"
EquippedSkillListでスキルを選択
↓
equipped_skill_ids から削除
↓
AvailableSkillList更新
```

---

# 20. セット上限エラー

セット上限6個を超える場合は、UIにメッセージを出す。

表示例:

```text id="w9rfkl"
セットできるスキルは最大6個です
```

英語UIなら:

```text id="x5dhpw"
Max 6 skills can be equipped
```

BattleLogではなく、PreBattleSetupPanel内のメッセージ欄でよい。

---

# 21. 戦闘中SkillMenuの変更

戦闘中の `SkillMenu` は、
`SkillUnlockSystem.get_available_skill_ids_for_unit()` ではなく、
必ず `unit.equipped_skill_ids` を参照する。

```gdscript id="qjdql9"
func get_skills_for_battle(unit: BattleUnit) -> Array[SkillData]:
    var result: Array[SkillData] = []
    for skill_id in unit.equipped_skill_ids:
        var skill = skill_database.get_skill(skill_id)
        if skill != null:
            result.append(skill)
    return result
```

これにより、戦闘前にセットしていないスキルは戦闘中に使えない。

---

# 22. ステージ開始前の流れを変更する

現在はステージ開始時にすぐ戦闘へ入っている場合、
以下の流れに変更する。

```text id="s2eqdx"
ステージ選択またはテスト開始
↓
PreBattleSetupPanelを表示
↓
ユニットごとにメインジョブ・サブジョブ・セットスキルを確認
↓
StartBattleButtonを押す
↓
セット内容をバリデーション
↓
戦闘開始
```

Phase 10ではステージ選択画面は不要。
起動後に直接 `PreBattleSetupPanel` を出してもよい。

---

# 23. セット内容の仮保存

Phase 10では本格的なセーブ/ロードは不要。

ただし、戦闘中に使うため、セット内容を `BattleUnit` に保持する。

後から保存に対応しやすいよう、以下のようなデータ取得メソッドを作る。

```gdscript id="hhn3u8"
func get_build_data() -> Dictionary:
    return {
        "unit_id": unit_id,
        "main_job_id": main_job_id,
        "sub_job_id": sub_job_id,
        "equipped_skill_ids": equipped_skill_ids.duplicate()
    }

func apply_build_data(data: Dictionary) -> void:
    main_job_id = data.get("main_job_id", main_job_id)
    sub_job_id = data.get("sub_job_id", sub_job_id)
    equipped_skill_ids = data.get("equipped_skill_ids", []).duplicate()
```

---

# 24. UnitBuildData Resource の追加

将来の保存やビルド管理を見据えて、
`UnitBuildData.gd` を追加してもよい。

追加ファイル:

```text id="s8mv0p"
res://scripts/unit/UnitBuildData.gd
```

内容例:

```gdscript id="2bsps6"
class_name UnitBuildData
extends Resource

@export var unit_id: String
@export var main_job_id: String
@export var sub_job_id: String
@export var equipped_skill_ids: Array[String] = []
```

Phase 10では、実際に `.tres` 保存しなくてもよい。
構造だけ作っておく。

---

# 25. ジョブ成長結果の表示修正

GrowthResultPanelでは、ジョブ成長がメインジョブにだけ入ったことが分かるようにする。

表示例:

```text id="m6af11"
Vain
Main Job: 剣術師 Lv 2 -> Lv 3
Sub Job: 弓術師 Lv 1
JobEXP gained: 剣術師 +13
```

サブジョブ欄には、経験値が入っていないことを明示してもよい。

```text id="5e06hv"
Sub Job: 弓術師 Lv 1
No JobEXP gained
```

ただし、UIが複雑になる場合は、メインジョブの成長だけ表示すればよい。

---

# 26. UnitInfoPanel の表示修正

戦闘中のUnitInfoPanelにメイン/サブジョブとセットスキル数を表示する。

表示例:

```text id="ed5bpo"
Vain
Lv: 3
HP: 130 / 130
AP: 32 / 32

Main Job: 剣術師 Lv 3
Sub Job: 弓術師
Equipped Skills: 4 / 6
```

---

# 27. JobSystem の修正

JobSystemは、今後以下の方針にする。

```text id="1ex5k0"
JobEXP:
  main_job_id にのみ加算

JobLevel:
  job_levels[main_job_id] を上げる

SkillUnlock:
  JobLevelUp時にスキル候補を解放する
  ただし、戦闘中に即使用可能になるのではなく、
  次回セットアップ時にセットできるようになる
```

つまり、JobLevelUpで新スキルが解放されても、
戦闘中の `equipped_skill_ids` に自動追加しない。

BattleLogには以下を表示する。

```text id="bnn02j"
Vain unlocked ガードスタンス
Set it before battle to use it.
```

日本語なら:

```text id="glsfn2"
ヴェインは「ガードスタンス」を解放した
次の戦闘前セットアップでセットできます
```

---

# 28. スキル解放とスキルセットの違い

コード上でもUI上でも以下を明確に分ける。

```text id="cnwwnw"
Unlocked:
  ジョブレベル条件を満たして使用候補になっている

Equipped:
  戦闘前にセットして、戦闘中に使用できる
```

戦闘中SkillMenuは `Equipped` のみ表示する。

---

# 29. 初期セットスキル

テストしやすいよう、初期状態で各味方にセット済みスキルを入れる。

```text id="ww48w7"
Vain:
  main_job_id = swordsman
  sub_job_id = archer
  equipped_skill_ids = [
    "power_slash"
  ]

Acrea:
  main_job_id = magic_swordsman
  sub_job_id = swordsman
  equipped_skill_ids = [
    "aqua_edge",
    "healing_water"
  ]

Glen:
  main_job_id = archer
  sub_job_id = swordsman
  equipped_skill_ids = [
    "aimed_shot"
  ]
```

スキルが未解放の場合は、初期化時に解放条件を満たすようにジョブレベルを調整するか、
初期セットだけはテスト用として許可してよい。

推奨は、初期ジョブレベルを以下にする。

```text id="djfjhh"
Vain swordsman Lv 1
Acrea magic_swordsman Lv 3
Glen archer Lv 2
```

---

# 30. 新規追加ファイル

以下を追加する。

```text id="uhekvj"
res://scripts/config/GameBalance.gd
res://scripts/skill/SkillUnlockSystem.gd
res://scripts/ui/PreBattleSetupPanel.gd
res://scripts/unit/UnitBuildData.gd
```

既存構成によっては、`UnitBuildData.gd` はPhase 10では省略してもよい。

---

# 31. 既存ファイルの主な変更対象

以下を修正する。

```text id="ukrrd4"
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/job/JobSystem.gd
res://scripts/job/JobData.gd
res://scripts/job/JobDatabase.gd
res://scripts/skill/SkillDatabase.gd
res://scripts/ui/SkillMenu.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/GrowthResultPanel.gd
res://scripts/battle/StageManager.gd
res://scripts/Main.gd
```

必要に応じて以下も修正する。

```text id="f7lq3e"
res://scripts/battle/SkillSystem.gd
res://scripts/battle/ThreatSystem.gd
res://scripts/battle/EnemyAI.gd
```

---

# 32. 推奨ノード構成

`Main.tscn` を以下のように拡張する。

```text id="s4k6j1"
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

# 33. 完了条件

以下がすべて動作すれば完了。

1. BattleUnitが `main_job_id` を持つ
2. BattleUnitが `sub_job_id` を持つ
3. BattleUnitが `job_levels` をDictionaryで持つ
4. BattleUnitが `job_exps` をDictionaryで持つ
5. JobEXPはメインジョブにのみ加算される
6. サブジョブにはJobEXPが加算されない
7. メインジョブレベルに応じてメインジョブスキルが使用候補になる
8. サブジョブはメインジョブレベルの半分までのスキルが使用候補になる
9. スキルは戦闘前にセットできる
10. 1キャラにセットできるスキル上限が6個である
11. セット上限は定数として変更可能になっている
12. セットできるスキル一覧がPreBattleSetupPanelに表示される
13. セット中スキル一覧がPreBattleSetupPanelに表示される
14. スキルをセットできる
15. スキルを外せる
16. 条件を満たさないスキルはセットできない
17. メイン/サブジョブ変更時、無効なセットスキルが外れる
18. 戦闘中SkillMenuにはセット済みスキルだけが表示される
19. JobLevelUpで解放されたスキルが自動装備されない
20. 解放済みスキルは次回セットアップでセットできる
21. UnitInfoPanelにメイン/サブジョブとセットスキル数が表示される
22. GrowthResultPanelでメインジョブ成長が分かる
23. 既存のスキル使用・AP消費・敵AI・ThreatSystem・勝敗判定が壊れていない

---

# 34. 今回は実装しないもの

以下はPhase 10では実装しない。

* 本格的なセーブ/ロード
* ジョブチェンジ解放条件
* クラスチェンジ
* スキルツリーUI
* スキルポイント
* 装備
* アイテム
* ショップ
* 拠点画面
* ステージ選択画面
* 出撃人数選択
* 永続的なパーティ管理
* スマホUI
* 複雑なサブジョブ補正
* サブジョブ成長
* サブジョブ経験値

---

# 35. 実装時の注意

* スキルの「解放」と「セット」を明確に分ける
* 戦闘中に使えるのは `equipped_skill_ids` のみ
* `learned_skill_ids` は固有スキルやイベント習得用として残す
* セットスキル上限は6だが、定数化して後で変更しやすくする
* JobEXPは必ずメインジョブにのみ加算する
* サブジョブにはJobEXPを入れない
* サブジョブの使用可能スキルレベルは `floor(main_job_level / 2)` とする
* ただし最低1は許可する
* メインジョブ・サブジョブ変更時は `validate_equipped_skills()` を必ず実行する
* JobLevelUp時に新スキルを自動装備しない
* PreBattleSetupPanelは仮UIでよいが、操作可能な状態にする
* 既存のPhase 8.5のAP表記を崩さない
* 既存のPhase 9の成長ログを壊さない

---

# 36. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* BattleUnitに追加したビルド関連項目
* main_job_id / sub_job_id の仕様
* job_levels / job_exps の仕様
* メインジョブ成長仕様
* サブジョブ制限仕様
* SkillUnlockSystemの仕様
* セット可能スキル判定
* equipped_skill_idsの仕様
* PreBattleSetupPanelの操作方法
* 戦闘中SkillMenuへの反映方法
* JobLevelUp時のスキル解放仕様
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**戦闘前スキルセット・メインジョブ/サブジョブ・スキル解放制限** を追加してください。

具体的には以下を実装してください。

* BattleUnitに `main_job_id` / `sub_job_id` を追加
* BattleUnitに `job_levels` / `job_exps` を追加
* BattleUnitに `learned_skill_ids` / `equipped_skill_ids` を追加
* セットスキル上限を6にする
* 上限値は後から変更しやすいよう定数化する
* SkillUnlockSystemを追加する
* メインジョブのレベルに応じてスキルを解放する
* サブジョブはメインジョブレベルの半分までのスキルをセット可能にする
* JobEXPはメインジョブにのみ加算する
* サブジョブは成長しない
* PreBattleSetupPanelを追加する
* 戦闘開始前にスキルをセットできるようにする
* 戦闘中SkillMenuにはセット済みスキルだけを表示する
* JobLevelUpで新スキルが解放されても自動装備しない
* 解放済みスキルは次回セットアップでセットできるようにする

装備・アイテム・セーブロード・スキルツリーUIはまだ不要です。
まずは、戦闘前にキャラクタービルドを組んで戦闘へ入る基礎を完成させてください。
