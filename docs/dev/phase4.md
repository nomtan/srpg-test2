# Godot SRPGプロトタイプ Phase 4 開発指示書

## 前提

Godot 4.x / GDScript で、ボクセル風の立体マップ上で展開するSRPGプロトタイプを開発している。

すでに以下は実装済み。

### Phase 1 実装済み

* 8×8のボクセル風SRPGマップ表示
* 斜め見下ろしカメラ
* SRPG用グリッド
* ユニット1体の配置
* カーソル操作
* ユニット選択
* 移動可能範囲の表示
* 高低差を考慮した移動
* 通行不可マスの判定
* 選択したマスへのユニット移動

### Phase 2 実装済み

* 味方ユニット3体の配置
* 敵ユニット2体の配置
* 複数ユニット管理
* 行動済み状態
* 行動済みユニットの見た目変更
* 味方全員行動済みで敵ターンへ移行
* 敵ターンの仮処理
* 敵ターン後に次の味方ターンへ戻る
* ターン数とフェーズのUI表示

### Phase 3 実装済み

* ユニットのHP
* 攻撃力
* 防御力
* 攻撃射程
* 行動メニュー
* 「攻撃」「待機」
* 攻撃範囲表示
* 通常攻撃
* HP減少
* 撃破処理
* 敵ターン中の簡易攻撃
* Victory / Defeat 判定
* 選択中ユニットやHPの簡易UI表示

---

## 今回の目的

Phase 4 では、SRPGとしての操作感と戦闘の自然さを高める。

今回の主な目的は以下。

* 敵ユニットが移動してから攻撃できるようにする
* 味方ユニットの行動キャンセルを実装する
* 移動前の位置へ戻れるようにする
* 攻撃前に予想ダメージを表示する
* 攻撃対象の選択を分かりやすくする
* 攻撃できない場合の待機処理を整理する
* ターン進行と入力状態をより安定させる

Phase 4 のゴールは、
**敵味方が同じ基本ルールで「移動 → 攻撃/待機」できるSRPGの基礎を作ること**である。

---

## 今回追加する主な機能

* 敵の簡易移動AI
* 敵の移動後攻撃
* 攻撃可能な位置への移動判断
* 味方行動時のキャンセル
* 移動後のキャンセルで元の位置へ戻る
* 攻撃対象選択中のキャンセル
* ダメージ予測UI
* 攻撃対象ハイライト
* 敵ターン中の処理順序の安定化
* BattleState / CursorMode の整理

---

## 1. 敵移動AIの追加

Phase 3では、敵ターン中に攻撃範囲内の味方がいれば攻撃するだけだった。

Phase 4では、敵が以下の行動を取れるようにする。

```text
敵ターン開始
↓
敵ユニットを順番に処理
↓
攻撃範囲内に味方がいるか確認
↓
いれば攻撃
↓
いなければ、攻撃できる位置まで移動を試みる
↓
移動後に攻撃範囲内なら攻撃
↓
攻撃できなければ待機
↓
次の敵へ
```

---

## 2. EnemyAI.gd の追加

敵AI処理を `TurnManager` や `BattleCursor` に直接書きすぎないよう、
`EnemyAI.gd` を追加する。

追加ファイル:

```text
res://scripts/battle/EnemyAI.gd
```

責務:

* 敵ユニットの行動先を決める
* 最も近い味方ユニットを探す
* 攻撃可能な対象を探す
* 攻撃できる位置を探す
* 移動先を決める
* 移動後に攻撃するか判断する

想定メソッド:

```gdscript
func process_enemy_unit(enemy: BattleUnit) -> void:
    # 敵1体分の行動を処理する

func find_nearest_player_unit(enemy: BattleUnit) -> BattleUnit:
    # 最も近い生存中の味方ユニットを返す

func find_attackable_player_unit(enemy: BattleUnit) -> BattleUnit:
    # 現在位置から攻撃可能な味方ユニットを返す

func find_best_move_cell_for_attack(enemy: BattleUnit, target: BattleUnit) -> GridCell:
    # 移動後にtargetへ攻撃できる位置を探す

func find_closest_move_cell_to_target(enemy: BattleUnit, target: BattleUnit) -> GridCell:
    # 攻撃できない場合、targetに近づく移動先を返す
```

---

## 3. 敵AIの基本方針

敵AIはまだ簡易でよい。

優先順位は以下。

```text
1. 現在位置から攻撃できる味方がいれば攻撃する
2. 攻撃できない場合、移動後に攻撃できるマスを探す
3. 移動後に攻撃できるマスがあれば、そこへ移動して攻撃する
4. 攻撃できるマスがなければ、最も近い味方へ近づく
5. 何もできなければ待機
```

---

## 4. 敵の移動範囲計算

敵も味方と同じ移動ルールを使う。

つまり、既存の `Pathfinding.gd` を再利用する。

考慮するもの:

* `move_range`
* `move_cost`
* `walkable`
* `occupied_unit`
* `jump_height`
* 高低差

ただし、敵自身の現在地は移動候補として扱ってよい。

想定メソッド:

```gdscript
func get_reachable_cells(unit: BattleUnit) -> Array:
    # 指定ユニットの移動可能マスを返す
```

すでに似た関数がある場合は、敵AIでも使えるようにする。

---

## 5. 攻撃できる位置の探し方

敵が移動後に攻撃できる位置を探す。

簡易ロジックでよい。

1. 敵の移動可能マス一覧を取得
2. 各マスから対象に攻撃できるか仮判定する
3. 攻撃できるマスの中から、対象に最も近いマスを選ぶ
4. 同距離なら移動コストが少ないマスを優先する

想定メソッド:

```gdscript
func can_attack_from_cell(attacker: BattleUnit, from_cell: GridCell, target: BattleUnit) -> bool:
    # attackerがfrom_cellにいると仮定してtargetへ攻撃可能か判定する
```

攻撃可能条件:

* マンハッタン距離が `attack_range` 以下
* 高さ差が1以内
* 対象が生存している
* 対象が敵対チームである

---

## 6. 敵の移動実行

敵が移動する場合も、味方と同じように `UnitManager` 経由で移動させる。

想定メソッド:

```gdscript
func move_unit_to_cell(unit: BattleUnit, target_cell: GridCell) -> void:
    # occupied_unitの更新とユニットの見た目移動を行う
```

すでに味方移動用のメソッドがある場合は、敵にも使えるように汎用化する。

注意:

* 移動前のGridCellの `occupied_unit` を解除する
* 移動後のGridCellに `occupied_unit` を設定する
* unit.grid_x / unit.grid_z を更新する
* 高さに応じたワールド座標へ移動する

---

## 7. 敵ターンの処理フロー変更

`TurnManager.gd` の敵ターン処理を、EnemyAIを使う形に変更する。

変更後イメージ:

```gdscript
func process_enemy_turn() -> void:
    current_phase = TurnPhase.ENEMY_TURN
    update_hud()

    for enemy in unit_manager.get_alive_enemy_units():
        if check_battle_result():
            return

        await enemy_ai.process_enemy_unit(enemy)

        if check_battle_result():
            return

        await get_tree().create_timer(0.3).timeout

    unit_manager.reset_player_units_action_state()
    turn_count += 1
    current_phase = TurnPhase.PLAYER_TURN
    update_hud()
```

敵の行動中は、プレイヤー入力を受け付けないようにする。

---

## 8. 味方の行動キャンセル

Phase 4では、味方ユニット操作中にキャンセルできるようにする。

キャンセル対象は以下。

### ユニット選択中

ユニット選択を解除する。

```text
UNIT_SELECTED
↓ キャンセル
IDLE
```

### 移動後・行動メニュー表示中

移動前の位置へ戻す。

```text
ACTION_MENU
↓ キャンセル
移動前の位置へ戻す
↓
UNIT_SELECTED
```

### 攻撃対象選択中

攻撃対象選択をやめて、行動メニューへ戻る。

```text
ATTACK_TARGETING
↓ キャンセル
ACTION_MENU
```

---

## 9. 移動前座標の保存

移動後キャンセルを実装するため、
ユニットを移動させる前の座標を保存する。

`BattleCursor.gd` に以下を追加する。

```gdscript
var selected_unit_original_x: int
var selected_unit_original_z: int
var selected_unit_moved_this_action: bool = false
```

ユニット選択時に保存する。

```gdscript
selected_unit_original_x = selected_unit.grid_x
selected_unit_original_z = selected_unit.grid_z
selected_unit_moved_this_action = false
```

移動後に以下を設定する。

```gdscript
selected_unit_moved_this_action = true
```

キャンセル時に、元の座標へ戻す。

```gdscript
if selected_unit_moved_this_action:
    unit_manager.move_unit_to_grid(selected_unit, selected_unit_original_x, selected_unit_original_z)
    selected_unit_moved_this_action = false
```

---

## 10. キャンセル入力

キャンセル入力を追加する。

推奨:

```text
右クリック
または
Escapeキー
```

GodotのInputMapに以下を追加する。

```text
cancel_action
```

割り当て:

* Escape
* Mouse Button Right

既存の入力処理に影響が出ないよう注意する。

---

## 11. 行動メニューの改善

Phase 3の行動メニューに以下を追加する。

```text
攻撃
待機
キャンセル
```

### キャンセル

行動メニューで「キャンセル」を選んだ場合、
移動前の位置へ戻ってユニット選択状態に戻る。

ただし、まだ行動済みにはしない。

```text
移動後
↓
行動メニュー
↓
キャンセル
↓
移動前の位置へ戻る
↓
再度移動先を選べる
```

---

## 12. ダメージ予測UI

攻撃対象選択中に、対象へカーソルを合わせたら予想ダメージを表示する。

表示例:

```text
Attacker: Vain
Target: Bandit_A
Damage: 22
Target HP: 58 / 80
After HP: 36 / 80
```

`BattleHUD` または `UnitInfoPanel` に表示してよい。

想定メソッド:

```gdscript
func show_damage_preview(attacker: BattleUnit, target: BattleUnit, damage: int) -> void
func clear_damage_preview() -> void
```

ダメージ計算は `AttackSystem.calculate_damage()` を使う。

---

## 13. 攻撃対象ハイライト

攻撃範囲内に敵ユニットがいる場合、対象を分かりやすくする。

簡易実装でよい。

例:

* 攻撃可能マス: 赤いハイライト
* 攻撃可能な敵ユニット: 点滅、色変更、頭上マーカー
* 現在カーソルを合わせている対象: 強調表示

まずは以下だけでもよい。

* 攻撃範囲を赤ハイライト
* カーソル上の攻撃可能対象をUIに表示

---

## 14. 攻撃対象選択中の確定処理

攻撃対象選択中に決定ボタンを押した場合:

1. カーソル上にユニットがいるか確認
2. そのユニットが敵対チームか確認
3. `AttackSystem.can_attack()` で攻撃可能か確認
4. 攻撃可能なら `AttackSystem.execute_attack()` を実行
5. 攻撃後、選択中ユニットを行動済みにする
6. ハイライトを消す
7. 行動メニューを閉じる
8. 選択状態を解除する
9. Victory / Defeat をチェックする
10. 味方全員行動済みなら敵ターンへ移行する

攻撃できない場合は何もしないか、簡易メッセージを表示する。

---

## 15. 行動後の状態整理

味方ユニットの行動終了時は、必ず以下を行う。

```gdscript
func finish_player_unit_action(unit: BattleUnit) -> void:
    unit.has_moved = true
    unit.has_acted = true
    unit.update_visual_state()

    clear_selected_unit()
    clear_highlights()
    action_menu.hide()
    battle_hud.clear_damage_preview()

    if battle_result_manager.check_battle_result():
        return

    if unit_manager.are_all_player_units_acted():
        turn_manager.start_enemy_turn()
```

既存処理が複数箇所に分散している場合は、できるだけ関数化する。

---

## 16. BattleState の追加検討

現在の `BattleCursor.CursorMode` だけで状態管理が複雑になっている場合、
`BattleState` 的な考え方を導入してもよい。

ただし、Phase 4では大規模リファクタリングは避ける。

最低限、以下の状態が明確に分かれていればよい。

```gdscript
enum CursorMode {
    IDLE,
    UNIT_SELECTED,
    ACTION_MENU,
    ATTACK_TARGETING,
    ENEMY_PROCESSING,
    BATTLE_RESULT
}
```

敵ターン処理中や勝敗決定後は、プレイヤー操作を受け付けない。

---

## 17. 勝敗決定後の入力停止

Victory / Defeat が決定したら、以降の入力を止める。

```gdscript
var is_battle_finished: bool = false
```

勝敗が決まったら:

```gdscript
is_battle_finished = true
current_mode = CursorMode.BATTLE_RESULT
```

以後、以下を禁止する。

* ユニット選択
* 移動
* 攻撃
* ターン進行
* 敵AI処理

---

## 18. UI表示の整理

Phase 4では、最低限以下が分かるようにする。

```text
Turn 2
Player Turn

Selected: Vain
HP: 98 / 120

Target: Bandit_A
HP: 58 / 80
Damage: 22
After HP: 36 / 80
```

敵ターン中は以下のように表示する。

```text
Turn 2
Enemy Turn

Enemy: Bandit_A acting...
```

勝敗決定時:

```text
Victory
```

または

```text
Defeat
```

---

## 19. 新規追加ファイル

以下を追加する。

```text
res://scripts/battle/EnemyAI.gd
```

必要に応じて以下も追加する。

```text
res://scripts/battle/BattleResultManager.gd
```

Phase 3で `BattleResultManager.gd` をすでに追加済みなら、新規追加ではなく既存を拡張する。

---

## 20. 既存ファイルの主な変更対象

以下の既存ファイルを拡張する。

```text
res://scripts/battle/TurnManager.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/Pathfinding.gd
res://scripts/unit/UnitManager.gd
res://scripts/unit/BattleUnit.gd
res://scripts/grid/GridSystem.gd
res://scripts/ui/ActionMenu.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/Main.gd
```

---

## 21. 推奨ノード構成

既存の `Main.tscn` を以下のように拡張する。

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── BattleCursor
├── Pathfinding
├── AttackSystem
├── EnemyAI
├── TurnManager
├── CameraController
└── UI
    ├── BattleHUD
    │   └── TurnLabel
    ├── ActionMenu
    │   ├── AttackButton
    │   ├── WaitButton
    │   └── CancelButton
    └── UnitInfoPanel
        └── UnitInfoLabel
```

---

## 22. 今回の完了条件

以下がすべて動作すれば完了。

1. 敵ターンで敵ユニットが行動できる
2. 敵が現在位置から攻撃可能なら攻撃する
3. 敵が攻撃できない場合、移動して攻撃を試みる
4. 敵が移動後に攻撃できる場合、移動してから攻撃する
5. 敵が攻撃できない場合、最も近い味方へ近づく
6. 敵も高低差・通行不可・占有マスを考慮して移動する
7. 敵ターン中、プレイヤーはユニットを操作できない
8. 味方ユニット選択中にキャンセルできる
9. 移動後の行動メニューでキャンセルすると、移動前の位置へ戻る
10. 攻撃対象選択中にキャンセルすると、行動メニューへ戻る
11. 行動メニューに「攻撃」「待機」「キャンセル」がある
12. 攻撃対象にカーソルを合わせると予想ダメージが表示される
13. 攻撃後、HP・撃破・Victory / Defeat 判定が正しく動く
14. Victory / Defeat 後は入力とターン進行が止まる
15. 既存の移動・攻撃・ターン制が壊れていない

---

## 23. 今回はまだ実装しないもの

以下はPhase 4では実装しない。

* 本格的な敵AI
* 複数ターゲットの高度な優先順位
* 命中率
* 回避率
* 会心
* 方向補正
* 側面攻撃
* 背面攻撃
* 弓の射線判定
* 魔法
* スキル
* 範囲攻撃
* 回復
* 状態異常
* 装備
* ジョブ
* 経験値
* レベルアップ
* アニメーション
* 攻撃エフェクト
* ダメージポップアップ
* 会話イベント
* ステージクリア演出
* セーブ/ロード
* スマホ操作
* マップエディタ

---

## 24. 実装時の注意

* 既存のPhase 1〜3の処理を壊さない
* 敵AIは `EnemyAI.gd` に分離する
* 敵の移動も味方と同じ `UnitManager` の移動処理を使う
* 移動処理は敵味方共通化する
* 攻撃処理は `AttackSystem` に集約する
* ダメージ予測も `AttackSystem.calculate_damage()` を使う
* キャンセル処理では `occupied_unit` の更新漏れに注意する
* 移動後キャンセル時、ユニット座標とGridCell占有状態を必ず戻す
* Victory / Defeat 後に敵AIやターン進行が続かないようにする
* 入力可能な状態と不可の状態を明確に分ける
* 一度に大規模リファクタリングしすぎず、既存構成を尊重して拡張する

---

## 25. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* EnemyAI の処理フロー
* 敵ターンの流れ
* 味方操作時のキャンセル処理
* 移動後キャンセル時の座標復元処理
* ダメージ予測UIの仕組み
* Victory / Defeat 後の入力停止処理
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

## まず実装してください

既存の8×8ボクセル風SRPGマップ上で、
**敵ユニットが自分のターンに移動して味方へ近づき、可能であれば通常攻撃を行う** 状態を実装してください。

あわせて、味方操作では以下を実装してください。

* ユニット選択キャンセル
* 移動後キャンセル
* 攻撃対象選択キャンセル
* 行動メニューへの「キャンセル」追加
* 攻撃前のダメージ予測表示

スキル、魔法、命中率、弓の射線、攻撃エフェクトはまだ不要です。
まずはSRPGとしての基本操作感を高めるため、
**敵移動AI・キャンセル操作・ダメージ予測** を完成させてください。
