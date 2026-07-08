# Phase 14: ジオラママップ表現基盤

現在のGodot SRPGプロトタイプでは、2Dグリッド＋高さ情報を使ってSRPGロジックを管理している。
この構造は維持したまま、マップの見た目を単純なボクセルCube表示から、ジオラマ風の3Dアセット配置方式へ拡張したい。

## 目的

- GridSystemのSRPGロジックは変更しない
- VoxelMap側の表示処理を拡張する
- terrain_typeに応じて異なる3Dアセットを配置できるようにする
- 高低差の境界に崖側面パーツを自動配置する
- 草地、石畳、水、橋、階段を表現できるようにする
- 将来的にWakfu風の草崖・石橋マップを作れる基盤にする

## 実装方針

1. `MapVisualTheme` のようなResourceを追加し、terrainごとのPackedSceneを登録できるようにする
2. `VoxelMap.gd` を、Cube直生成ではなくScene配置方式に対応させる
3. 各セルの上面には terrain に応じた top prefab を配置する
4. 隣接セルとのheight差を見て、必要な方向に cliff_side prefab を配置する
5. `water` terrainを追加し、水面Planeを配置できるようにする
6. `stone_road` terrainを追加し、石畳の上面を配置できるようにする
7. `bridge` terrainを追加し、橋床パーツを配置できるようにする
8. `stair` terrainを追加し、高さ差をつなぐ階段パーツを配置できるようにする
9. 見た目用PropはSRPGロジックとは分離し、装飾専用データとして扱う
10. 既存の移動、攻撃、射線、地形効果、ターン制処理が壊れないようにする

## 最初に用意する仮アセット

本番モデルが未完成なので、最初はGodot内の簡易Meshでよい。

- grass_top
- stone_road_top
- dirt_top
- cliff_side
- water_plane
- bridge_floor
- stair_block
- grass_patch
- broken_stone
- flag_placeholder

## 成果物

- 既存のPhase 10までの戦闘が動く
- 見た目がCubeマップではなく、terrain別のパーツ配置になる
- 高低差の境界に崖側面が表示される
- 小さなサンプルマップとして、草地、石畳、崖、水、橋、階段を含む8×8または12×12のマップが表示される