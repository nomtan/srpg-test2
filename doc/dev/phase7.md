# Godot SRPGプロトタイプ Phase 7 開発指示書

# 目的

Phase7では

**「SRPGとして1ステージ遊べる状態」**

を目標とする。

これまで構築した

* マップ
* ユニット
* AI
* ターン制
* 地形
* 射線
* 向き
* 戦闘

を利用し、

実際に「ステージを攻略する」というゲームループを完成させる。

今回は

* ステージデータ
* 勝利条件
* 敗北条件
* オブジェクト
* イベント
* 強化AI

を追加する。

---

# 実装項目

## 1. StageManager追加

追加ファイル

```text
res://scripts/stage/StageManager.gd
```

責務

* ステージ開始
* 勝利判定
* 敗北判定
* イベント発火
* オブジェクト管理
* ステージ終了

---

## 2. StageData追加

ステージ情報をResource化する。

```text
StageData
```

保持する内容

```gdscript
stage_name

map_name

player_spawn

enemy_spawn

victory_condition

defeat_condition

event_list
```

---

## 3. VictoryCondition

enum化する

```gdscript
DEFEAT_ALL_ENEMIES

REACH_POINT

SURVIVE_TURNS

ESCORT

DEFEAT_BOSS
```

---

## 4. DefeatCondition

```gdscript
ALL_PLAYER_DEAD

MAIN_CHARACTER_DEAD

TURN_LIMIT

NPC_DEAD
```

---

## 5. StageObject

マップ上に配置できるオブジェクトを追加

例

```
宝箱

レバー

扉

破壊可能オブジェクト

回復ポイント

転移魔法陣
```

追加ファイル

```
StageObject.gd
```

---

## 6. TriggerSystem

追加

```
TriggerManager.gd
```

責務

```
指定マス到達

指定ユニット到達

指定ターン

敵撃破

アイテム取得

オブジェクト操作
```

---

## 7. イベントシステム

EventManager追加

イベント例

```
3ターン目

増援出現

宝箱取得

ボス会話

扉開放

橋が落ちる

地形変化
```

---

## 8. Reinforcement

途中増援追加

例

```
Turn5

Bandit_C

Bandit_D

出現
```

---

## 9. Object Interaction

宝箱

```
カーソル選択

↓

開ける

↓

アイテム取得
```

レバー

```
操作

↓

扉が開く
```

---

## 10. AI改善

EnemyAI改善

優先順位

```
HPが低い敵を狙う

回復役を優先

主人公優先

高所確保

遮蔽物利用

遠距離維持
```

---

## 11. AIタイプ

EnemyType

```
Aggressive

Defensive

Sniper

Guard

Boss
```

EnemyAIはタイプによって思考を変える。

---

## 12. BossAI

追加

```
HP50%以下

↓

行動変化

↓

優先対象変更

↓

スキル解禁
```

今回はスキルはまだ不要。

行動変化だけ実装。

---

## 13. BattleMessage

ログとは別に

画面中央へ

```
Enemy Phase

Player Phase

Victory

Defeat

Reinforcement

Mission Complete
```

などを表示。

---

## 14. MissionUI

画面左側へ表示

```
Victory

・敵を全滅させる

Defeat

・ヴェインが倒れる
```

常時表示。

---

## 15. Cursor改善

カーソルを

```
宝箱

扉

レバー

NPC

敵

味方
```

で見た目変更。

---

## 16. UnitInfo改善

表示内容追加

```
名前

HP

地形

命中率

回避率

向き

現在状態
```

---

## 17. EventCamera

イベント時

```
カメラ移動

↓

対象へズーム

↓

終了後戻る
```

---

## 18. Camera演出

追加

```
攻撃時

対象へ寄る

↓

終了

↓

戻る
```

簡易実装でよい。

---

## 19. StageSaveData

ステージ情報保持

```
Turn

Player位置

Enemy位置

オブジェクト状態

イベント状態
```

まだ保存機能は不要。

構造だけ作る。

---

## 20. 新規追加ファイル

```
StageManager.gd

StageData.gd

TriggerManager.gd

EventManager.gd

StageObject.gd

MissionUI.gd

BattleMessage.gd
```

---

## 21. 完了条件

以下が完成していること

* ステージ開始できる
* 勝利条件がある
* 敗北条件がある
* 勝利画面表示
* 敗北画面表示
* MissionUI表示
* 途中増援
* 宝箱
* レバー
* 扉
* Trigger動作
* イベント発火
* EnemyAI改善
* AIタイプ追加
* BossAI追加
* BattleMessage追加
* Camera演出
* UnitInfo改善

---

## 22. 今回は実装しないもの

以下はPhase7では不要

* ジョブ
* スキル
* 魔法
* 状態異常
* 装備
* インベントリ
* レベルアップ
* 経験値
* ショップ
* セーブロード
* 会話システム
* カットシーン
* ボイス

---

## 23. 実装時の注意

* 既存戦闘システムを壊さない
* ステージシステムを戦闘システムから分離する
* TriggerManager と EventManager を独立させる
* StageData を Resource として設計し、今後ステージを追加しやすくする
* AIタイプは enum で管理する
* イベントはデータ駆動を意識する
* MissionUI と BattleMessage は独立したUIとして実装する

---

## 24. 実装後に提示してほしい内容

* 追加ファイル一覧
* ノード構成
* StageManagerの責務
* EventManagerの責務
* TriggerManagerの責務
* AIタイプ一覧
* 勝利条件の追加方法
* イベント追加方法
* StageData追加方法
* 動作確認方法
* 次フェーズへの改善点

---

## まず実装してください

既存のSRPG戦闘システムに対して、

* StageManager
* StageData
* TriggerManager
* EventManager
* Victory / Defeat 条件
* MissionUI
* BattleMessage
* 宝箱
* レバー
* 扉
* 増援
* AIタイプ

を追加してください。

最終的に

**「1マップを最初から最後まで攻略できるSRPGステージ」**

として遊べる状態を完成させてください。
