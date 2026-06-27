# Godot SRPGプロトタイプ Phase 3 開発指示書

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
* 味方ユニットのみ選択可能
* 敵ユニットは選択不可
* 複数ユニット管理
* 行動済み状態
* 行動済みユニットの見た目変更
* 味方全員行動済みで敵ターンへ移行
* 敵ターンの仮処理
* 敵ターン後に次の味方ターンへ戻る
* ターン数とフェーズのUI表示

---

## 今回の目的

Phase 3 では、SRPGとして最低限必要な **行動メニュー・HP・通常攻撃・撃破処理** を実装する。

今回の目標は、以下の流れを成立させること。

```text
味方ユニットを選択
↓
移動可能範囲を表示
↓
移動先を選択
↓
行動メニューを表示
↓
「攻撃」または「待機」を選択
↓
攻撃を選んだ場合、攻撃範囲を表示
↓
攻撃対象を選択
↓
ダメージを与える
↓
HPが0以下なら撃破
↓
ユニットを行動済みにする
↓
次のユニットへ
```

今回も、スキル・魔法・詳細なダメージ計算・敵AIの本格実装はまだ不要。
まずは **SRPGの通常攻撃が成立する状態** を作る。

---

## 今回追加する主な機能

* ユニットにHPと攻撃力を追加する
* 行動メニューを追加する
* 「攻撃」「待機」を選べるようにする
* 攻撃範囲を表示する
* 攻撃対象を選択できるようにする
* 通常攻撃でダメージを与える
* HPが0以下になったユニットを撃破扱いにする
* 撃破されたユニットをマップから除去する
* 敵ターンで簡易攻撃処理を行う

---

## 1. ユニットステータスの追加

`BattleUnit.gd` に以下のステータスを追加する。

```gdscript
var max_hp: int = 100
var hp: int = 100
var attack_power: int = 30
var defense: int = 5
var attack_range: int = 1
var is_dead: bool = false
```

ユニットごとの初期値例:

```gdscript
# 味方
Vain:
  max_hp = 120
  attack_power = 30
  defense = 8
  attack_range = 1

Acrea:
  max_hp = 90
  attack_power = 24
  defense = 5
  attack_range = 1

Glen:
  max_hp = 110
  attack_power = 28
  defense = 7
  attack_range = 1

# 敵
Bandit_A:
  max_hp = 80
  attack_power = 22
  defense = 4
  attack_range = 1

Bandit_B:
  max_hp = 80
  attack_power = 22
  defense = 4
  attack_range = 1
```

`hp` は初期化時に `max_hp` と同じ値にする。

---

## 2. BattleUnit に追加するメソッド

`BattleUnit.gd` に以下のメソッドを追加する。

```gdscript
func take_damage(amount: int) -> void:
    hp -= amount
    if hp <= 0:
        hp = 0
        die()
    update_visual_state()

func die() -> void:
    is_dead = true
    visible = false
    # 実際のoccupied_unit解除やユニット一覧からの除外はUnitManager側で行う

func is_alive() -> bool:
    return not is_dead and hp > 0
```

`update_visual_state()` では以下も反映する。

* 行動済みなら暗くする
* 死亡済みなら非表示
* HPが少ない場合の表現はまだ不要

---

## 3. 行動メニューの追加

ユニットが移動した後、すぐ行動済みにするのではなく、
行動メニューを表示するように変更する。

行動メニューには最低限以下を表示する。

```text
攻撃
待機
```

Godotの簡易UIでよい。

例:

```text
UI
└── ActionMenu
    ├── AttackButton
    └── WaitButton
```

または `VBoxContainer + Button` でよい。

---

## 4. 行動メニューの動作

### 攻撃

「攻撃」を選択した場合:

1. 行動メニューを閉じる
2. 攻撃範囲を表示する
3. 攻撃対象選択モードに入る
4. 対象を選択したら通常攻撃を実行する
5. 攻撃後、そのユニットを行動済みにする

### 待機

「待機」を選択した場合:

1. 行動メニューを閉じる
2. 選択中ユニットを行動済みにする
3. 選択状態を解除する
4. 味方全員行動済みなら敵ターンへ移行する

---

## 5. BattleCursor の状態管理

`BattleCursor.gd` に状態管理を導入する。

例:

```gdscript
enum CursorMode {
    IDLE,
    UNIT_SELECTED,
    MOVING,
    ACTION_MENU,
    ATTACK_TARGETING
}

var current_mode: CursorMode = CursorMode.IDLE
```

各モードの役割:

### IDLE

* ユニット未選択状態
* 味方ユニットを選択できる

### UNIT_SELECTED

* ユニット選択済み
* 移動可能範囲を表示する
* 移動先を選択できる

### ACTION_MENU

* 移動後に行動メニュー表示中
* カーソル操作は制限してよい

### ATTACK_TARGETING

* 攻撃範囲を表示
* 攻撃対象を選択できる
* 範囲外や味方は対象外

---

## 6. 移動後の処理変更

Phase 2では移動後に即行動済みとしていたが、Phase 3では変更する。

変更前:

```gdscript
unit.has_moved = true
unit.has_acted = true
```

変更後:

```gdscript
unit.has_moved = true
show_action_menu(unit)
```

つまり、移動後に「攻撃」か「待機」を選べるようにする。

ただし、今回は移動前攻撃はまだ不要。
ユニットは必ず「移動 → 行動メニュー」の流れでよい。

---

## 7. 攻撃範囲計算

通常攻撃の範囲は、最初はマンハッタン距離で計算する。

```gdscript
distance = abs(from_x - target_x) + abs(from_z - target_z)
```

`distance <= attack_range` のマスを攻撃範囲とする。

今回は `attack_range = 1` の近接攻撃だけでよい。
高低差については、以下の簡易ルールを入れる。

```text
攻撃者と対象の高さ差が 1 以内なら攻撃可能
高さ差が 2 以上なら攻撃不可
```

将来的に弓や魔法の射程・射線判定を追加するため、攻撃範囲計算は別関数に分ける。

---

## 8. AttackSystem の追加

攻撃処理を `BattleCursor` や `BattleUnit` に直接書きすぎないよう、
`AttackSystem.gd` を追加する。

追加ファイル:

```text
res://scripts/battle/AttackSystem.gd
```

責務:

* 攻撃可能範囲の計算
* 攻撃対象として有効か判定
* ダメージ計算
* 攻撃実行
* 撃破判定

想定メソッド:

```gdscript
func get_attackable_cells(attacker: BattleUnit) -> Array:
    # 攻撃可能なGridCell一覧を返す

func can_attack(attacker: BattleUnit, target: BattleUnit) -> bool:
    # 射程、チーム、高低差、生存状態を判定する

func calculate_damage(attacker: BattleUnit, target: BattleUnit) -> int:
    # 仮のダメージ計算

func execute_attack(attacker: BattleUnit, target: BattleUnit) -> void:
    # ダメージを与え、必要なら撃破処理を行う
```

---

## 9. ダメージ計算

今回は簡易計算でよい。

```gdscript
damage = max(1, attacker.attack_power - target.defense)
```

例:

```text
攻撃力30、防御8
=> 22ダメージ
```

会心、命中、回避、属性、向き補正はまだ不要。

---

## 10. 攻撃対象の条件

攻撃対象として選べるのは以下。

### 味方ターン中

* `team == "enemy"` のユニット
* 生存している
* 攻撃範囲内
* 高低差条件を満たす

### 敵ターン中

* `team == "player"` のユニット
* 生存している
* 攻撃範囲内
* 高低差条件を満たす

味方を攻撃する処理は不要。
敵同士の攻撃も不要。

---

## 11. 撃破処理

ユニットのHPが0になったら撃破扱いにする。

撃破時に行うこと:

* `is_dead = true`
* ユニットを非表示にする
* GridCell の `occupied_unit` を解除する
* UnitManager の生存ユニット判定から除外する

必要であれば、UnitManager に以下を追加する。

```gdscript
func remove_unit(unit: BattleUnit) -> void:
    grid_system.clear_occupied_unit(unit.grid_x, unit.grid_z)
    unit.is_dead = true
    unit.visible = false
```

または、配列から完全に削除せず、`is_dead` で判定してもよい。
今回は後から戦闘ログなどに使えるため、配列には残して `is_dead` で除外する方式でもよい。

---

## 12. HP表示

最低限、選択中ユニットまたはカーソル上のユニットのHPが分かるようにする。

簡易UIでよい。

表示例:

```text
Vain HP: 120 / 120
Bandit_A HP: 58 / 80
```

実装候補:

* 画面左下に `UnitInfoPanel` を表示
* カーソルが乗っているユニットのHPを表示
* 選択中ユニットのHPを表示

まずは `Label` でよい。

追加ファイル例:

```text
res://scripts/ui/UnitInfoPanel.gd
```

---

## 13. 攻撃範囲ハイライト

既存の移動範囲ハイライトとは別に、攻撃範囲ハイライトを追加する。

色や見た目は仮でよい。

例:

* 移動範囲: 青系
* 攻撃範囲: 赤系
* カーソル: 黄色系

既存のハイライト管理がある場合は、以下のような関数を追加する。

```gdscript
func show_move_range(cells: Array) -> void
func show_attack_range(cells: Array) -> void
func clear_highlights() -> void
```

---

## 14. 敵ターンの簡易攻撃処理

Phase 2では敵ターンは何もしない仮処理だったが、Phase 3では簡易的に攻撃だけ行う。

敵ターンの流れ:

1. 敵ユニットを順番に処理する
2. 生存していない敵はスキップ
3. 攻撃範囲内に味方ユニットがいるか探す
4. 見つかった場合、その味方を攻撃する
5. 見つからなければ何もしない
6. 全敵ユニットの処理後、味方ターンへ戻す

今回は敵移動AIはまだ不要。

疑似コード:

```gdscript
func process_enemy_turn() -> void:
    for enemy in unit_manager.get_alive_enemy_units():
        var target = find_attackable_player_unit(enemy)
        if target != null:
            attack_system.execute_attack(enemy, target)
        await get_tree().create_timer(0.5).timeout

    unit_manager.reset_player_units_action_state()
    turn_count += 1
    current_phase = TurnPhase.PLAYER_TURN
```

---

## 15. 勝利・敗北判定

最低限、以下の判定を追加する。

### 勝利

敵ユニットが全員撃破されたら勝利。

```text
Victory
```

と表示する。

### 敗北

味方ユニットが全員撃破されたら敗北。

```text
Defeat
```

と表示する。

追加ファイル候補:

```text
res://scripts/battle/BattleResultManager.gd
```

ただし、今回は `TurnManager` または `UnitManager` 内の簡易判定でもよい。
後で分離できるように関数化する。

想定メソッド:

```gdscript
func are_all_enemies_defeated() -> bool
func are_all_players_defeated() -> bool
func check_battle_result() -> void
```

---

## 16. UI表示の追加

既存の `BattleHUD` に以下を追加する。

### 表示内容

```text
Turn 1
Player Turn

Selected: Vain
HP: 120 / 120
```

攻撃対象にカーソルを合わせた場合:

```text
Target: Bandit_A
HP: 58 / 80
Expected Damage: 22
```

最初は簡易表示でよい。
ダメージ予測は可能なら実装する。難しければPhase 4に回してよい。

---

## 17. 新規追加ファイル

以下を追加する。

```text
res://scripts/battle/AttackSystem.gd
res://scripts/ui/ActionMenu.gd
res://scripts/ui/UnitInfoPanel.gd
```

必要であれば以下も追加する。

```text
res://scripts/battle/BattleResultManager.gd
```

---

## 18. 既存ファイルの主な変更対象

以下の既存ファイルを拡張する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/TurnManager.gd
res://scripts/battle/Pathfinding.gd
res://scripts/grid/GridSystem.gd
res://scripts/ui/BattleHUD.gd
res://scripts/Main.gd
```

---

## 19. 推奨ノード構成

既存の `Main.tscn` を以下のように拡張する。

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── BattleCursor
├── Pathfinding
├── AttackSystem
├── TurnManager
├── CameraController
└── UI
    ├── BattleHUD
    │   └── TurnLabel
    ├── ActionMenu
    │   ├── AttackButton
    │   └── WaitButton
    └── UnitInfoPanel
        └── UnitInfoLabel
```

---

## 20. 今回の完了条件

以下がすべて動作すれば完了。

1. 各ユニットにHPが設定されている
2. 各ユニットに攻撃力・防御力・攻撃射程が設定されている
3. 味方ユニットを選択して移動できる
4. 移動後、行動メニューが表示される
5. 行動メニューに「攻撃」「待機」が表示される
6. 「待機」を選ぶと行動済みになる
7. 「攻撃」を選ぶと攻撃範囲が表示される
8. 攻撃範囲内の敵ユニットを選択できる
9. 攻撃範囲外の敵ユニットは攻撃できない
10. 味方ユニットを攻撃対象にできない
11. 攻撃すると敵のHPが減る
12. HPが0以下になった敵は撃破される
13. 撃破された敵のマスは移動可能になる
14. 敵が全員撃破されたらVictory表示になる
15. 敵ターンでは、攻撃範囲内に味方がいれば簡易攻撃する
16. 味方が全員撃破されたらDefeat表示になる
17. 現在ターン、フェーズ、選択中ユニット、HPがUIで分かる
18. 既存の移動範囲・高低差移動・ターン進行が壊れていない

---

## 21. 今回はまだ実装しないもの

以下はPhase 3では実装しない。

* 本格的な敵AI
* 敵の移動
* スキル
* 魔法
* 属性
* 命中率
* 回避率
* 会心
* 方向補正
* 側面攻撃
* 背面攻撃
* 弓や魔法の射線判定
* 範囲攻撃
* 回復
* 状態異常
* 装備
* ジョブ
* レベルアップ
* 経験値
* アニメーション
* 攻撃エフェクト
* ダメージポップアップ
* 会話イベント
* ステージクリア演出
* セーブ/ロード
* スマホ操作

---

## 22. 実装時の注意

* 既存の移動処理とターン処理を壊さない
* 移動後すぐ行動済みにせず、行動メニューを挟む
* 攻撃処理は `AttackSystem` に分離する
* HPや死亡状態は `BattleUnit` に持たせる
* ユニット一覧や占有マス解除は `UnitManager` が管理する
* グリッドの `occupied_unit` を必ず正しく更新する
* 攻撃範囲ハイライトと移動範囲ハイライトを混同しない
* 敵ターン処理は後からAIを追加しやすいように関数化する
* Victory / Defeat 判定は攻撃後と敵ターン後に必ず行う
* 今回はシンプルに動くことを優先し、演出は最小限でよい

---

## 23. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* 主要クラスの役割
* 行動メニューの処理フロー
* 攻撃処理の流れ
* HP・撃破処理の流れ
* 敵ターンの簡易攻撃処理
* Victory / Defeat 判定の仕組み
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

## まず実装してください

既存の8×8ボクセル風SRPGマップ上で、
**味方ユニットが移動後に「攻撃」または「待機」を選択でき、攻撃範囲内の敵に通常攻撃を行い、HPを減らして撃破できる状態** を実装してください。

敵ターンでは、敵が攻撃範囲内の味方に対して簡易攻撃できるようにしてください。

攻撃エフェクト、アニメーション、スキル、魔法、敵移動AIはまだ不要です。
まずはSRPGの基本となる **行動メニュー・通常攻撃・HP・撃破・勝敗判定** を完成させてください。
