# Godot SRPGプロトタイプ Phase 12 開発指示書

## 目的

Phase 12では、既存のSRPG戦闘システムに対して、
**CT制の行動順システム** を追加する。

Phase 11.5では、基礎ステータスとBuild値を整理し、
AGIから `speed` を算出できるようにした。

Phase 12では、この `speed` を実際の戦闘進行に反映し、
従来の「味方ターン → 敵ターン」という固定フェーズ制から、
ユニットごとの素早さによって行動順が決まる方式へ移行する。

今回のゴールは以下。

```text
AGIが高いユニットほどCTが早く溜まる
CTが100以上になったユニットから行動できる
行動後、CTを消費して次のユニットへ進む
待機した場合は次回行動が少し早くなる
行動順UIで次に動くユニットが分かる
敵味方が入り混じった行動順になる
```

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* 通常攻撃
* スキル
* AP
* 属性
* メインジョブ / サブジョブ
* ジョブレベル
* スキルセット
* 戦闘前セットアップ
* 経験値
* レベルアップ
* セーブ / ロード
* ジョブ体系
* 基礎ステータス
* BuildStats
* StatusCalculator
* Build値としての speed
* BattleLog
* BattleMessage
* UnitInfoPanel

---

# 今回の実装範囲

Phase 12では以下を実装する。

* CT値
* CT蓄積処理
* CT行動順システム
* TurnManagerのCT対応
* 行動可能ユニットの選出
* 待機時CTボーナス
* 行動順UI
* 敵味方混在ターン
* CT制に合わせた敵AI実行
* CT制に合わせた入力制御
* UnitInfoPanelへのCT表示
* BattleLogへの行動順ログ

ただし、今回は以下はまだ実装しない。

* 高度なタイムライン予測
* 行動内容ごとのCT消費差
* スキルごとの詠唱時間
* 割り込み行動
* リアクションスキル
* 加速 / 鈍足バフの本格反映
* CT制専用の大型UI
* ATB風リアルタイム進行

---

# 1. CT制の基本仕様

CTは、ユニットごとに蓄積される行動ゲージとする。

```text
CT = Charge Time
```

基本ルール:

```text
各ユニットは ct を持つ
戦闘開始時 ct は 0
戦闘進行時、各ユニットの ct に speed を加算する
ct が 100 以上になったユニットが行動可能になる
行動後、そのユニットの ct を 0 に戻す
```

待機時は、次回行動を少し早めるためにCTボーナスを残す。

```text
通常行動後:
  ct = 0

待機後:
  ct = 20
```

---

# 2. BattleUnit にCTを追加する

`BattleUnit.gd` に以下を追加する。

```gdscript
var ct: int = 0
var is_current_actor: bool = false
```

CT操作用メソッドを追加する。

```gdscript
func add_ct(amount: int) -> void:
    ct += amount

func is_ready_to_act() -> bool:
    return ct >= 100 and is_alive()

func reset_ct_after_action() -> void:
    ct = 0

func reset_ct_after_wait() -> void:
    ct = 20
```

---

# 3. speedの参照元

CT蓄積に使う値は、Phase 11.5で追加したBuild値の `speed` を使う。

```gdscript
var speed = unit.build_stats.speed
```

`build_stats` が未生成の場合に備えて、最低限のフォールバックを用意する。

```gdscript
func get_ct_speed(unit: BattleUnit) -> int:
    if unit.build_stats != null:
        return max(1, unit.build_stats.speed)

    return max(1, unit.agility)
```

既存の `agility` がない場合は、`base_agi` を使う。

---

# 4. TurnManagerをCT制へ対応する

既存の `TurnManager.gd` は、
Phase 2以降の `PLAYER_TURN` / `ENEMY_TURN` を管理している。

Phase 12では、いきなり完全削除せず、CT制モードを追加する。

```gdscript
enum TurnMode {
    TEAM_PHASE,
    CT
}

var turn_mode: TurnMode = TurnMode.CT
```

既存のチームフェーズ制は残してよい。
ただし、Phase 12の戦闘では `CT` を使用する。

---

# 5. CT用のTurnStateを追加する

`TurnManager.gd` にCT制用の状態を追加する。

```gdscript
enum TurnState {
    INITIALIZING,
    CHARGING_CT,
    UNIT_READY,
    PLAYER_ACTING,
    ENEMY_ACTING,
    ACTION_RESOLVING,
    BATTLE_RESULT
}

var current_turn_state: TurnState = TurnState.INITIALIZING
var current_actor: BattleUnit = null
```

---

# 6. CT蓄積処理

行動可能ユニットがいない場合、全生存ユニットのCTを蓄積する。

想定メソッド:

```gdscript
func charge_ct_until_actor_ready() -> BattleUnit:
    while true:
        var alive_units = unit_manager.get_alive_units()

        for unit in alive_units:
            unit.add_ct(get_ct_speed(unit))

        var ready_units = get_ready_units(alive_units)

        if ready_units.size() > 0:
            return choose_next_actor(ready_units)
```

ただし、無限ループ防止のため、最大ループ回数を設ける。

```gdscript
var safety_count = 0
while safety_count < 1000:
    safety_count += 1
    ...
```

---

# 7. 行動可能ユニットの選出

CTが100以上のユニットを行動可能とする。

```gdscript
func get_ready_units(units: Array) -> Array:
    var result = []

    for unit in units:
        if unit.is_ready_to_act():
            result.append(unit)

    return result
```

複数ユニットが同時にCT100以上になった場合は、以下の優先順位で決める。

```text
1. CT値が高いユニット
2. speedが高いユニット
3. teamがplayerのユニット
4. unit_id順
```

実装例:

```gdscript
func choose_next_actor(ready_units: Array) -> BattleUnit:
    ready_units.sort_custom(func(a, b):
        if a.ct != b.ct:
            return a.ct > b.ct

        if a.build_stats.speed != b.build_stats.speed:
            return a.build_stats.speed > b.build_stats.speed

        if a.team != b.team:
            return a.team == "player"

        return a.unit_id < b.unit_id
    )

    return ready_units[0]
```

---

# 8. 現在行動ユニットの設定

次の行動ユニットが決まったら、以下を行う。

```text
current_actorに設定
is_current_actor = true
カメラを対象へ移動
BattleMessageで通知
行動可能UIを表示
```

想定処理:

```gdscript
func start_actor_turn(actor: BattleUnit) -> void:
    current_actor = actor
    actor.is_current_actor = true

    battle_message.show_message(actor.unit_name + " Turn")

    camera_controller.focus_on_unit(actor)

    if actor.team == "player":
        current_turn_state = TurnState.PLAYER_ACTING
        battle_cursor.enable_player_control(actor)
    else:
        current_turn_state = TurnState.ENEMY_ACTING
        battle_cursor.disable_input()
        await enemy_ai.process_enemy_unit(actor)
        finish_actor_turn(actor, false)
```

---

# 9. プレイヤー行動の変更

CT制では、プレイヤーが自由に未行動ユニットを選ぶのではなく、
現在行動可能になったユニットだけを操作する。

変更前:

```text
プレイヤーターン中、未行動の味方ユニットを選択できる
```

変更後:

```text
current_actor が味方の場合、そのユニットだけ操作できる
他の味方ユニットは選択できない
```

`BattleCursor.gd` のユニット選択処理を修正する。

```gdscript
func can_select_unit(unit: BattleUnit) -> bool:
    if turn_manager.turn_mode == TurnManager.TurnMode.CT:
        return unit == turn_manager.current_actor

    return unit.team == "player" and not unit.has_acted
```

---

# 10. 行動終了処理

通常攻撃、スキル、待機、向き変更後に、
`finish_actor_turn()` を呼ぶ。

```gdscript
func finish_actor_turn(actor: BattleUnit, waited: bool = false) -> void:
    actor.is_current_actor = false

    if waited:
        actor.reset_ct_after_wait()
    else:
        actor.reset_ct_after_action()

    current_actor = null
    current_turn_state = TurnState.CHARGING_CT

    check_battle_result()

    if not is_battle_finished:
        start_next_ct_turn()
```

---

# 11. 待機時のCTボーナス

待機を選択した場合、CTを完全に0へ戻さず、
20だけ残す。

```gdscript
func on_wait_selected() -> void:
    finish_actor_turn(current_actor, true)
```

仕様:

```text
攻撃・スキル使用:
  行動後CT = 0

待機:
  行動後CT = 20
```

これにより、何もせず待機したユニットは次回行動が少し早くなる。

---

# 12. 攻撃 / スキル実行後のCT処理

通常攻撃決定後:

```gdscript
func on_combat_confirmed() -> void:
    var result = attack_system.execute_attack(current_actor, selected_attack_target)
    battle_log.show_attack_result(current_actor, selected_attack_target, result)

    finish_actor_turn(current_actor, false)
```

スキル決定後:

```gdscript
func on_skill_confirmed() -> void:
    var result = skill_system.execute_skill(current_actor, selected_skill, selected_target_cell)
    battle_log.show_skill_result(current_actor, selected_skill, result)

    finish_actor_turn(current_actor, false)
```

---

# 13. 敵AIのCT対応

敵もCTによって行動する。

従来の敵ターン処理:

```text
敵ターン開始
↓
敵全員が順番に行動
↓
プレイヤーターンへ
```

CT制では以下に変更する。

```text
CTが100以上になった敵1体だけが行動
↓
行動終了
↓
次のCT蓄積へ
```

`EnemyAI.gd` は、1体の敵を処理する関数を中心にする。

```gdscript
func process_enemy_unit(enemy: BattleUnit) -> void:
    # 既存AIを使って、この敵1体だけ行動させる
```

複数敵をまとめて処理する関数がある場合は、CT制では使わない。

---

# 14. has_acted / has_moved の扱い

従来のチームターン制では `has_acted` / `has_moved` を使っていた。

CT制では、基本的にこれらは不要になる。

ただし、既存コードとの互換性のため、当面は残す。

CT制では以下のように扱う。

```text
行動開始時:
  has_acted = false
  has_moved = false

行動終了時:
  has_acted = true
  has_moved = true
```

次のユニット行動開始時には、現在行動ユニットだけ初期化する。

```gdscript
func prepare_actor_for_turn(actor: BattleUnit) -> void:
    actor.has_acted = false
    actor.has_moved = false
```

将来的にはCT制では不要になったら削除する。

---

# 15. 行動順UIを追加する

CT制では、次に誰が動くか分かることが重要になる。

追加ファイル:

```text
res://scripts/ui/TurnOrderPanel.gd
```

UI例:

```text
TurnOrderPanel
├── CurrentActorLabel
└── UpcomingList
```

表示例:

```text
Current:
Vain

Next:
1. Bandit_A
2. Glen
3. Acrea
4. Bandit_B
```

---

# 16. 行動順予測

Phase 12では、厳密な未来予測でなくてよい。

簡易的に、現在のCTとspeedから次に行動しそうな順番を算出する。

計算イメージ:

```gdscript
func estimate_turn_order(count: int = 5) -> Array:
    var simulated = []

    for unit in unit_manager.get_alive_units():
        simulated.append({
            "unit": unit,
            "ct": unit.ct,
            "speed": get_ct_speed(unit)
        })

    var order = []

    while order.size() < count:
        for entry in simulated:
            entry["ct"] += entry["speed"]

        simulated.sort_custom(func(a, b):
            return a["ct"] > b["ct"]
        )

        var next = simulated[0]
        order.append(next["unit"])
        next["ct"] = 0

    return order
```

待機CTボーナスや行動内容差までは考慮しなくてよい。

---

# 17. TurnOrderPanelの更新タイミング

以下のタイミングで更新する。

```text
- 戦闘開始時
- CT蓄積後
- current_actor決定時
- 行動終了時
- ユニット撃破時
- speedが変化した時
```

Phase 12では、speed変化はほぼないため、
戦闘開始・行動終了・撃破時に更新できればよい。

---

# 18. UnitInfoPanelにCTを表示する

`UnitInfoPanel` にCTとspeedを表示する。

表示例:

```text
Vain
Lv: 3
HP: 270 / 270
AP: 32 / 32

CT: 80 / 100
Speed: 22

Main Job: 剣術師 Lv 3
Sub Job: 弓術師
```

---

# 19. BattleHUDに現在行動ユニットを表示する

`BattleHUD` に現在の行動ユニットを表示する。

```text
Current Actor: Vain
```

敵の場合:

```text
Current Actor: Bandit_A
```

---

# 20. BattleMessageの表示

行動開始時に中央表示を出す。

味方:

```text
Vain Turn
```

敵:

```text
Bandit_A Turn
```

戦闘開始時:

```text
Battle Start
```

---

# 21. BattleLogの表示

CT制に合わせてログを出す。

例:

```text
Battle started
Vain is ready
Vain waits
Bandit_A is ready
Bandit_A attacks Acrea
Glen is ready
```

---

# 22. 勝利 / 敗北判定

CT制でも既存の勝敗判定を維持する。

行動終了時、攻撃・スキル・撃破処理の後に必ず判定する。

```gdscript
func check_battle_result() -> void:
    if unit_manager.are_all_enemies_defeated():
        stage_manager.handle_victory()

    elif unit_manager.are_all_players_defeated():
        stage_manager.handle_defeat()
```

勝敗確定後はCT蓄積を止める。

```gdscript
if is_battle_finished:
    current_turn_state = TurnState.BATTLE_RESULT
    return
```

---

# 23. CT制での入力制御

以下のタイミングではプレイヤー入力を無効化する。

```text
- CT蓄積中
- 敵行動中
- 攻撃 / スキル演出中
- BattleMessage表示中
- Victory / Defeat後
```

味方の `current_actor` が行動可能な時だけ入力を有効にする。

---

# 24. 戦闘開始時の初期CT

Phase 12では、全ユニットのCTを0から開始する。

```gdscript
func initialize_ct_for_battle() -> void:
    for unit in unit_manager.get_all_units():
        unit.ct = 0
        unit.is_current_actor = false
```

将来的には、AGIが高いユニットに初期CTボーナスを与えてもよいが、
Phase 12では不要。

---

# 25. CT制とStageManagerの連携

`StageManager` の戦闘開始処理で、
従来のターン初期化ではなくCT初期化を行う。

```gdscript
func start_battle() -> void:
    unit_manager.spawn_units()
    status_calculator.refresh_all_units()
    turn_manager.initialize_ct_battle()
```

---

# 26. TurnManagerの初期化

`TurnManager.gd` に以下を追加する。

```gdscript
func initialize_ct_battle() -> void:
    turn_mode = TurnMode.CT
    current_turn_state = TurnState.INITIALIZING
    current_actor = null

    initialize_ct_for_battle()

    battle_message.show_message("Battle Start")

    start_next_ct_turn()
```

---

# 27. 次ターン開始処理

```gdscript
func start_next_ct_turn() -> void:
    if is_battle_finished:
        return

    current_turn_state = TurnState.CHARGING_CT

    var actor = charge_ct_until_actor_ready()

    if actor == null:
        push_error("No actor found in CT system")
        return

    start_actor_turn(actor)
```

---

# 28. カメラ制御

行動ユニットが決まったら、そのユニットへカメラを寄せる。

```gdscript
camera_controller.focus_on_unit(actor)
```

既存のカメラ制御がある場合は、それを流用する。

敵行動時も、行動前に敵へカメラを寄せる。

---

# 29. ThreatSystemとの関係

ThreatSystemは引き続き使用する。

ただし、CT制では「次の敵ターン」という概念が薄くなる。

Phase 12では、紫マスの意味を以下に変更する。

```text
そのマスに移動した場合、
現在生存している敵の攻撃・スキル範囲に入る可能性があるマス
```

つまり、厳密に「次に動く敵」だけでなく、
敵全体の攻撃可能性として表示してよい。

既存のThreatSystemを大きく変更しなくてよい。

---

# 30. CT制と経験値 / JobEXP

経験値・JobEXPの処理は既存どおり。

ただし、行動単位が「現在行動ユニット」になるため、
経験値付与対象は必ず `current_actor` を基準にする。

```gdscript
experience_system.grant_exp(current_actor, amount)
job_system.grant_job_exp(current_actor, amount)
```

---

# 31. CT制とセーブ/ロード

Phase 12では、戦闘中CT値の保存は不要。

保存するのは従来どおり、ステージクリア後の永続データのみ。

```text
保存する:
  レベル
  EXP
  ジョブ
  スキル
  ステージ進行

保存しない:
  戦闘中のCT
  current_actor
  行動順
```

---

# 32. 新規追加ファイル

以下を追加する。

```text
res://scripts/ui/TurnOrderPanel.gd
```

必要に応じて、CT制を分離する場合は以下を追加してもよい。

```text
res://scripts/battle/CTTurnSystem.gd
```

ただし、Phase 12では `TurnManager.gd` に統合してもよい。

---

# 33. 既存ファイルの主な変更対象

以下を修正する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/battle/TurnManager.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/StageManager.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/SkillSystem.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/BattleMessage.gd
res://scripts/ui/BattleLog.gd
res://scripts/Main.gd
```

必要に応じて以下も修正する。

```text
res://scripts/battle/ThreatSystem.gd
res://scripts/camera/CameraController.gd
```

---

# 34. 推奨ノード構成

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

# 35. 完了条件

以下がすべて動作すれば完了。

1. BattleUnitがCTを持つ
2. BattleUnitが現在行動ユニットかどうかを持つ
3. TurnManagerにCTモードが追加されている
4. 全ユニットのCTがspeedに応じて蓄積される
5. CTが100以上になったユニットが行動可能になる
6. AGI / speedが高いユニットほど行動が早く回る
7. 複数ユニットが同時に行動可能な場合、優先順位で決定される
8. 味方ユニットがcurrent_actorの場合、そのユニットだけ操作できる
9. 敵ユニットがcurrent_actorの場合、敵AIがその1体だけ行動する
10. 通常攻撃後、CTが0になる
11. スキル使用後、CTが0になる
12. 待機後、CTが20になる
13. 行動後、自動で次のCT蓄積へ進む
14. 敵味方が入り混じった行動順になる
15. TurnOrderPanelに現在ユニットと次の行動候補が表示される
16. UnitInfoPanelにCTとspeedが表示される
17. BattleHUDに現在行動ユニットが表示される
18. BattleMessageに行動開始通知が表示される
19. Victory / Defeat後、CT処理が停止する
20. 既存の攻撃・スキル・経験値・JobEXP・セーブ/ロードが壊れていない

---

# 36. 今回は実装しないもの

以下はPhase 12では実装しない。

```text
- スキルごとのCT消費差
- 詠唱時間
- 行動遅延スキル
- 割り込み行動
- リアクションスキル
- 加速 / 鈍足バフの本格処理
- CT値のセーブ
- 高度なターン順予測
- CTバーの豪華なアニメーション
- 敵AIの未来予測
- スマホ向けUI調整
```

---

# 37. 実装時の注意

```text
- 既存のチームターン制をすぐ削除しない
- TurnMode.TEAM_PHASEを残しておく
- Phase 12ではTurnMode.CTを使う
- current_actor以外の味方を操作できないようにする
- 敵AIは敵全体ではなく、current_actorの敵1体だけ処理する
- CT蓄積ループに安全装置を入れる
- Victory / Defeat後にCT蓄積が続かないようにする
- 待機時だけCTを20残す
- 攻撃・スキル使用時はCTを0にする
- has_acted / has_movedは互換用として残す
- ThreatSystemは敵全体の危険範囲として維持する
- CT値はセーブしない
- speedはBuildStatsから参照する
```

---

# 38. 実装後に提示してほしい内容

実装後、以下を説明してください。

```text
- 追加・変更したファイル一覧
- 追加したノード構成
- BattleUnitに追加したCT項目
- TurnManagerのCT制仕様
- CT蓄積処理
- 行動可能ユニットの選出ルール
- 同時行動可能時の優先順位
- プレイヤー操作制限の変更点
- 敵AIのCT対応
- 待機時CTボーナス仕様
- TurnOrderPanelの仕様
- UnitInfoPanelのCT表示
- BattleHUDの現在行動ユニット表示
- ThreatSystemとの関係
- 既存チームターン制との互換方針
- 動作確認手順
- 現時点の制限事項
- 次に実装しやすい項目
```

---

# まず実装してください

既存のSRPG戦闘システムに対して、
**CT制の行動順システム** を追加してください。

具体的には以下を実装してください。

```text
- BattleUnitにctを追加
- BattleUnitにis_current_actorを追加
- TurnManagerにTurnMode.CTを追加
- speedに応じてCTを蓄積する
- CTが100以上のユニットを行動可能にする
- current_actorを決定する
- 味方current_actorのみ操作可能にする
- 敵current_actorはEnemyAIで1体だけ行動させる
- 行動後CTを0にする
- 待機後CTを20にする
- TurnOrderPanelを追加する
- UnitInfoPanelにCTとspeedを表示する
- BattleHUDに現在行動ユニットを表示する
- Victory / Defeat後にCT処理を停止する
```

スキルごとのCT消費差、詠唱時間、割り込み、リアクションスキルはまだ不要です。
まずは、AGIとBuild値のspeedが実際の行動順に反映される
**基本CTターンシステム** を完成させてください。
