# Godot SRPGプロトタイプ Phase 11 開発指示書

## 目的

Phase 11では、Phase 10までに実装した以下の要素を、
戦闘ごとに消えない **永続データ** として管理できるようにする。

* ユニットレベル
* EXP
* AP
* メインジョブ
* サブジョブ
* ジョブレベル
* ジョブEXP
* 解放済みスキル
* セット済みスキル
* ステージクリア状況

Phase 10では、戦闘前にキャラごとのビルドを設定できるようにした。

Phase 11では、そのビルドや成長結果を保存し、
次のステージや再起動後にも引き継げるようにする。

今回のゴールは以下。

```text
ゲーム開始
↓
ユニット永続データを読み込む
↓
戦闘前セットアップでジョブ・スキルを設定
↓
戦闘開始
↓
経験値・ジョブ経験値を得る
↓
ステージクリア
↓
成長結果を永続データへ反映
↓
セーブ
↓
次回起動時に同じ状態から再開できる
```

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 通常攻撃
* スキル
* AP
* 属性
* ジョブ
* メインジョブ / サブジョブ
* スキル解放
* セットスキル
* 戦闘前セットアップ
* EXP
* レベルアップ
* JobEXP
* JobLevelUp
* GrowthResultPanel
* StageManager
* Victory / Defeat
* BattleLog
* BattleMessage

---

# 今回の実装範囲

Phase 11では以下を実装する。

* PlayerProfileData
* UnitProgressData
* StageProgressData
* SaveData
* SaveManager
* Load処理
* Save処理
* 戦闘開始時の永続ユニットデータ反映
* 戦闘終了時の成長結果反映
* 戦闘前ビルドの保存
* ステージクリア状況の保存
* セーブ/ロード用のJSON出力
* テスト用のNew Game / Continue処理

今回は以下はまだ実装しない。

* 複数セーブスロット
* クラウドセーブ
* オートセーブ演出
* 拠点画面
* ステージ選択画面の本格UI
* セーブデータ暗号化
* バージョン移行処理の本格対応

---

# 1. SaveData の全体構造

セーブデータは、以下のような構造にする。

```gdscript
{
    "save_version": 1,
    "player_profile": {},
    "units": {},
    "stages": {},
    "system": {}
}
```

各項目の役割:

```text
save_version:
  セーブデータのバージョン

player_profile:
  プレイヤー全体の進行状況

units:
  味方ユニットごとの永続データ

stages:
  ステージごとのクリア状況

system:
  将来の設定やオプション用
```

---

# 2. SaveManager を追加する

セーブ/ロード処理を管理する。

追加ファイル:

```text
res://scripts/save/SaveManager.gd
```

責務:

* セーブデータの生成
* セーブデータの保存
* セーブデータの読み込み
* セーブファイルの存在確認
* New Game データの作成
* 読み込んだデータを各Managerへ反映
* 各Managerから現在データを収集

想定メソッド:

```gdscript
func has_save_file() -> bool:
    return FileAccess.file_exists(get_save_path())

func get_save_path() -> String:
    return "user://save_data.json"

func save_game() -> void:
    var data = build_save_data()
    write_json(data)

func load_game() -> Dictionary:
    if not has_save_file():
        return create_new_game_data()

    return read_json()

func build_save_data() -> Dictionary:
    return {
        "save_version": 1,
        "player_profile": player_profile_data.to_dict(),
        "units": unit_progress_manager.to_dict(),
        "stages": stage_progress_manager.to_dict(),
        "system": {}
    }

func apply_save_data(data: Dictionary) -> void:
    player_profile_data.from_dict(data.get("player_profile", {}))
    unit_progress_manager.from_dict(data.get("units", {}))
    stage_progress_manager.from_dict(data.get("stages", {}))
```

---

# 3. JSON保存形式

Phase 11では、Godotの `FileAccess` を使ってJSON保存する。

保存先:

```text
user://save_data.json
```

保存処理例:

```gdscript
func write_json(data: Dictionary) -> void:
    var file = FileAccess.open(get_save_path(), FileAccess.WRITE)
    if file == null:
        push_error("Failed to open save file for writing")
        return

    var json_text = JSON.stringify(data, "\t")
    file.store_string(json_text)
    file.close()
```

読み込み処理例:

```gdscript
func read_json() -> Dictionary:
    var file = FileAccess.open(get_save_path(), FileAccess.READ)
    if file == null:
        push_error("Failed to open save file for reading")
        return create_new_game_data()

    var json_text = file.get_as_text()
    file.close()

    var result = JSON.parse_string(json_text)
    if typeof(result) != TYPE_DICTIONARY:
        push_error("Invalid save data")
        return create_new_game_data()

    return result
```

---

# 4. UnitProgressData を追加する

味方ユニットごとの永続データを管理する。

追加ファイル:

```text
res://scripts/save/UnitProgressData.gd
```

または、ResourceではなくDictionaryベースでもよい。

ユニットごとに保存する内容:

```gdscript
{
    "unit_id": "vain",
    "unit_name": "Vain",

    "level": 3,
    "exp": 40,

    "max_hp": 130,
    "max_ap": 32,

    "strength": 12,
    "dexterity": 10,
    "vitality": 11,
    "mind": 8,
    "intelligence": 7,
    "agility": 10,

    "attack_power": 34,
    "defense": 10,
    "accuracy": 92,
    "evasion": 12,

    "main_job_id": "swordsman",
    "sub_job_id": "archer",

    "job_levels": {
        "swordsman": 3,
        "archer": 1
    },

    "job_exps": {
        "swordsman": 20,
        "archer": 0
    },

    "learned_skill_ids": [],
    "equipped_skill_ids": [
        "power_slash",
        "guard_stance"
    ],

    "unlocked_job_ids": [
        "swordsman",
        "archer"
    ]
}
```

---

# 5. UnitProgressManager を追加する

ユニット永続データをまとめて管理する。

追加ファイル:

```text
res://scripts/save/UnitProgressManager.gd
```

責務:

* 味方ユニットの進行データを保持
* 初期ユニットデータを作成
* セーブ用Dictionaryを生成
* ロードしたDictionaryを保持
* BattleUnitへ反映
* BattleUnitから更新

想定メソッド:

```gdscript
func create_default_units() -> void:
    # Vain / Acrea / Glen の初期データを作る

func apply_progress_to_unit(unit: BattleUnit) -> void:
    # unit_id に一致する進行データをBattleUnitへ反映

func update_progress_from_unit(unit: BattleUnit) -> void:
    # 戦闘後のBattleUnitの状態を永続データへ反映

func update_progress_from_units(units: Array) -> void:
    for unit in units:
        if unit.team == "player":
            update_progress_from_unit(unit)

func to_dict() -> Dictionary:
    # units_progress をDictionary化する

func from_dict(data: Dictionary) -> void:
    # セーブデータから復元する
```

---

# 6. BattleUnit と永続データの関係

`BattleUnit` は戦闘中に使う実体であり、
`UnitProgressData` は戦闘外で保持する永続データとする。

つまり、以下の関係にする。

```text
UnitProgressData:
  永続データ
  セーブ対象
  戦闘外で保持

BattleUnit:
  戦闘中の実体
  マップ上に配置される
  戦闘終了後にUnitProgressDataへ反映
```

戦闘開始時:

```text
UnitProgressData
↓
BattleUnitへ反映
↓
戦闘開始
```

戦闘終了時:

```text
BattleUnitの成長結果
↓
UnitProgressDataへ反映
↓
セーブ
```

---

# 7. 戦闘開始時の反映

`StageManager` または `UnitManager` で、
味方ユニット生成後に `UnitProgressManager` のデータを反映する。

処理例:

```gdscript
func spawn_player_units() -> void:
    var units = unit_manager.spawn_player_units()

    for unit in units:
        unit_progress_manager.apply_progress_to_unit(unit)
```

反映するもの:

* level
* exp
* max_hp
* max_ap
* hp
* ap
* 基本ステータス
* 戦闘ステータス
* main_job_id
* sub_job_id
* job_levels
* job_exps
* learned_skill_ids
* equipped_skill_ids
* unlocked_job_ids

戦闘開始時は、原則HP/APを全回復してもよい。

```gdscript
unit.hp = unit.max_hp
unit.ap = unit.max_ap
```

---

# 8. 戦闘終了時の反映

Victory時に、味方ユニットの成長結果を `UnitProgressManager` に反映する。

処理例:

```gdscript
func on_stage_victory() -> void:
    var player_units = unit_manager.get_player_units()
    unit_progress_manager.update_progress_from_units(player_units)

    stage_progress_manager.mark_stage_cleared(current_stage_id)

    save_manager.save_game()

    growth_result_panel.show_results(...)
```

Defeat時の扱いは、Phase 11では以下とする。

```text
Defeat時:
  成長結果は保存しない
  ステージクリア状況も保存しない
```

将来的に敗北時も経験値を保持する仕様にするかは後で決める。

---

# 9. StageProgressData を追加する

ステージごとの進行状況を保存する。

追加ファイル:

```text
res://scripts/save/StageProgressData.gd
```

保存内容例:

```gdscript
{
    "stage_id": "stage_001",
    "cleared": true,
    "clear_count": 1,
    "best_turn_count": 5,
    "opened_chests": [
        "chest_001"
    ],
    "triggered_events": [
        "intro_event",
        "reinforcement_turn_3"
    ]
}
```

Phase 11では最低限以下があればよい。

```gdscript
{
    "stage_id": "stage_001",
    "cleared": true,
    "clear_count": 1
}
```

---

# 10. StageProgressManager を追加する

追加ファイル:

```text
res://scripts/save/StageProgressManager.gd
```

責務:

* ステージクリア状況を保持
* ステージをクリア済みにする
* ステージが解放済みか判定する
* セーブ/ロード用Dictionaryへ変換する

想定メソッド:

```gdscript
func mark_stage_cleared(stage_id: String, turn_count: int = 0) -> void:
    var progress = stages.get(stage_id, {})
    progress["cleared"] = true
    progress["clear_count"] = int(progress.get("clear_count", 0)) + 1

    if turn_count > 0:
        var best = int(progress.get("best_turn_count", 999999))
        progress["best_turn_count"] = min(best, turn_count)

    stages[stage_id] = progress

func is_stage_cleared(stage_id: String) -> bool:
    return bool(stages.get(stage_id, {}).get("cleared", false))

func to_dict() -> Dictionary:
    return stages

func from_dict(data: Dictionary) -> void:
    stages = data.duplicate(true)
```

---

# 11. PlayerProfileData を追加する

プレイヤー全体の進行情報を保存する。

追加ファイル:

```text
res://scripts/save/PlayerProfileData.gd
```

保存内容例:

```gdscript
{
    "player_name": "Player",
    "current_stage_id": "stage_001",
    "play_time_seconds": 0,
    "gold": 0
}
```

Phase 11では最低限でよい。

```gdscript
var current_stage_id: String = "stage_001"
var gold: int = 0
```

---

# 12. New Game データ作成

セーブファイルが存在しない場合、
`SaveManager.create_new_game_data()` で初期データを作る。

初期データに含めるもの:

* Vain
* Acrea
* Glen
* 初期レベル
* 初期EXP
* 初期メインジョブ
* 初期サブジョブ
* 初期ジョブレベル
* 初期セットスキル
* 初期ステージID

例:

```gdscript
func create_new_game_data() -> Dictionary:
    unit_progress_manager.create_default_units()
    stage_progress_manager.create_default_progress()
    player_profile_data.create_default_profile()

    return build_save_data()
```

---

# 13. Continue 処理

起動時にセーブファイルがある場合は、
`Continue` として読み込む。

Phase 11では本格的なタイトル画面は不要。

以下のどちらかでよい。

## 案A: 自動ロード

```text
起動
↓
セーブデータがあれば自動ロード
↓
PreBattleSetupPanelを表示
```

## 案B: 簡易TitlePanel

```text
New Game
Continue
```

余裕があれば `TitlePanel.gd` を追加する。

追加ファイル候補:

```text
res://scripts/ui/TitlePanel.gd
```

Phase 11では案Aでもよい。

---

# 14. 戦闘前セットアップとの連携

`PreBattleSetupPanel` は、
`BattleUnit` の一時データではなく、`UnitProgressManager` の永続データを編集する方針にする。

ただし、既存実装がBattleUnitを直接編集している場合は、
以下の流れでもよい。

```text
PreBattleSetupPanelでBattleUnitを編集
↓
StartBattleButton押下時
↓
UnitProgressManagerへ反映
↓
戦闘開始
```

推奨は以下。

```text
PreBattleSetupPanel:
  UnitProgressDataを編集

戦闘開始:
  UnitProgressDataからBattleUnit生成
```

---

# 15. セットスキル保存

Phase 10で実装した `equipped_skill_ids` は必ず保存対象に含める。

保存対象:

```gdscript
"equipped_skill_ids": [
    "power_slash",
    "guard_stance",
    "aimed_shot"
]
```

ロード後、PreBattleSetupPanelで同じセット内容が表示されること。

---

# 16. メイン/サブジョブ保存

以下も保存対象にする。

```gdscript
"main_job_id": "swordsman",
"sub_job_id": "archer"
```

ロード後、PreBattleSetupPanelとUnitInfoPanelに反映されること。

---

# 17. ジョブレベル保存

以下も保存対象にする。

```gdscript
"job_levels": {
    "swordsman": 3,
    "archer": 1
}
```

メインジョブだけでなく、過去に育てたジョブレベルも保存できるようにする。

ただし、Phase 10仕様どおり、成長するのは現在のメインジョブのみ。

---

# 18. ジョブEXP保存

以下も保存対象にする。

```gdscript
"job_exps": {
    "swordsman": 20,
    "archer": 0
}
```

---

# 19. レベル/EXP保存

以下も保存対象にする。

```gdscript
"level": 3,
"exp": 40
```

---

# 20. ステータス保存

Phase 11では、レベルアップによって上がったステータスを保存する。

保存対象:

```text
max_hp
max_ap
attack_power
defense
accuracy
evasion
strength
dexterity
vitality
mind
intelligence
agility
```

---

# 21. セーブ実行タイミング

Phase 11では、以下のタイミングでセーブする。

## Victory時

```text
ステージクリア
↓
ユニット成長結果をUnitProgressManagerへ反映
↓
ステージクリア状況をStageProgressManagerへ反映
↓
SaveManager.save_game()
↓
GrowthResultPanel表示
```

## PreBattleSetupPanelでStartBattleを押した時

以下を保存してもよい。

```text
メインジョブ
サブジョブ
セットスキル
```

ただし、戦闘前セットアップの変更をすぐ保存するか、
Victory時に保存するかは仕様として決める必要がある。

Phase 11では以下を採用する。

```text
StartBattleButton押下時にビルド設定を保存する
Victory時に成長とクリア状況を保存する
```

---

# 22. セーブ失敗時の扱い

ファイル書き込みに失敗した場合は、
`push_error()` でログを出す。

UI表示はPhase 11では必須ではない。

```gdscript
push_error("Failed to save game")
```

---

# 23. ロード失敗時の扱い

セーブファイルが壊れている場合やJSONとして読めない場合は、
New Game データを作る。

ただし、データ消失が分かりにくいため、
BattleLogまたはConsoleに警告を出す。

```gdscript
push_warning("Save data is invalid. Starting new game.")
```

---

# 24. セーブデータバージョン

セーブデータには `save_version` を含める。

```gdscript
"save_version": 1
```

Phase 11では、バージョン差分移行処理は不要。

ただし、将来に備えて以下の関数を用意する。

```gdscript
func migrate_save_data(data: Dictionary) -> Dictionary:
    var version = int(data.get("save_version", 0))
    if version < 1:
        # 今回は何もしない
        data["save_version"] = 1
    return data
```

---

# 25. GrowthResultPanelとの連携

Victory後の `GrowthResultPanel` は、
今回保存された内容と一致するようにする。

表示例:

```text
Stage Clear

Vain
Lv 2 -> Lv 3
EXP: 40 / 100
Main Job: 剣術師 Lv 2 -> Lv 3
Sub Job: 弓術師
Unlocked: アースブレイク
Saved

Acrea
Lv 1 -> Lv 2
EXP: 20 / 100
Saved
```

最低限、保存済みであることが分かればよい。

---

# 26. Debug用セーブ操作

開発中に確認しやすいよう、デバッグ用のキー操作を追加してもよい。

例:

```text
F5:
  Save Game

F9:
  Load Game

F10:
  Delete Save
```

Phase 11では必須ではないが、あると便利。

削除処理を追加する場合:

```gdscript
func delete_save_file() -> void:
    if FileAccess.file_exists(get_save_path()):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(get_save_path()))
```

実装が不安定になる場合は削除処理は不要。

---

# 27. Save確認用ログ

セーブ/ロード時にBattleLogまたはConsoleへ表示する。

例:

```text
Game saved.
Game loaded.
New game data created.
```

---

# 28. 新規追加ファイル

以下を追加する。

```text
res://scripts/save/SaveManager.gd
res://scripts/save/UnitProgressData.gd
res://scripts/save/UnitProgressManager.gd
res://scripts/save/StageProgressData.gd
res://scripts/save/StageProgressManager.gd
res://scripts/save/PlayerProfileData.gd
```

必要に応じて以下も追加する。

```text
res://scripts/ui/TitlePanel.gd
```

---

# 29. 既存ファイルの主な変更対象

以下を修正する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/ui/PreBattleSetupPanel.gd
res://scripts/ui/GrowthResultPanel.gd
res://scripts/battle/StageManager.gd
res://scripts/battle/ExperienceSystem.gd
res://scripts/job/JobSystem.gd
res://scripts/Main.gd
```

必要に応じて以下も修正する。

```text
res://scripts/ui/BattleLog.gd
res://scripts/ui/BattleMessage.gd
res://scripts/ui/UnitInfoPanel.gd
```

---

# 30. 推奨ノード構成

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
    ├── TitlePanel
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

`TitlePanel` は実装する場合のみ追加する。

---

# 31. 完了条件

以下がすべて動作すれば完了。

1. セーブデータ構造が定義されている
2. `SaveManager.gd` が存在する
3. `user://save_data.json` にセーブできる
4. セーブファイルをロードできる
5. セーブファイルがない場合、New Gameデータを作成できる
6. 味方ユニットの level / exp が保存される
7. 味方ユニットのステータスが保存される
8. 味方ユニットの main_job_id / sub_job_id が保存される
9. 味方ユニットの job_levels / job_exps が保存される
10. 味方ユニットの equipped_skill_ids が保存される
11. 味方ユニットの unlocked_job_ids が保存される
12. ロード後、PreBattleSetupPanelに保存済みビルドが反映される
13. ロード後、戦闘中SkillMenuに保存済みセットスキルが反映される
14. Victory後、成長結果がUnitProgressManagerへ反映される
15. Victory後、ステージクリア状況が保存される
16. Defeat時は成長とクリア状況を保存しない
17. StartBattleButton押下時にビルド設定が保存される
18. 再起動後もレベル・ジョブ・セットスキルが維持される
19. GrowthResultPanelに保存済みであることが分かる表示がある
20. 既存の戦闘・スキル・成長・セットアップ機能が壊れていない

---

# 32. 今回は実装しないもの

以下はPhase 11では実装しない。

* 複数セーブスロット
* クラウドセーブ
* セーブデータ暗号化
* 本格的なタイトル画面
* 本格的なステージ選択画面
* 拠点画面
* ショップ
* 装備
* アイテム
* 永続的な所持品管理
* スマホUI
* セーブデータバージョン移行の本格対応
* オートセーブ演出
* ロード演出

---

# 33. 実装時の注意

* BattleUnitとUnitProgressDataの責務を分ける
* BattleUnitは戦闘中の実体として扱う
* UnitProgressDataは永続データとして扱う
* 戦闘開始時にUnitProgressDataをBattleUnitへ反映する
* Victory時にBattleUnitの結果をUnitProgressDataへ戻す
* Defeat時は原則保存しない
* equipped_skill_idsを必ず保存対象に含める
* main_job_id / sub_job_idを必ず保存対象に含める
* job_levels / job_expsをDictionaryとして保存する
* JSON保存時にGodot Objectを直接入れない
* 保存するのはString / int / float / bool / Array / Dictionaryのみにする
* セーブデータが壊れていてもゲームが落ちないようにする
* 今回はシンプルなJSON保存でよい

---

# 34. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* SaveDataの構造
* SaveManagerの仕様
* UnitProgressDataの仕様
* UnitProgressManagerの仕様
* StageProgressManagerの仕様
* PlayerProfileDataの仕様
* 戦闘開始時のロード反映フロー
* 戦闘終了時の保存フロー
* PreBattleSetupPanelとの連携
* GrowthResultPanelとの連携
* セーブファイルの保存場所
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**ユニット永続データ・セーブ/ロード・ステージ間引き継ぎ** を追加してください。

具体的には以下を実装してください。

* SaveManagerを追加
* UnitProgressManagerを追加
* StageProgressManagerを追加
* PlayerProfileDataを追加
* `user://save_data.json` へJSON保存する
* セーブファイルがない場合はNew Gameデータを作る
* セーブファイルがある場合はロードする
* 戦闘開始前に保存済みユニットデータを反映する
* 戦闘前セットアップで変更したメインジョブ・サブジョブ・セットスキルを保存する
* Victory後にレベル・EXP・ジョブレベル・ジョブEXP・ステータスを保存する
* Victory後にステージクリア状況を保存する
* Defeat時は成長とクリア状況を保存しない
* 再起動後も成長結果とセットスキルが維持されるようにする

複数セーブスロット、拠点画面、ステージ選択画面、装備、アイテムはまだ不要です。
まずは、戦闘で成長したキャラクター情報が次回以降も残る状態を完成させてください。
