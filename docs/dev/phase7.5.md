# Godot SRPGプロトタイプ Phase 7.5 改善指示書

## 目的

Phase 8 に進む前に、既存のSRPG戦闘システムの操作感と視認性を改善する。

今回の目的は、新しいジョブ・スキル・魔法などを追加することではなく、
既存の移動・攻撃・敵ターン処理をよりSRPGらしく、分かりやすくすることである。

主な改善点は以下。

* 移動先が敵の攻撃範囲に入っているかを事前に分かるようにする
* 危険マスに入った場合、どの敵から攻撃される可能性があるかを視覚的に表示する
* 攻撃対象選択後、即攻撃ではなく戦闘予測UIと確認操作を挟む
* 敵ユニットの移動を瞬間移動ではなくアニメーションで表示する

---

## 前提

以下の機能はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 移動可能範囲表示
* 攻撃範囲表示
* HP / 攻撃力 / 防御力
* 命中率 / 回避率
* 高低差補正
* 地形効果
* 射線判定
* 向き補正
* 戦闘予測UI
* 敵AI
* Victory / Defeat 判定
* StageManager / EventManager / TriggerManager

---

# 今回の改善項目

## 1. 移動可能範囲に危険マス表示を追加する

現在、味方ユニットを選択したとき、移動可能範囲が青色で表示されている。

これを以下のように変更する。

```text
通常の移動可能マス:
  青色

移動可能だが、次の敵ターンで敵から攻撃を受ける可能性があるマス:
  紫色
```

つまり、移動可能範囲を表示するときに、各移動候補マスについて

```text
そのマスに移動した場合、敵の攻撃範囲に入るか
```

を判定する。

---

## 2. ThreatSystem を追加する

敵から攻撃される可能性のあるマスを計算するため、
`ThreatSystem.gd` を追加する。

追加ファイル:

```text
res://scripts/battle/ThreatSystem.gd
```

責務:

* 敵ユニットの攻撃可能範囲を計算する
* 指定マスが敵の攻撃範囲内か判定する
* 指定マスを攻撃可能な敵ユニット一覧を返す
* 味方ユニットが移動した場合の仮想位置から被攻撃リスクを判定する

想定メソッド:

```gdscript
func get_threatening_enemies_for_cell(
    target_unit: BattleUnit,
    target_cell: GridCell
) -> Array:
    # target_unit が target_cell にいると仮定した場合、
    # 攻撃可能な敵ユニット一覧を返す

func is_cell_threatened(
    target_unit: BattleUnit,
    target_cell: GridCell
) -> bool:
    return get_threatening_enemies_for_cell(target_unit, target_cell).size() > 0

func get_enemy_threat_cells(enemy: BattleUnit) -> Array:
    # 指定敵ユニットが攻撃可能なマス一覧を返す
```

---

## 3. ThreatSystem の判定条件

敵から攻撃される可能性があるかどうかは、既存の攻撃判定を利用する。

必ず `AttackSystem` の判定ロジックを再利用する。

判定に含めるもの:

* 敵ユニットの攻撃射程
* 近接 / 遠距離
* 高低差
* 射線判定
* 地形効果
* min_attack_range / max_attack_range
* 生存状態
* 敵ユニットのチーム

ただし、ThreatSystemでは実際に攻撃を実行しない。

あくまで

```text
このマスにいた場合、攻撃される可能性があるか
```

を調べるだけにする。

---

## 4. 仮想位置での攻撃判定

まだ移動前の段階でリスク判定を行うため、
対象ユニットを実際に移動させずに、仮想座標として判定する必要がある。

`AttackSystem` に以下のようなメソッドを追加してもよい。

```gdscript
func can_attack_cell(
    attacker: BattleUnit,
    target_unit: BattleUnit,
    target_cell: GridCell
) -> bool:
    # target_unit が target_cell にいると仮定して、
    # attacker がそのマスを攻撃可能か判定する
```

または、ThreatSystem側で一時的な座標を使って判定してもよい。

注意:

* 実際の `unit.grid_x` / `unit.grid_z` を変更しない
* `GridCell.occupied_unit` を変更しない
* 仮想判定後に状態が壊れないこと

---

## 5. 移動範囲ハイライトの色分け

既存の移動範囲表示を拡張する。

想定メソッド:

```gdscript
func show_move_range(
    cells: Array,
    selected_unit: BattleUnit
) -> void:
    for cell in cells:
        if threat_system.is_cell_threatened(selected_unit, cell):
            show_danger_move_highlight(cell)
        else:
            show_safe_move_highlight(cell)
```

表示ルール:

```text
safe move:
  blue

danger move:
  purple
```

既存のハイライト管理がある場合、以下のように分ける。

```gdscript
func show_safe_move_highlight(cell: GridCell) -> void
func show_danger_move_highlight(cell: GridCell) -> void
func clear_move_highlights() -> void
```

---

## 6. 危険マス侵入時の敵攻撃予測矢印

味方ユニットが紫色の危険マスへ移動した場合、
そのマスを攻撃可能な敵から、移動した味方ユニットへ向かって赤色の放物線矢印を表示する。

表示イメージ:

```text
敵ユニット
  ↓ 赤色の放物線矢印
移動後の味方ユニット
```

これは実際に攻撃される処理ではなく、
「この敵から狙われる可能性がある」という警告演出である。

---

## 7. ThreatArrowManager を追加する

危険マス侵入時の矢印表示を管理するため、
`ThreatArrowManager.gd` を追加する。

追加ファイル:

```text
res://scripts/battle/ThreatArrowManager.gd
```

責務:

* 敵から味方への赤い放物線矢印を表示する
* 複数の敵から狙われる場合、複数本表示する
* 行動メニューやキャンセル時に矢印を消す
* ユニットが移動前に戻った場合も矢印を消す

想定メソッド:

```gdscript
func show_threat_arrows(
    enemies: Array,
    target_unit: BattleUnit
) -> void:
    clear_threat_arrows()
    for enemy in enemies:
        create_threat_arrow(enemy, target_unit)

func clear_threat_arrows() -> void

func create_threat_arrow(
    from_unit: BattleUnit,
    to_unit: BattleUnit
) -> Node3D:
    # 放物線矢印を生成する
```

---

## 8. 放物線矢印の簡易実装

最初は厳密なメッシュでなくてよい。

以下のいずれかで実装する。

### 案A: Line3D風のMesh生成

* `ImmediateMesh` または `ArrayMesh` で曲線を描画
* 始点: 敵ユニットの上
* 終点: 味方ユニットの上
* 中間点: 高めのY座標
* 色: 赤

### 案B: 複数の小さなSphereやCylinderを並べる

* 放物線上に小さな赤い点を並べる
* 終点側に小さな三角形またはConeを置く
* 視認性優先

### 案C: まずは直線でもよい

実装難度が高い場合、Phase 7.5では赤い直線矢印でもよい。
ただし、後から放物線に変更しやすいように `ThreatArrowManager` に分離する。

---

## 9. 危険矢印を表示するタイミング

表示タイミングは以下。

```text
味方ユニットが危険マスへ移動完了
↓
ThreatSystemで攻撃可能な敵を取得
↓
該当する敵が1体以上いる場合
↓
ThreatArrowManagerで赤色矢印を表示
↓
行動メニューを表示
```

疑似コード:

```gdscript
func on_player_unit_moved(unit: BattleUnit, target_cell: GridCell) -> void:
    var enemies = threat_system.get_threatening_enemies_for_cell(unit, target_cell)

    if enemies.size() > 0:
        threat_arrow_manager.show_threat_arrows(enemies, unit)
    else:
        threat_arrow_manager.clear_threat_arrows()

    action_menu.show_for_unit(unit)
```

---

## 10. 危険矢印を消すタイミング

以下のタイミングで必ず消す。

* 行動を確定したとき
* 待機したとき
* 攻撃したとき
* 移動後キャンセルしたとき
* ユニット選択を解除したとき
* 敵ターンへ移行したとき
* Victory / Defeat になったとき

想定メソッド:

```gdscript
threat_arrow_manager.clear_threat_arrows()
```

---

# 攻撃確認UIの追加

## 11. 攻撃対象選択後に即攻撃しない

現在は、攻撃可能範囲から敵を選択すると、即座に攻撃が実行される。

これを変更する。

変更後の流れ:

```text
攻撃を選択
↓
攻撃可能範囲を表示
↓
敵ユニットを選択
↓
戦闘確認UIを表示
↓
命中率・予想ダメージ・攻撃方向・地形補正などを表示
↓
「決定」または「キャンセル」を選択
↓
決定なら攻撃実行
↓
キャンセルなら攻撃対象選択へ戻る
```

---

## 12. CombatConfirmPanel を追加する

追加ファイル:

```text
res://scripts/ui/CombatConfirmPanel.gd
```

UIノード例:

```text
UI
└── CombatConfirmPanel
    ├── AttackerLabel
    ├── TargetLabel
    ├── DamageLabel
    ├── HitRateLabel
    ├── TerrainLabel
    ├── DirectionLabel
    ├── ConfirmButton
    └── CancelButton
```

---

## 13. CombatConfirmPanel の表示内容

最低限、以下を表示する。

```text
Attacker: Vain
Target: Bandit_A

Damage: 26
Hit Rate: 87%
Target HP: 58 / 80
After HP: 32 / 80

Attack Direction: Side
Terrain: Forest
Line of Sight: Clear
```

可能であれば以下も表示する。

```text
命中時: 26 damage
撃破可能: Yes / No
被反撃: Phase 7.5では不要
```

---

## 14. BattleCursor の状態追加

攻撃確認UI用に、CursorModeを追加する。

```gdscript
enum CursorMode {
    IDLE,
    UNIT_SELECTED,
    ACTION_MENU,
    ATTACK_TARGETING,
    COMBAT_CONFIRM,
    ENEMY_PROCESSING,
    BATTLE_RESULT
}
```

`COMBAT_CONFIRM` の役割:

* 攻撃対象は選択済み
* まだ攻撃は実行しない
* ConfirmButtonで攻撃実行
* CancelButtonでATTACK_TARGETINGへ戻る
* カーソル操作は基本的に停止してよい

---

## 15. 攻撃対象選択時の処理変更

変更前:

```gdscript
attack_system.execute_attack(attacker, target)
finish_player_unit_action(attacker)
```

変更後:

```gdscript
selected_attack_target = target
combat_confirm_panel.show_preview(attacker, target)
current_mode = CursorMode.COMBAT_CONFIRM
```

---

## 16. 攻撃決定時の処理

ConfirmButtonを押したら攻撃を実行する。

```gdscript
func on_combat_confirmed() -> void:
    var result = attack_system.execute_attack(selected_unit, selected_attack_target)
    battle_log.show_attack_result(selected_unit, selected_attack_target, result)

    combat_confirm_panel.hide()
    selected_attack_target = null

    finish_player_unit_action(selected_unit)
```

攻撃後は既存の以下を必ず維持する。

* HP減少
* Miss処理
* 撃破処理
* BattleLog表示
* Victory / Defeat 判定
* 行動済み化
* 敵ターン移行判定

---

## 17. 攻撃キャンセル時の処理

CancelButtonを押したら攻撃対象選択へ戻る。

```gdscript
func on_combat_cancelled() -> void:
    combat_confirm_panel.hide()
    selected_attack_target = null
    current_mode = CursorMode.ATTACK_TARGETING
    show_attack_range(selected_unit)
```

このとき、以下は行わない。

* 攻撃実行
* HP減少
* 行動済み化
* 移動キャンセル
* 行動メニューへ戻る

つまり、攻撃対象の選び直しができる状態に戻る。

---

## 18. 既存のダメージ予測UIとの関係

Phase 5〜6で既に攻撃対象にカーソルを合わせた時の戦闘予測UIがある場合、
今回の `CombatConfirmPanel` はそれより一段強い「最終確認UI」として扱う。

役割分担:

```text
UnitInfoPanel / BattleHUD:
  カーソルを合わせた時の軽い予測表示

CombatConfirmPanel:
  攻撃対象を選択した後の最終確認
```

---

# 敵移動アニメーション

## 19. 敵の瞬間移動をやめる

現在、敵ターンで敵ユニットが移動する際、
移動先へ瞬間移動している。

これを、味方ユニットと同じように移動アニメーションでつなぐ。

---

## 20. UnitMover を追加または共通化する

味方と敵の移動演出を共通化するため、
`UnitMover.gd` を追加するか、既存の `UnitManager` 内の移動処理を拡張する。

推奨追加ファイル:

```text
res://scripts/unit/UnitMover.gd
```

責務:

* グリッド座標に沿ったユニット移動
* 経路に沿って順番に移動する
* 高低差に応じて上下移動する
* 移動完了を `await` できる
* 味方・敵両方で使う

想定メソッド:

```gdscript
func move_unit_along_path(
    unit: BattleUnit,
    path: Array
) -> void:
    # pathはGridCell配列
    # 各セルへ順番に移動する
```

非同期で扱う場合:

```gdscript
func move_unit_along_path(
    unit: BattleUnit,
    path: Array
) -> Signal:
    # finished signal を返す、または await できる構造にする
```

Godotでは以下のように使える形を目指す。

```gdscript
await unit_mover.move_unit_along_path(enemy, path)
```

---

## 21. 敵AIで移動経路を取得する

敵が移動先だけでなく、移動経路も取得できるようにする。

`Pathfinding.gd` に以下を追加または確認する。

```gdscript
func find_path(
    unit: BattleUnit,
    target_cell: GridCell
) -> Array:
    # unitの現在地からtarget_cellまでのGridCell配列を返す
```

移動範囲探索で親ノードを保持している場合は、それを使って経路復元する。

---

## 22. 敵移動処理の変更

変更前:

```gdscript
unit_manager.move_unit_to_cell(enemy, target_cell)
```

変更後:

```gdscript
var path = pathfinding.find_path(enemy, target_cell)
await unit_mover.move_unit_along_path(enemy, path)
unit_manager.sync_unit_grid_position(enemy, target_cell)
```

または、`UnitMover` 内で `UnitManager` の占有情報更新まで行ってもよい。

ただし、責務は以下のように整理する。

```text
UnitMover:
  見た目の移動アニメーション

UnitManager:
  グリッド座標とoccupied_unitの更新

Pathfinding:
  経路計算
```

---

## 23. 移動アニメーションの仕様

最初はシンプルでよい。

仕様:

```text
1マス移動あたり 0.15〜0.25秒
高低差がある場合は、少し山なりに移動
移動中は向きを進行方向へ変える
移動完了後に最終座標へスナップする
```

疑似コード:

```gdscript
func animate_step(unit: BattleUnit, from_pos: Vector3, to_pos: Vector3) -> void:
    var t = 0.0
    while t < 1.0:
        t += delta / move_duration
        var pos = from_pos.lerp(to_pos, t)
        pos.y += sin(t * PI) * jump_arc_height
        unit.global_position = pos
        await get_tree().process_frame

    unit.global_position = to_pos
```

---

## 24. 敵ターン中の入力制御

敵の移動アニメーション中は、プレイヤー操作を受け付けない。

既存の `ENEMY_PROCESSING` または `TurnPhase.ENEMY_TURN` を利用する。

敵移動中に以下が起きないこと。

* カーソル選択
* ユニット選択
* 攻撃対象選択
* 行動メニュー表示
* ターンが先に進む

---

# 新規追加ファイル

## 25. 追加ファイル一覧

今回、以下を追加する。

```text
res://scripts/battle/ThreatSystem.gd
res://scripts/battle/ThreatArrowManager.gd
res://scripts/ui/CombatConfirmPanel.gd
res://scripts/unit/UnitMover.gd
```

既存構成によっては `UnitMover.gd` は `UnitManager.gd` に統合してもよいが、
味方・敵の移動演出を共通化するため、分離を推奨する。

---

# 既存ファイルの変更対象

## 26. 主な変更ファイル

以下を修正する。

```text
res://scripts/battle/BattleCursor.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/Pathfinding.gd
res://scripts/unit/UnitManager.gd
res://scripts/unit/BattleUnit.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/ActionMenu.gd
res://scripts/Main.gd
```

---

# 推奨ノード構成

## 27. Main.tscn の拡張

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── UnitMover
├── BattleCursor
├── Pathfinding
├── AttackSystem
├── LineOfSight
├── ThreatSystem
├── ThreatArrowManager
├── EnemyAI
├── TurnManager
├── StageManager
├── CameraController
└── UI
    ├── BattleHUD
    ├── ActionMenu
    ├── UnitInfoPanel
    ├── BattleLog
    ├── MissionUI
    ├── BattleMessage
    └── CombatConfirmPanel
        ├── AttackerLabel
        ├── TargetLabel
        ├── DamageLabel
        ├── HitRateLabel
        ├── TerrainLabel
        ├── DirectionLabel
        ├── ConfirmButton
        └── CancelButton
```

---

# 完了条件

## 28. 今回の完了条件

以下がすべて動作すれば完了。

1. 味方ユニット選択時、移動可能範囲が表示される
2. 安全な移動可能マスは青で表示される
3. 敵から攻撃される可能性がある移動可能マスは紫で表示される
4. 紫マス判定には敵の射程・高低差・射線・地形が反映される
5. 紫マスへ移動すると、攻撃可能な敵から味方へ赤色の矢印が表示される
6. 複数の敵から攻撃される場合、複数の矢印が表示される
7. 移動後キャンセルや行動確定時に矢印が消える
8. 攻撃可能範囲から敵を選択しても即攻撃されない
9. 敵選択後、CombatConfirmPanel が表示される
10. CombatConfirmPanel に命中率・予想ダメージ・HP変化が表示される
11. CombatConfirmPanel の決定で攻撃が実行される
12. CombatConfirmPanel のキャンセルで攻撃対象選択へ戻る
13. 攻撃キャンセル時、HP減少や行動済み化が発生しない
14. 敵ユニットの移動が瞬間移動ではなくアニメーションで表示される
15. 敵移動中はプレイヤー入力が無効になる
16. 敵移動後に攻撃可能なら既存どおり攻撃する
17. 既存の移動・攻撃・命中・射線・地形・勝敗判定が壊れていない

---

# 今回は実装しないもの

## 29. 今回不要なもの

以下は今回実装しない。

* Phase 8のジョブ
* スキル
* 魔法
* 反撃
* 被攻撃予測の詳細ダメージ表示
* 敵の次ターン行動完全予測
* 矢印の豪華なエフェクト
* カットイン
* 攻撃アニメーション
* ダメージポップアップ
* スマホ操作
* セーブロード

---

# 実装時の注意

## 30. 注意事項

* Phase 8には進まず、既存戦闘の品質改善に集中する
* ThreatSystem は実際の攻撃処理を行わない
* ThreatSystem は AttackSystem の攻撃可能判定を再利用する
* 仮想位置判定でユニットやGridCellの実状態を壊さない
* 紫マス判定と実際の敵攻撃判定が大きくズレないようにする
* CombatConfirmPanel は最終確認UIとして扱う
* 攻撃対象選択中の軽い予測UIと、攻撃確定前の確認UIを混同しない
* 敵移動アニメーション中は必ず入力を止める
* UnitMover は味方・敵どちらにも使える設計にする
* 既存のキャンセル処理を壊さない
* 移動後キャンセル時に ThreatArrow が残らないようにする

---

# 実装後に提示してほしい内容

## 31. 実装後の説明項目

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* ThreatSystem の仕様
* 紫マス判定の流れ
* ThreatArrowManager の仕様
* CombatConfirmPanel の仕様
* 攻撃確定までの新しい処理フロー
* 攻撃キャンセル時の処理
* UnitMover の仕様
* 敵移動アニメーションの流れ
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

Phase 8へ進む前の改善として、既存のSRPG戦闘システムに対して以下を実装してください。

* 移動可能範囲の危険マス表示
* 安全マスは青
* 敵から攻撃される可能性があるマスは紫
* 紫マスへ移動した時、攻撃可能な敵から味方へ赤色の放物線矢印を表示
* 攻撃対象選択後、即攻撃ではなく CombatConfirmPanel を表示
* CombatConfirmPanel で命中率・予想ダメージ・HP変化を確認
* 決定で攻撃実行
* キャンセルで攻撃対象選択へ戻る
* 敵ユニットの移動を瞬間移動ではなくアニメーション化

ジョブ・スキル・魔法はまだ追加しないでください。
今回は、SRPGとしての判断しやすさと操作感を改善することを目的にしてください。
