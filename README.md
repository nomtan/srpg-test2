# Voxel SRPG Prototype

Godot 4製の、2Dグリッド＋高さ情報で動く8×8ボクセル風SRPGプロトタイプです。
Phase 2では味方3体・敵2体と、プレイヤー／敵ターンの基本ループを実装しています。
Phase 3では移動後の行動メニュー、通常攻撃、HP、撃破、勝敗判定を追加しています。
Phase 4では敵の移動AI、移動の取り消し、詳細なダメージ予測を追加しています。

## 実行

1. Godot 4.6以降でこのフォルダーの `project.godot` を開く
2. `F6` ではなく `F5`（プロジェクトを実行）を押す
3. 青い味方にカーソルを合わせて決定し、青く表示された移動先を決定する
4. 味方3体が行動すると1秒間の敵ターンを挟み、次のプレイヤーターンが始まる

操作は矢印キー/WASDとEnter/Space/Esc、またはマウスです。

## ノードとスクリプト

`Main.tscn` に、設計書どおり `VoxelMap`、`GridSystem`、`UnitManager`、
`BattleCursor`、`Pathfinding`、`TurnManager`、`CameraController`、`UI/BattleHUD` を配置しています。
各ノードには同名の責務を持つ `scripts/` 以下のスクリプトを割り当てています。

- `grid/`: 盤面データと座標変換
- `map/`: 盤面データから独立した3D表示
- `unit/`: ユニット表示、選択、占有状態の更新
- `battle/`: カーソル入力、Dijkstraによる移動範囲、ターン進行
- `ui/`: ターン、フェーズ、操作状況の表示
- `camera/`: 固定の正投影カメラ
- `main.gd`: 各機能を結ぶプロトタイプの進行制御
