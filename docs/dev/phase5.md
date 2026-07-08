# Godot SRPGプロトタイプ Phase 5 開発指示書

## 前提

Godot 4.x / GDScript で、ボクセル風の立体マップ上で展開するSRPGプロトタイプを開発している。

すでに以下は実装済み。

### Phase 1 実装済み

* 8×8のボクセル風SRPGマップ表示
* 斜め見下ろしカメラ
* SRPG用グリッド
* ユニット配置
* カーソル操作
* ユニット選択
* 移動可能範囲表示
* 高低差を考慮した移動
* 通行不可マス判定
* 選択したマスへのユニット移動

### Phase 2 実装済み

* 味方ユニット3体
* 敵ユニット2体
* 複数ユニット管理
* 行動済み状態
* ターン制
* 敵ターンの処理
* ターン数とフェーズのUI表示

### Phase 3 実装済み

* HP
* 攻撃力
* 防御力
* 攻撃射程
* 行動メニュー
* 攻撃
* 待機
* 通常攻撃
* HP減少
* 撃破処理
* Victory / Defeat 判定
* HP表示

### Phase 4 実装済み

* 敵移動AI
* 敵の移動後攻撃
* 味方行動キャンセル
* 移動後キャンセル
* 攻撃対象選択キャンセル
* ダメージ予測UI
* 攻撃対象ハイライト
* 勝敗後の入力停止

---

## 今回の目的

Phase 5 では、SRPGらしい戦術性を高めるために、
**射程武器・高低差補正・命中率・回避率・戦闘予測UI** を追加する。

これにより、単純な隣接攻撃だけではなく、
高台からの攻撃、遠距離攻撃、命中率を考慮した攻撃判断ができるようにする。

今回のゴールは、以下のような戦闘判断が成立する状態にすること。

```text
高台にいる弓ユニットは射程が伸びる
低所から高所への攻撃は命中率が下がる
敵の回避力によって命中率が変わる
攻撃前に命中率・予想ダメージ・撃破可能かが分かる
攻撃が外れることがある
```

---

## 今回追加する主な機能

* ユニットに命中・回避ステータスを追加
* ユニットに攻撃種別を追加
* 近接攻撃と遠距離攻撃を区別する
* 高低差による射程補正
* 高低差による命中補正
* 命中判定
* Miss表示
* 戦闘予測UIの拡張
* 弓系ユニットの仮実装
* 敵AIが射程と命中を考慮して攻撃する

---

## 1. ユニットステータスの追加

`BattleUnit.gd` に以下を追加する。

```gdscript
enum AttackType {
    MELEE,
    RANGED
}

var attack_type: AttackType = AttackType.MELEE

var accuracy: int = 90
var evasion: int = 10

var min_attack_range: int = 1
var max_attack_range: int = 1
```

既存の `attack_range` がある場合は、以下のどちらかに整理する。

### 推奨

`attack_range` を廃止し、以下に統一する。

```gdscript
var min_attack_range: int = 1
var max_attack_range: int = 1
```

近接ユニット:

```gdscript
min_attack_range = 1
max_attack_range = 1
attack_type = AttackType.MELEE
```

弓ユニット:

```gdscript
min_attack_range = 2
max_attack_range = 3
attack_type = AttackType.RANGED
```

---

## 2. ユニット初期値の調整

既存ユニットの初期値を以下のようにする。

```text
Vain:
  max_hp = 120
  attack_power = 30
  defense = 8
  accuracy = 90
  evasion = 10
  attack_type = MELEE
  min_attack_range = 1
  max_attack_range = 1

Acrea:
  max_hp = 90
  attack_power = 24
  defense = 5
  accuracy = 92
  evasion = 15
  attack_type = MELEE
  min_attack_range = 1
  max_attack_range = 1

Glen:
  max_hp = 100
  attack_power = 22
  defense = 5
  accuracy = 85
  evasion = 12
  attack_type = RANGED
  min_attack_range = 2
  max_attack_range = 3

Bandit_A:
  max_hp = 80
  attack_power = 22
  defense = 4
  accuracy = 85
  evasion = 8
  attack_type = MELEE
  min_attack_range = 1
  max_attack_range = 1

Bandit_B:
  max_hp = 70
  attack_power = 18
  defense = 3
  accuracy = 80
  evasion = 10
  attack_type = RANGED
  min_attack_range = 2
  max_attack_range = 3
```

Glen と Bandit_B を弓ユニットとして扱う。

見た目は仮でよいが、弓ユニットは近接ユニットと少し色を変える。

---

## 3. 攻撃範囲計算の変更

`AttackSystem.gd` の攻撃範囲計算を、
`min_attack_range` と `max_attack_range` に対応させる。

マンハッタン距離を使う。

```gdscript
var distance = abs(from_x - target_x) + abs(from_z - target_z)
```

攻撃可能条件:

```gdscript
distance >= attacker.min_attack_range
distance <= attacker.max_attack_range
```

近接攻撃:

```text
距離1のみ攻撃可能
```

弓攻撃:

```text
距離2〜3を攻撃可能
隣接距離1には攻撃不可
```

---

## 4. 高低差による射程補正

遠距離攻撃の場合、高低差によって射程を補正する。

ルール:

```text
攻撃者が対象より高い位置にいる:
  高さ差1ごとに最大射程 +1
  ただし最大補正は +2 まで

攻撃者が対象より低い位置にいる:
  高さ差1ごとに最大射程 -1
  ただし最低射程は min_attack_range 未満にならない
```

例:

```text
弓ユニットの基本射程: 2〜3

高さ差 +1:
  射程 2〜4

高さ差 +2:
  射程 2〜5

高さ差 -1:
  射程 2〜2

高さ差 -2:
  射程 2〜2
```

近接攻撃は、今回のPhase 5では射程補正なしでよい。

---

## 5. 高低差による攻撃可否

近接攻撃は、Phase 4までと同様に以下を維持する。

```text
高さ差が1以内なら攻撃可能
高さ差が2以上なら攻撃不可
```

遠距離攻撃は、以下とする。

```text
高さ差が3以内なら攻撃可能
高さ差が4以上なら攻撃不可
```

これは仮ルールでよい。
将来的に射線判定を入れるまでは、高低差のみで判定する。

---

## 6. 命中率計算

`AttackSystem.gd` に命中率計算を追加する。

想定メソッド:

```gdscript
func calculate_hit_rate(attacker: BattleUnit, target: BattleUnit) -> int:
    var hit_rate = attacker.accuracy - target.evasion
    # 高低差補正を加える
    return clamp(hit_rate, 5, 100)
```

基本式:

```text
命中率 = 攻撃者 accuracy - 対象 evasion + 高低差補正
```

高低差補正:

```text
攻撃者が対象より高い:
  高さ差1ごとに命中率 +5%
  最大 +15%

攻撃者が対象より低い:
  高さ差1ごとに命中率 -7%
  最大 -21%
```

最終的な命中率は以下に収める。

```text
最低 5%
最高 100%
```

---

## 7. 命中判定

`AttackSystem.execute_attack()` を修正する。

処理順:

```text
1. 攻撃可能か確認
2. 命中率を計算
3. 乱数で命中判定
4. 命中した場合、ダメージ計算
5. 対象にダメージ
6. 外れた場合、Missとして処理
7. 撃破判定
8. 戦闘ログを更新
```

疑似コード:

```gdscript
func execute_attack(attacker: BattleUnit, target: BattleUnit) -> Dictionary:
    if not can_attack(attacker, target):
        return {
            "success": false,
            "hit": false,
            "damage": 0,
            "message": "Cannot attack"
        }

    var hit_rate = calculate_hit_rate(attacker, target)
    var roll = randi_range(1, 100)
    var is_hit = roll <= hit_rate

    if not is_hit:
        return {
            "success": true,
            "hit": false,
            "damage": 0,
            "message": "Miss"
        }

    var damage = calculate_damage(attacker, target)
    target.take_damage(damage)

    return {
        "success": true,
        "hit": true,
        "damage": damage,
        "message": "Hit"
    }
```

戻り値をDictionaryにすることで、UIやログに反映しやすくする。

---

## 8. ダメージ計算

Phase 3の計算を維持する。

```gdscript
damage = max(1, attacker.attack_power - target.defense)
```

ただし、今回は高低差によるダメージ補正は入れない。

命中率と射程補正だけに絞る。

---

## 9. 戦闘予測UIの拡張

攻撃対象選択中、以下を表示する。

```text
Attacker: Glen
Target: Bandit_A

Damage: 18
Hit Rate: 82%
Target HP: 80 / 80
After HP: 62 / 80
Range: 2 - 4
Height Diff: +1
```

近接ユニットの場合:

```text
Attacker: Vain
Target: Bandit_A

Damage: 26
Hit Rate: 87%
Target HP: 80 / 80
After HP: 54 / 80
Range: 1
Height Diff: 0
```

`BattleHUD` または `UnitInfoPanel` を拡張する。

想定メソッド:

```gdscript
func show_battle_preview(attacker: BattleUnit, target: BattleUnit, preview: Dictionary) -> void
func clear_battle_preview() -> void
```

previewには以下を含める。

```gdscript
{
    "damage": 22,
    "hit_rate": 87,
    "target_hp": 80,
    "after_hp": 58,
    "height_diff": 1,
    "min_range": 2,
    "max_range": 4
}
```

---

## 10. 戦闘ログの追加

簡易的な戦闘ログを追加する。

表示例:

```text
Glen attacks Bandit_A
Hit! 18 damage
```

Missの場合:

```text
Bandit_B attacks Acrea
Miss!
```

撃破時:

```text
Vain attacks Bandit_A
Hit! 26 damage
Bandit_A defeated
```

追加ファイル候補:

```text
res://scripts/ui/BattleLog.gd
```

ノード例:

```text
UI
└── BattleLog
    └── BattleLogLabel
```

最初は直近1〜3行だけ表示できればよい。

---

## 11. 攻撃結果表示

攻撃実行後、`AttackSystem.execute_attack()` の戻り値を使ってUIを更新する。

```gdscript
var result = attack_system.execute_attack(attacker, target)
battle_log.show_attack_result(attacker, target, result)
```

攻撃結果として最低限以下が分かるようにする。

* 誰が攻撃したか
* 誰を攻撃したか
* 命中したか
* 何ダメージか
* 撃破したか

---

## 12. 敵AIの調整

`EnemyAI.gd` を Phase 5 の射程ルールに対応させる。

敵AIは以下を考慮する。

* 近接ユニットは隣接を狙う
* 遠距離ユニットは `min_attack_range` 〜 `max_attack_range` を維持する
* 弓ユニットはできれば隣接しない
* 攻撃可能な対象がいる場合は攻撃する
* 複数対象がいる場合は、命中率が高い対象を優先する
* 同命中率ならHPが低い対象を優先する

優先順位:

```text
1. 攻撃可能な対象を探す
2. 命中率が高い対象を優先
3. 同じ命中率ならHPが低い対象を優先
4. 攻撃できない場合は、攻撃可能位置へ移動
5. 遠距離ユニットは隣接しすぎない位置を優先
6. 何もできなければ最も近い敵へ近づく
```

---

## 13. 攻撃可能位置の探索修正

Phase 4の `find_best_move_cell_for_attack()` を、
`min_attack_range` と `max_attack_range` に対応させる。

遠距離ユニットの場合、以下を優先する。

```text
対象との距離が min_attack_range 以上
対象との距離が補正後 max_attack_range 以下
対象と隣接しない
攻撃命中率が高い
```

近接ユニットの場合はこれまで通り、隣接できる場所を探す。

---

## 14. ハイライト表示の改善

攻撃範囲ハイライトを、近接・遠距離に対応させる。

* 近接ユニット: 隣接マスを赤く表示
* 弓ユニット: 距離2〜3のマスを赤く表示
* 高所にいる場合: 補正後の射程を表示
* 攻撃不可の隣接マスは表示しない

ハイライト生成も `AttackSystem.get_attackable_cells()` を使用する。

---

## 15. 入力とキャンセル処理の維持

Phase 4で実装した以下のキャンセル処理は壊さない。

* ユニット選択キャンセル
* 移動後キャンセル
* 攻撃対象選択キャンセル
* 行動メニューのキャンセル
* Victory / Defeat 後の入力停止

特に、攻撃対象選択中のキャンセルで、
戦闘予測UIと攻撃範囲ハイライトを正しく消すこと。

---

## 16. 新規追加ファイル

以下を追加する。

```text
res://scripts/ui/BattleLog.gd
```

必要に応じて既存の `BattleHUD.gd`、`UnitInfoPanel.gd` を拡張する。

---

## 17. 既存ファイルの主な変更対象

以下を拡張する。

```text
res://scripts/unit/BattleUnit.gd
res://scripts/unit/UnitManager.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/BattleCursor.gd
res://scripts/battle/TurnManager.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/Main.gd
```

---

## 18. 推奨ノード構成

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
    ├── ActionMenu
    ├── UnitInfoPanel
    └── BattleLog
        └── BattleLogLabel
```

---

## 19. 今回の完了条件

以下がすべて動作すれば完了。

1. ユニットに accuracy と evasion が追加されている
2. ユニットに attack_type が追加されている
3. min_attack_range / max_attack_range で攻撃範囲を管理している
4. 近接ユニットは距離1のみ攻撃できる
5. 弓ユニットは距離2〜3を攻撃できる
6. 弓ユニットは隣接距離1に攻撃できない
7. 高所からの遠距離攻撃で最大射程が伸びる
8. 低所からの遠距離攻撃で最大射程が短くなる
9. 高低差によって命中率が変わる
10. 攻撃時に命中判定が行われる
11. 攻撃が外れることがある
12. Miss時はHPが減らない
13. 攻撃対象選択中に予想ダメージと命中率が表示される
14. 攻撃結果がBattleLogに表示される
15. 敵AIが近接・遠距離の射程差を考慮して行動する
16. 弓系敵ユニットが距離を取って攻撃しようとする
17. 既存の移動・攻撃・キャンセル・勝敗判定が壊れていない

---

## 20. 今回はまだ実装しないもの

以下はPhase 5では実装しない。

* 射線判定
* 障害物越しの攻撃制限
* 範囲攻撃
* 魔法
* スキル
* 回復
* 状態異常
* 属性相性
* 会心
* 背面攻撃
* 側面攻撃
* 向き
* 反撃
* 連携攻撃
* 装備
* ジョブ
* レベルアップ
* 経験値
* 攻撃アニメーション
* ダメージポップアップ
* 本格的な戦闘演出
* ステージクリア演出
* セーブ/ロード
* スマホ操作

---

## 21. 実装時の注意

* 既存のPhase 1〜4の機能を壊さない
* `attack_range` が既存にある場合は、`min_attack_range` / `max_attack_range` へ移行する
* 攻撃可能判定は `AttackSystem` に集約する
* 敵AIも必ず `AttackSystem.can_attack()` を使う
* ダメージ予測と実際の攻撃で同じ計算式を使う
* 命中率は最低5%、最高100%に丸める
* Miss時はダメージと撃破処理を行わない
* 遠距離ユニットが隣接攻撃できないことを確認する
* 高低差による射程補正は遠距離攻撃のみ適用する
* UIは仮でよいが、命中率と予想ダメージは必ず見えるようにする

---

## 22. 実装後に提示してほしい内容

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* 追加したノード構成
* BattleUnit に追加したステータス
* AttackSystem の攻撃可能判定
* 高低差による射程補正の仕様
* 命中率計算の仕様
* 攻撃実行時の処理フロー
* BattleLog の表示内容
* EnemyAI の変更点
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

## まず実装してください

既存の8×8ボクセル風SRPGマップ上で、
**近接ユニットと弓ユニットを区別し、射程・高低差・命中率を考慮した通常攻撃**を実装してください。

具体的には以下を実装してください。

* Glen を弓ユニットにする
* Bandit_B を弓ユニットにする
* 弓ユニットは距離2〜3で攻撃する
* 弓ユニットは隣接攻撃できない
* 高所からの弓攻撃は射程が伸びる
* 低所からの弓攻撃は射程が短くなる
* 高低差で命中率が変わる
* 攻撃前に予想ダメージと命中率を表示する
* 攻撃時に命中判定を行う
* Missの場合はHPを減らさない
* 攻撃結果をBattleLogに表示する

スキル、魔法、射線判定、範囲攻撃、反撃、アニメーションはまだ不要です。
まずはSRPGとしての戦術性を高めるため、
**射程・高低差・命中率・戦闘予測UI** を完成させてください。
