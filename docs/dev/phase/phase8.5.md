# Godot SRPGプロトタイプ Phase 8.5 改善指示書

## 目的

Phase 8で追加したジョブ・スキル・属性システムに対して、
Phase 9へ進む前に細かい仕様修正と演出改善を行う。

今回の目的は、新しい大きなシステムを追加することではなく、
既存のスキル・UI・演出・危険表示をより分かりやすく整えることである。

主な修正内容は以下。

* MPをAP、Action Pointへ名称変更する
* 物理攻撃スキル・魔法攻撃スキルの攻撃範囲色を通常攻撃と同じ赤色に統一する
* ダメージや回復時に、対象キャラクター上から数値ログを表示する
* 敵攻撃可能領域の赤い放物線矢印を、玉を並べた点線表示に変更する

---

# 前提

以下はすでに実装済み。

* ボクセル風SRPGマップ
* 味方・敵ユニット
* ターン制
* 通常攻撃
* HP
* 命中率 / 回避率
* 地形効果
* 射線判定
* 向き補正
* 戦闘予測UI
* CombatConfirmPanel
* 敵移動AI
* 敵移動アニメーション
* ThreatSystem
* ThreatArrowManager
* SkillData
* SkillDatabase
* SkillSystem
* ElementSystem
* SkillMenu
* SkillConfirmPanel
* MPを消費するスキル
* 攻撃スキル
* 回復スキル
* 範囲スキル
* 敵AIのスキル使用
* ThreatSystemのスキル対応

---

# 今回の修正項目

## 1. MPをAPへ名称変更する

現在、スキル使用時のリソース名が `MP` になっている。

しかし、このゲームでは魔法だけでなく、
物理攻撃的な技・剣技・弓技・特殊行動もスキルとして扱うため、
`MP` ではなく `AP` に名称変更する。

APは以下の意味とする。

```text id="qolgbt"
AP = Action Point
```

APは、魔法・剣技・弓技・特殊行動など、
通常攻撃以外の行動スキルを使うための共通リソースである。

---

## 2. BattleUnit の変数名変更

`BattleUnit.gd` の以下を変更する。

変更前:

```gdscript id="kujnet"
var max_mp: int = 30
var mp: int = 30
```

変更後:

```gdscript id="hq87zp"
var max_ap: int = 30
var ap: int = 30
```

初期化時も以下に変更する。

変更前:

```gdscript id="2wkf03"
mp = max_mp
```

変更後:

```gdscript id="joyfav"
ap = max_ap
```

---

## 3. SkillData のコスト名変更

`SkillData.gd` の以下を変更する。

変更前:

```gdscript id="hilfxb"
@export var mp_cost: int = 0
```

変更後:

```gdscript id="0izgzd"
@export var ap_cost: int = 0
```

---

## 4. SkillSystem のAP対応

`SkillSystem.gd` のMP判定をAP判定へ変更する。

変更前:

```gdscript id="7b1gpn"
func can_use_skill(user: BattleUnit, skill: SkillData) -> bool:
    return user.mp >= skill.mp_cost and user.is_alive()
```

変更後:

```gdscript id="87y3fu"
func can_use_skill(user: BattleUnit, skill: SkillData) -> bool:
    return user.ap >= skill.ap_cost and user.is_alive()
```

スキル実行時の消費も変更する。

変更前:

```gdscript id="9qg7cb"
user.mp -= skill.mp_cost
```

変更後:

```gdscript id="voyeyj"
user.ap -= skill.ap_cost
```

APは0未満にならないようにする。

```gdscript id="hi6smv"
user.ap = max(0, user.ap - skill.ap_cost)
```

---

## 5. UI表示のMPをAPへ変更する

以下のUI表示をすべて `MP` から `AP` に変更する。

対象例:

```text id="lbt6a2"
BattleHUD
UnitInfoPanel
SkillMenu
SkillConfirmPanel
BattleLog
CombatConfirmPanel内にスキル情報を出している場合
```

表示例:

変更前:

```text id="3un8u9"
MP: 30 / 30
MP Cost: 8
Not enough MP
```

変更後:

```text id="cx5ra3"
AP: 30 / 30
AP Cost: 8
Not enough AP
```

---

## 6. 初期ユニット設定の名称変更

初期ユニット設定も `max_mp` から `max_ap` に変更する。

例:

```text id="9xbsva"
Vain:
  max_ap = 30

Acrea:
  max_ap = 45

Glen:
  max_ap = 25

Bandit_A:
  max_ap = 15

Bandit_B:
  max_ap = 20
```

---

## 7. 初期スキル定義の名称変更

SkillDatabase内のスキル定義も `mp_cost` から `ap_cost` に変更する。

例:

```text id="blzx75"
power_slash:
  ap_cost = 5

earth_break:
  ap_cost = 10

aqua_edge:
  ap_cost = 8

healing_water:
  ap_cost = 8

aimed_shot:
  ap_cost = 5

piercing_arrow:
  ap_cost = 9

heavy_attack:
  ap_cost = 4
```

---

## 8. ThreatSystem のAP対応

ThreatSystemで敵スキルの使用可否を判定している場合、
MPではなくAPを参照する。

変更前:

```gdscript id="a6r66l"
if enemy.mp >= skill.mp_cost:
```

変更後:

```gdscript id="9k2dt5"
if enemy.ap >= skill.ap_cost:
```

---

## 9. EnemyAI のAP対応

EnemyAIでスキル使用可否を判定している場合もAPへ変更する。

変更前:

```text id="9nwo4n"
MPが足りる場合、スキルを使う
```

変更後:

```text id="osvroy"
APが足りる場合、スキルを使う
```

処理上も `mp` / `mp_cost` 参照をすべて `ap` / `ap_cost` に置き換える。

---

# 攻撃スキル範囲色の修正

## 10. 攻撃スキルの範囲色を赤に統一する

現在、スキルで魔法攻撃や物理攻撃スキルを選択したとき、
攻撃可能領域がオレンジ色で表示されている。

これを、通常攻撃と同じ赤色に変更する。

対象となるスキル:

```text id="0f9wu0"
SkillType.ATTACK
```

攻撃スキルは、物理・魔法・属性を問わず、
攻撃可能領域として通常攻撃と同じ赤色を使う。

---

## 11. スキル範囲色の整理

スキル範囲表示の色を以下に統一する。

```text id="lmbkaj"
通常攻撃範囲:
  赤

攻撃スキル範囲:
  赤

回復スキル範囲:
  緑

範囲スキルの効果範囲:
  黄色

移動可能マス:
  青

敵から攻撃される可能性のある移動可能マス:
  紫
```

---

## 12. HighlightManager または BattleCursor の修正

既存のハイライト管理で以下のような処理がある場合、

```gdscript id="fzk6vd"
func show_skill_range(cells: Array, skill: SkillData) -> void:
    # 攻撃スキルはオレンジ
```

次のように修正する。

```gdscript id="di99s6"
func show_skill_range(cells: Array, skill: SkillData) -> void:
    if skill.skill_type == SkillData.SkillType.ATTACK:
        show_attack_highlight(cells) # 赤
    elif skill.skill_type == SkillData.SkillType.HEAL:
        show_heal_highlight(cells) # 緑
```

攻撃スキルは通常攻撃と同じハイライト生成処理を再利用してよい。

---

# 数値ログ演出の追加

## 13. FloatingNumber を追加する

攻撃でダメージを受けたとき、または回復でHPが回復したとき、
対象キャラクターの上から数値ログが出る演出を追加する。

追加ファイル:

```text id="dlesgn"
res://scripts/ui/FloatingNumber.gd
```

または3D空間上で出す場合:

```text id="8rnr3j"
res://scripts/effect/FloatingNumber3D.gd
```

推奨は、3Dマップ上のキャラクター位置に追従する
`Label3D` ベースの簡易実装とする。

---

## 14. FloatingNumber の表示仕様

ダメージ時:

```text id="8f3zhf"
-26
```

回復時:

```text id="5k3cjd"
+25
```

Miss時:

```text id="mf17w9"
Miss
```

撃破時は、通常ダメージ表示に加えてBattleLogに撃破ログが出ればよい。
FloatingNumber側に `Defeated` 表示は必須ではない。

---

## 15. FloatingNumber の色・動き

表示仕様:

```text id="6f4db5"
ダメージ:
  赤系

回復:
  緑系

Miss:
  白または灰色
```

動き:

```text id="8etq8c"
対象ユニットの頭上から表示
0.6〜1.0秒かけて上へ移動
徐々に透明になる
最後に自動削除
```

Godot実装イメージ:

```gdscript id="qbttig"
func play(value_text: String, start_position: Vector3, number_type: String) -> void:
    global_position = start_position + Vector3(0, 1.5, 0)
    text = value_text

    var tween = create_tween()
    tween.tween_property(self, "global_position", global_position + Vector3(0, 1.0, 0), 0.8)
    tween.parallel().tween_property(self, "modulate:a", 0.0, 0.8)
    tween.finished.connect(queue_free)
```

`Label3D` の場合は `modulate` または `transparency` の扱いに注意する。

---

## 16. FloatingNumberManager を追加する

FloatingNumber生成を一元管理する。

追加ファイル:

```text id="8qj3a0"
res://scripts/effect/FloatingNumberManager.gd
```

責務:

* ダメージ数値を表示する
* 回復数値を表示する
* Missを表示する
* 対象ユニットの位置から表示する
* 表示ノードを生成・削除する

想定メソッド:

```gdscript id="7yqoxn"
func show_damage(unit: BattleUnit, amount: int) -> void:
    spawn_floating_number(unit, "-" + str(amount), "damage")

func show_heal(unit: BattleUnit, amount: int) -> void:
    spawn_floating_number(unit, "+" + str(amount), "heal")

func show_miss(unit: BattleUnit) -> void:
    spawn_floating_number(unit, "Miss", "miss")

func spawn_floating_number(
    unit: BattleUnit,
    text: String,
    number_type: String
) -> void:
    # unitの頭上にFloatingNumberを生成
```

---

## 17. AttackSystem への反映

通常攻撃でダメージを与えた場合、
`FloatingNumberManager.show_damage()` を呼ぶ。

Missの場合は、
`FloatingNumberManager.show_miss()` を呼ぶ。

ただし、`AttackSystem` がUIや演出に直接依存しすぎるのを避けるため、
以下のどちらかで実装する。

### 推奨案A: result Dictionaryに情報を返し、BattleCursor / TurnManager側で演出

`AttackSystem.execute_attack()` は以下を返す。

```gdscript id="mfdntv"
{
    "success": true,
    "hit": true,
    "damage": 26,
    "target": target,
    "defeated": false
}
```

呼び出し側で演出を出す。

```gdscript id="u7vpot"
var result = attack_system.execute_attack(attacker, target)

if result.hit:
    floating_number_manager.show_damage(target, result.damage)
else:
    floating_number_manager.show_miss(target)
```

### 案B: AttackSystemにFloatingNumberManagerを参照させる

簡単だが、責務が混ざるため非推奨。
既存構造上こちらが簡単なら採用してもよい。

---

## 18. SkillSystem への反映

スキルでダメージ・回復・Missが発生した場合も、
FloatingNumberを表示する。

攻撃スキル:

```text id="eig3yw"
Hit:
  対象に -damage 表示

Miss:
  対象に Miss 表示
```

回復スキル:

```text id="z0pe4g"
対象に +heal 表示
```

範囲攻撃スキルの場合:

```text id="k9xvg8"
対象ごとに FloatingNumber を表示する
```

`SkillSystem.execute_skill()` の戻り値に、対象ごとの結果を含める。

例:

```gdscript id="r2h6sl"
{
    "success": true,
    "skill_id": "earth_break",
    "results": [
        {
            "target": bandit_a,
            "hit": true,
            "damage": 34,
            "heal": 0,
            "miss": false
        },
        {
            "target": bandit_b,
            "hit": false,
            "damage": 0,
            "heal": 0,
            "miss": true
        }
    ]
}
```

呼び出し側で、結果に応じてFloatingNumberを表示する。

---

# 敵攻撃可能領域の赤放物線矢印の点線化

## 19. ThreatArrowを点線の玉で表示する

現在、危険マスへ移動した時、
攻撃可能な敵から味方へ赤色の放物線矢印を表示している。

これを、赤い玉を点線状に並べた放物線表示に変更する。

表示イメージ:

```text id="lg0rof"
敵
  ・  ・  ・  ・  ・
        ・
          ・
            ↓
味方
```

---

## 20. ThreatArrowManager の修正

`ThreatArrowManager.gd` の `create_threat_arrow()` を修正する。

点線放物線の仕様:

```text id="t6q7uu"
始点:
  攻撃可能な敵ユニットの頭上

終点:
  移動後の味方ユニットの頭上

中間:
  放物線状に赤い小さな玉を配置

玉の数:
  8〜14個程度

玉のサイズ:
  小さめ

色:
  赤

終点側:
  必要であれば少し大きい玉、または小さなConeで矢印感を出す
```

---

## 21. 放物線点線の座標計算

以下のような計算でよい。

```gdscript id="m25z3x"
func get_arc_point(start: Vector3, end: Vector3, t: float, arc_height: float) -> Vector3:
    var pos = start.lerp(end, t)
    pos.y += sin(t * PI) * arc_height
    return pos
```

点を並べる。

```gdscript id="8gp77e"
for i in range(point_count):
    var t = float(i) / float(point_count - 1)
    var pos = get_arc_point(start, end, t, arc_height)
    create_red_sphere(pos)
```

---

## 22. ThreatArrowの更新と削除

既存どおり、以下のタイミングで点線玉を削除する。

* 行動確定
* 待機
* 攻撃
* 移動後キャンセル
* ユニット選択解除
* 敵ターン開始
* Victory / Defeat
* 次のユニット選択

`clear_threat_arrows()` で、生成した玉をすべて削除する。

---

# 新規追加ファイル

## 23. 追加ファイル一覧

以下を追加する。

```text id="eaxdab"
res://scripts/effect/FloatingNumber3D.gd
res://scripts/effect/FloatingNumberManager.gd
```

既存構成によっては、`FloatingNumber3D.gd` を `res://scripts/ui/FloatingNumber.gd` として作成してもよい。

---

# 既存ファイルの変更対象

## 24. 主な変更ファイル

以下を修正する。

```text id="mcs42t"
res://scripts/unit/BattleUnit.gd
res://scripts/skill/SkillData.gd
res://scripts/skill/SkillDatabase.gd
res://scripts/battle/SkillSystem.gd
res://scripts/battle/AttackSystem.gd
res://scripts/battle/ThreatSystem.gd
res://scripts/battle/EnemyAI.gd
res://scripts/battle/ThreatArrowManager.gd
res://scripts/battle/BattleCursor.gd
res://scripts/ui/SkillMenu.gd
res://scripts/ui/SkillConfirmPanel.gd
res://scripts/ui/BattleHUD.gd
res://scripts/ui/UnitInfoPanel.gd
res://scripts/ui/BattleLog.gd
res://scripts/Main.gd
```

---

# 推奨ノード構成

## 25. Main.tscn の拡張

```text id="vyvech"
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
    ├── BattleHUD
    ├── ActionMenu
    ├── SkillMenu
    ├── CombatConfirmPanel
    ├── SkillConfirmPanel
    ├── UnitInfoPanel
    ├── BattleLog
    ├── MissionUI
    └── BattleMessage
```

---

# 完了条件

## 26. 今回の完了条件

以下がすべて動作すれば完了。

1. `MP` 表記がすべて `AP` に変更されている
2. `BattleUnit` が `ap` / `max_ap` を持つ
3. `SkillData` が `ap_cost` を持つ
4. スキル使用時にAPが消費される
5. AP不足時はスキルを使用できない
6. UI上で `AP` と表示される
7. `Not enough MP` などの表記が `Not enough AP` に変更されている
8. 攻撃スキルの射程表示が赤色になる
9. 回復スキルの射程表示は緑色のまま
10. 範囲スキルの効果範囲は黄色で表示される
11. 通常攻撃でダメージを与えた時、対象上にダメージ数値が表示される
12. 通常攻撃がMissした時、対象上に `Miss` が表示される
13. スキル攻撃でダメージを与えた時、対象上にダメージ数値が表示される
14. スキル攻撃がMissした時、対象上に `Miss` が表示される
15. 回復スキルで回復した時、対象上に回復数値が表示される
16. 範囲スキルで複数対象に当たった場合、それぞれの対象上に数値が表示される
17. FloatingNumberは一定時間で上に移動しながら消える
18. 危険マス侵入時の赤放物線が、赤い玉を並べた点線表示になる
19. ThreatArrowの点線玉は、行動確定やキャンセル時に正しく消える
20. 既存の通常攻撃・スキル・回復・敵AI・ThreatSystem・勝敗判定が壊れていない

---

# 今回は実装しないもの

## 27. 今回不要なもの

以下はPhase 8.5では実装しない。

* 新規スキル追加
* ジョブチェンジ
* レベルアップ
* 経験値
* 装備
* アイテム
* 状態異常
* 反撃
* 連携攻撃
* 攻撃アニメーション
* 大規模エフェクト
* ダメージポップアップの複雑な演出
* スマホUI
* セーブロード

---

# 実装時の注意

## 28. 注意事項

* 機能追加よりも既存仕様の整備を優先する
* `MP` / `mp` / `mp_cost` の参照を残さない
* APは魔法・物理スキル共通の行動リソースとして扱う
* 攻撃スキルの射程色は通常攻撃と同じ赤に統一する
* 回復スキルの緑、効果範囲の黄色は維持する
* FloatingNumberはAttackSystemやSkillSystemに直接密結合しすぎない
* 可能なら攻撃・スキルの戻り値を使ってFloatingNumberManager側で表示する
* ThreatArrowManagerの点線玉は `clear_threat_arrows()` で一括削除できるようにする
* 既存のキャンセル処理で点線玉やFloatingNumberが残らないようにする
* UI文言の `MP` が残っていないか確認する

---

# 実装後に提示してほしい内容

## 29. 実装後の説明項目

実装後、以下を説明してください。

* 追加・変更したファイル一覧
* `MP` から `AP` へ変更した箇所
* BattleUnitのAP仕様
* SkillDataのAP Cost仕様
* SkillSystemのAP消費処理
* UI表示の変更内容
* スキル範囲色の仕様
* FloatingNumberManagerの仕様
* FloatingNumber3Dの表示仕様
* AttackSystem / SkillSystemからの表示連携方法
* ThreatArrowManagerの点線表示仕様
* 動作確認手順
* 現時点の制限事項
* 次に実装しやすい項目

---

# まず実装してください

Phase 8.5として、既存のスキル・UI・演出に対して以下の修正を行ってください。

* `MP` を `AP` に名称変更する
* `mp` / `max_mp` を `ap` / `max_ap` に変更する
* `mp_cost` を `ap_cost` に変更する
* UI表示を `MP` から `AP` に変更する
* AP不足時の文言を `Not enough AP` に変更する
* 攻撃スキルの射程色を通常攻撃と同じ赤色に統一する
* ダメージ時に対象キャラ上へダメージ数値を表示する
* 回復時に対象キャラ上へ回復数値を表示する
* Miss時に対象キャラ上へ `Miss` を表示する
* 敵攻撃可能領域の赤放物線矢印を、赤い玉を並べた点線表示に変更する

新しいジョブ・スキル・成長システムはまだ追加しないでください。
今回は、Phase 8で追加したスキルシステムの表記整理と演出改善を目的にしてください。
