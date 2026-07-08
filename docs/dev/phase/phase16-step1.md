# Phase16: 本番ローポリアセット導入 - Step1

## 目的

Phase15で作成したジオラママップ表示基盤に対して、
本番用のローポリGLBアセットを導入できるようにする。

まずはアセット規格を固定し、最小構成の地形アセットを作成・差し替え可能にする。

## 実装・作業内容

### 1. アセット規格書の作成

`docs/asset/map_asset_standard.md` を作成し、以下を定義する。

- 1セルのサイズ
- 1段の高さ
- Blender/Godot間のスケール
- 原点位置
- 前方向
- 命名規則
- terrain系、cliff系、prop系の分類
- GLBエクスポート時の注意点

### 2. 最小アセットリストの作成

`docs/asset/map_asset_list_phase16.md` を作成し、以下の10アセットを定義する。

- terrain_grass_top_01
- terrain_stone_top_01
- terrain_dirt_top_01
- terrain_cliff_side_01
- terrain_cliff_corner_outer_01
- terrain_cliff_corner_inner_01
- terrain_water_plane_01
- terrain_stair_stone_01
- prop_grass_patch_01
- prop_broken_stone_01

各アセットについて以下を記載する。

- 用途
- サイズ
- 原点
- 接続条件
- 使用terrain
- 後続バリエーション案

### 3. Godot側の受け入れ準備

既存のMapVisualThemeに、上記アセットを登録できるようにする。
すでに登録欄がある場合は不足分のみ追加する。

### 4. テストシーンの作成

`Phase16AssetPreview.tscn` のような確認用シーンを作成する。

確認内容:

- 1セルサイズの確認
- 高さ1段の確認
- grass + cliff + water の接続確認
- stone + stair の接続確認
- propの接地確認

## 完了条件

- アセット規格書が存在する
- Phase16用の最小アセットリストが存在する
- MapVisualThemeに本番GLBを登録できる
- アセットプレビュー用シーンでサイズ・原点・接続を確認できる
- 既存のPhase15サンプルマップを壊していない