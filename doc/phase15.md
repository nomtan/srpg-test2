# Phase15: ジオラママップ表現・土台構築

## 目的

既存のSRPGロジックを維持したまま、マップの見た目を単純なCube表示からジオラマ風のアセット配置方式へ拡張する。

## 方針

- GridSystem、移動、攻撃、射線、ターン制などの既存ロジックは壊さない
- マップの見た目生成を MapRenderer として分離する
- terrain_type と height に応じて上面パーツを配置する
- 隣接セルとの height 差から崖側面を自動生成する
- 水、橋、階段、草地、石畳を表現できるようにする
- 装飾Propはゲームロジックと分離する
- まずは仮アセットで動作確認する

## 実装内容

### 1. MapVisualTheme Resourceの追加

terrainごとのPackedSceneを登録できるResourceを作成する。

対象:
- grass_top
- stone_top
- dirt_top
- water_plane
- cliff_side
- cliff_corner
- stair_block
- bridge_floor
- bridge_railing
- grass_patch
- broken_stone
- flag_placeholder

### 2. MapRendererの追加

MapDataを読み取り、以下のレイヤーに分けてNodeを生成する。

- TopLayer
- CliffLayer
- WaterLayer
- PropLayer
- DebugLayer

### 3. 上面パーツ配置

各セルのterrainに応じて上面Prefabを配置する。

例:
- grass → grass_top
- stone → stone_top
- dirt → dirt_top
- water → water_plane
- bridge → bridge_floor
- stair → stair_block

### 4. 崖側面の自動生成

各セルについて4方向の隣接セルを確認する。

自セルのheightが隣接セルより高い場合、その方向にcliff_sideを配置する。
height差が2以上ある場合は、段数分cliff_sideを積む。

### 5. 水面配置

terrainがwaterのセルにはwater_planeを配置する。
水は基本height 0として扱う。

### 6. 橋と階段

bridge terrainは歩行可能な特殊地形として扱う。
stair terrainは高低差をつなぐ地形として扱う。

Phase15では見た目配置を優先し、移動ルールの厳密化は後続Phaseでもよい。

### 7. 装飾Prop

各セルにprops配列を持たせ、草束、小石、壊れた石、旗などを配置できるようにする。
ただし、visual propは移動判定には影響させない。

### 8. サンプルマップ追加

8×8または12×12のジオラマ検証用マップを追加する。

含める要素:
- 草地
- 石畳
- 水
- 崖
- 段差
- 橋
- 階段
- 草束
- 壊れた石
- 旗

## 完了条件

- 既存の戦闘が壊れずに動作する
- terrain_typeごとに異なる見た目が表示される
- height差に応じて崖側面が自動表示される
- 水、橋、階段が表示される
- 小さなジオラマ風サンプルマップが表示される
- 見た目用PropがSRPGロジックと分離されている