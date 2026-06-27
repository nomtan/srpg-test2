# Godot SRPGプロトタイプ Phase 2 開発指示書

## 前提

Godot 4.x / GDScript で、ボクセル風の立体マップ上で展開するSRPGプロトタイプを開発している。

すでに以下は実装済み。

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

今回の目的は、SRPGとしての戦闘ループの基礎を作ることである。

---

## 今回の実装目的

Phase 2 では、以下を実装する。

* 味方ユニットを複数配置する
* 敵ユニットを配置する
* ターン制の基礎を作る
* ユニットごとに行動済み状態を持たせる
* 移動後に待機できる
* 味方全員が行動済みになったら敵ターンへ移行する
* 敵ターンは仮処理で終了し、再び味方ターンへ戻す
* 現在のターン状態を画面に表示する
* 解像度1920 x 1080 フルHD

今回も攻撃処理や敵AIはまだ本格実装しない。
まずは **「複数ユニットを順番に動かせるSRPGの基本状態」** を作る。

---

## 今回追加する主な機能

### 1. 複数味方ユニット

味方ユニットを最低3体配置する。

例:

```gdscript
Vain
Acrea
Glen
```

初期配置例:

```text
Vain  : x=1, z=1
Acrea : x=2, z=1
Glen  : x=1, z=2
```

各ユニットは以下の情報を持つ。

```gdscript
var unit_id: String
var unit_name: String
var grid_x: int
var grid_z: int
var move_range: int
var jump_height: int
var team: String
var has_acted: bool
var has_moved: bool
```

---

### 2. 敵ユニットの配置

敵ユニットを最低2体配置する。

例:

```gdscript
Bandit_A
Bandit_B
```

初期配置例:

```text
Bandit_A : x=6, z=6
Bandit_B : x=5, z=6
```

敵ユニットはまだ操作不可でよい。

ただし、以下は必要。

* 敵ユニットのマスは occupied として扱う
* 味方ユニットは敵ユニットのいるマスへ移動できない
* 敵ユニットは見た目で味方と区別できるようにする

見た目は仮でよい。

例:

* 味方: 青系のCapsuleまたは簡易Mesh
* 敵: 赤系のCapsuleまたは簡易Mesh

---

## 3. ターン制の基礎

TurnManager を追加する。

ファイル例:

```text
res://scripts/battle/TurnManager.gd
```

TurnManager は以下を管理する。

```gdscript
enum TurnPhase {
    PLAYER_TURN,
    ENEMY_TURN
}

var current_phase: TurnPhase
var turn_count: int
```

初期状態:

```gdscript
current_phase = TurnPhase.PLAYER_TURN
turn_count = 1
```

---

## 4. 味方ターンのルール

味方ターンでは、プレイヤーは味方ユニットを選択できる。

ただし、以下の制約を入れる。

* `team == "player"` のユニットのみ選択可能
* `has_acted == false` のユニットのみ選択可能
* 行動済みユニットは選択できない、または選択しても移動できない
* 敵ユニットは選択対象外

味方ユニットが移動したあと、今回は自動で待機扱いにしてよい。

つまり、移動完了後に以下を設定する。

```gdscript
unit.has_moved = true
unit.has_acted = true
```

---

## 5. 行動済み表示

行動済みの味方ユニットは、見た目で分かるようにする。

簡易実装でよい。

例:

* 色を少し暗くする
* 半透明にする
* 頭上に小さなアイコンを出す
* Meshの色をグレー寄りにする

まずは色変更だけでよい。

---

## 6. 味方ターン終了判定

味方ユニット全員が `has_acted == true` になったら、自動で敵ターンへ移行する。

判定例:

```gdscript
func are_all_player_units_acted() -> bool:
    for unit in player_units:
        if not unit.has_acted:
            return false
    return true
```

味方ターン終了時:

```gdscript
current_phase = TurnPhase.ENEMY_TURN
```

---

## 7. 敵ターンの仮処理

今回は敵AIはまだ実装しない。

敵ターンに入ったら、以下の仮処理を行う。

1. 画面に「Enemy Turn」と表示する
2. 1秒程度待つ
3. 敵ユニット全員を行動済みにする、または何もしない
4. 味方ユニットの `has_acted` と `has_moved` をリセットする
5. `turn_count += 1`
6. `current_phase = TurnPhase.PLAYER_TURN`

敵ターン処理は後からAIを追加しやすい構造にする。

---

## 8. UI表示

簡易UIを追加する。

表示したい情報:

```text
Turn 1
Player Turn
```

敵ターン中は以下のように表示する。

```text
Turn 1
Enemy Turn
```

UIは仮でよい。

Godotの `Label` で画面左上に表示するだけでよい。

---

## 9. 入力制御

敵ターン中はプレイヤー操作を受け付けない。

つまり、BattleCursor などで以下を判定する。

```gdscript
if turn_manager.current_phase != TurnManager.TurnPhase.PLAYER_TURN:
    return
```

敵ターン中は以下を禁止する。

* カーソル選択
* ユニット選択
* 移動先選択
* 移動実行

ただし、カーソル移動だけは許可してもよい。
実装が簡単な方を採用してよい。

---

## 10. 既存クラスへの変更方針

### BattleUnit.gd

以下を追加する。

```gdscript
var unit_id: String
var has_acted: bool = false
var has_moved: bool = false
```

必要であれば以下のメソッドを追加する。

```gdscript
func mark_acted() -> void:
    has_acted = true
    has_moved = true
    update_visual_state()

func reset_action_state() -> void:
    has_acted = false
    has_moved = false
    update_visual_state()

func update_visual_state() -> void:
    # 行動済みかどうかで見た目を変える
```

---

### UnitManager.gd

以下の責務を追加する。

* 複数ユニット生成
* 味方ユニット一覧の管理
* 敵ユニット一覧の管理
* 全味方ユニットが行動済みか判定
* ターン開始時に味方ユニットの行動状態をリセット
* 指定座標にいるユニット取得
* teamごとのユニット取得

想定メソッド:

```gdscript
func spawn_initial_units() -> void
func get_player_units() -> Array
func get_enemy_units() -> Array
func get_unit_at(grid_x: int, grid_z: int) -> BattleUnit
func are_all_player_units_acted() -> bool
func reset_player_units_action_state() -> void
func mark_unit_acted(unit: BattleUnit) -> void
```

---

### BattleCursor.gd

以下を修正する。

* 味方ターン中のみユニット選択できる
* 行動済みユニットは移動できない
* 敵ユニットは選択できない
* 移動後、ユニットを行動済みにする
* 移動後、味方全員が行動済みか TurnManager に確認させる

---

### Pathfinding.gd

既存の移動可能範囲計算は維持する。

ただし、以下を確認する。

* 味方ユニットのいるマスには移動不可
* 敵ユニットのいるマスにも移動不可
* 選択中ユニット自身の現在地は移動範囲に含めてもよい
* occupied_unit の更新が正しく行われていること

---

### GridSystem.gd

occupied_unit の管理が正しくできるようにする。

必要であれば以下を追加する。

```gdscript
func set_occupied_unit(grid_x: int, grid_z: int, unit: BattleUnit) -> void
func clear_occupied_unit(grid_x: int, grid_z: int) -> void
func move_occupied_unit(from_x: int, from_z: int, to_x: int, to_z: int, unit: BattleUnit) -> void
```

---

## 11. 新規追加ファイル

以下を追加する。

```text
res://scripts/battle/TurnManager.gd
res://scripts/ui/BattleHUD.gd
```

必要であれば、既存の Main.gd に TurnManager と BattleHUD の初期化を追加する。

---

## 12. 推奨ノード構成

既存の Main.tscn を以下のように拡張する。

```text
Main.tscn
├── VoxelMap
├── GridSystem
├── UnitManager
├── BattleCursor
├── Pathfinding
├── TurnManager
├── CameraController
└── UI
    └── BattleHUD
        └── TurnLabel
```

---

## 13. 今回の完了条件

以下がすべて動作すれば完了。

1. 味方ユニットが3体表示される
2. 敵ユニットが2体表示される
3. 味方ユニットのみ選択できる
4. 敵ユニットは選択できない
5. 行動済みでない味方ユニットだけ移動できる
6. 移動後、そのユニットは行動済みになる
7. 行動済みユニットは見た目が変わる
8. 敵味方問わず、ユニットがいるマスには移動できない
9. 味方全員が行動済みになると敵ターンへ移行する
10. 敵ターン中はプレイヤーがユニットを動かせない
11. 敵ターンは仮処理で終了し、次の味方ターンへ戻る
12. 次の味方ターン開始時、味方ユニットの行動済み状態がリセットされる
13. 画面左上に現在ターンとフェーズが表示される

---

## 14. 今回はまだ実装しないもの

以下は今回のPhase 2では実装しない。

* 攻撃
* ダメージ
* HP
* 敵AI
* スキル
* 魔法
* 射程
* 射線
* 勝利条件
* 敗北条件
* ステータス画面
* 行動メニュー
* アイテム
* ジョブ
* アニメーション
* 会話イベント
* マップエディタ
* セーブ/ロード

---

## 15. 実装時の注意

* 既存の1体移動プロトタイプを壊さずに拡張する
* 一度に複雑な戦闘システムを入れない
* TurnManager / UnitManager / BattleCursor の責務を分ける
* ユニットの行動状態は BattleUnit が持つ
* ターン進行は TurnManager が管理する
* ユニット一覧は UnitManager が管理する
* グリッドの占有状態は GridSystem または GridCell が管理する
* 敵AIは後から追加できるよう、敵ターン処理を関数として分ける
* UIは仮でよいが、現在状態が分かるようにする
* 実装後、操作手順と確認方法を説明する

---

## 16. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* 主要クラスの役割
* ターン処理の流れ
* ユニット選択から移動完了までの流れ
* 動作確認手順
* 次に実装しやすい項目
* 現時点の制限事項

---

## まず実装してください

既存の8×8ボクセル風SRPGマップ上で、
**味方3体・敵2体を配置し、味方ユニットを順番に移動させ、全員行動済みになったら敵ターンを挟んで次の味方ターンへ戻る** ところまで実装してください。

攻撃・敵AI・HP・スキルはまだ不要です。
まずはSRPGの基本となる **複数ユニット管理とターン制の土台** を完成させてください。
