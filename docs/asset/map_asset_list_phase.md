# Phase 16 最小マップアセット一覧

| アセット | 用途 | 基準サイズ | 原点 | 接続条件 | terrain / 配置先 | 後続案 |
|---|---|---|---|---|---|---|
| `terrain_grass_top_01` | 草地の上面 | 1×0.1×1m以内 | 上面中央 | 四辺をセル境界へ揃える | grass / high_ground | 花、乾燥、苔、縁草 |
| `terrain_stone_top_01` | 石畳・岩床の上面 | 1×0.12×1m以内 | 上面中央 | 四辺の石目を隣接可能にする | stone / stone_road / rock / wall | 欠け、苔、大小石 |
| `terrain_dirt_top_01` | 土・森床の上面 | 1×0.1×1m以内 | 上面中央 | grassと同じ外周高さ | dirt / forest | 泥、轍、落葉 |
| `terrain_cliff_side_01` | 1段分の崖側面 | 幅1×高さ1m | 面中央 | 上端をY=+0.5、下端をY=-0.5、左右端をセル境界へ揃える | 高低差境界 | 草縁、岩層、土層 |
| `terrain_cliff_corner_outer_01` | 崖の凸角 | 1×1×1m以内 | 上面角基準 | 直交する2枚のsideと輪郭を揃える | 崖外角 | 丸角、欠け、張出し |
| `terrain_cliff_corner_inner_01` | 崖の凹角 | 1×1×1m以内 | 上面角基準 | 直交するside間の隙間を埋める | 崖内角 | 土溜り、草、岩屑 |
| `terrain_water_plane_01` | 水面 | 1×0×1m | 面中央 | 四辺を同高度の水面へ連結 | water | 流れ、泡、浅瀬 |
| `terrain_stair_stone_01` | 1段をつなぐ石階段 | 幅1×高さ1×奥行1m | 高い側の床面中央 | 高床Y=0、低床Y=-1へ接続。低い側は-Z | stair | 木階段、崩れ、手摺 |
| `prop_grass_patch_01` | 草束装飾 | 直径0.45×高さ0.4m以内 | 接地面中央 | 地形へ埋まりすぎず、セル外へ出ない | PropLayer | 花、枯草、シダ |
| `prop_broken_stone_01` | 壊れた石・瓦礫 | 0.5×0.35×0.5m以内 | 接地面中央 | 底面をY=0へ揃える | PropLayer | 石片群、苔石、レンガ |

すべてのアセットは[マップ用3Dアセット規格](map_asset_standard.md)に従い、Phase 16のプレビューシーンで寸法と接続を確認してから本番Themeへ登録する。
