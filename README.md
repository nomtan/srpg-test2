# Voxel SRPG Prototype

Godot 4製の、2Dグリッド＋高さ情報で動く8×8ボクセル風SRPGプロトタイプです。

## 実行

1. Godot 4.6以降でこのフォルダーの `project.godot` を開く
2. `F6` ではなく `F5`（プロジェクトを実行）を押す
3. 青いユニット Vain にカーソルを合わせて決定し、青く表示された移動先を決定する

操作は矢印キー/WASDとEnter/Space/Esc、またはマウスです。

## ノードとスクリプト

`Main.tscn` に、設計書どおり `VoxelMap`、`GridSystem`、`UnitManager`、
`BattleCursor`、`Pathfinding`、`CameraController`、`UI` を配置しています。
各ノードには同名の責務を持つ `scripts/` 以下のスクリプトを割り当てています。

- `grid/`: 盤面データと座標変換
- `map/`: 盤面データから独立した3D表示
- `unit/`: ユニット表示、選択、占有状態の更新
- `battle/`: カーソル入力とDijkstraによる移動範囲
- `camera/`: 固定の正投影カメラ
- `main.gd`: 各機能を結ぶプロトタイプの進行制御
