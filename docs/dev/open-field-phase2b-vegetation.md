# Open Field Phase 2B — Vegetation Asset Production

Phase 2A ([open-field-phase2a-vegetation.md](open-field-phase2a-vegetation.md)) で品質基準とした
**Broadleaf A** / **Grass Normal** と同じPipeline・規約で、残り14Assetを制作しGodotへ導入した。
Phase 2Aの2Assetは形状を変えていない (同じscriptから同一の三角形数・頂点で再出力される)。

スクリーンショット: [showcase/open-field-phase2b/](showcase/open-field-phase2b/)

## Pipeline (2Aから変更なし)

```bash
# 全16Assetを再生成 (名前を渡すとそのAssetだけ)
blender -b --factory-startup --python tools/vegetation/build_vegetation_assets.py -- [asset ...]
# 検証 (headless、226項目)
godot --headless --path . -s res://scripts/world_jrpg/verify_vegetation_phase2.gd
# Asset単体キャプチャ
godot --path . -s res://scripts/world_jrpg/verify_vegetation_phase2.gd -- --render --capture-dir=<dir>
```

Blender操作はBlender MCPと同じbpyコードをheadless実行している。形状はscriptのパラメータが正で、GLBは手修正しない。

### 規約の追加

| 項目 | 規約 |
|---|---|
| LOD | Tree: `_LOD0`–`_LOD3`、Bush: `_LOD0`–`_LOD2`、Grass / Flower: 1 Object |
| Material Slot | Bush は Tree と同じ `Trunk` + `Leaves`。Flower は `Grass` (葉・茎) + `Flower` (花弁) |
| Vertex Color A | 花弁のpalette (1 = warm: 白 / 黄、0 = cool: 紫 / 青)。それ以外は1 |

## 1–4. Asset一覧 / GLB / Triangle数

| Asset | GLB | LOD0 | LOD1 | LOD2 | LOD3 | 寸法 (Godot) |
|---|---|---|---|---|---|---|
| broadleaf_a | trees/broadleaf/broadleaf_a.glb | 4,820 | 1,269 | 665 | 172 | 高さ7.8m (2A) |
| broadleaf_b | trees/broadleaf/broadleaf_b.glb | 5,124 | 1,337 | 745 | 192 | 高さ8.4m、樹冠半径2.4m |
| broadleaf_c | trees/broadleaf/broadleaf_c.glb | 5,552 | 1,452 | 745 | 192 | 高さ6.9m、樹冠半径3.8m |
| oak_a | trees/oak/oak_a.glb | 5,552 | 1,452 | 745 | 192 | 高さ7.5m、樹冠半径5.2m |
| oak_b | trees/oak/oak_b.glb | 4,804 | 1,257 | 665 | 172 | 高さ7.7m、樹冠半径6.6m |
| conifer_a | trees/conifer/conifer_a.glb | 3,128 | 1,194 | 313 | 120 | 高さ8.8m、8 whorl |
| conifer_b | trees/conifer/conifer_b.glb | 2,456 | 938 | 249 | 96 | 高さ7.3m、6 whorl |
| bush_a | bushes/bush_a.glb | 1,699 | 412 | 69 | – | 高さ1.0m |
| bush_b | bushes/bush_b.glb | 2,019 | 492 | 89 | – | 高さ0.8m、幅2.2m |
| bush_c | bushes/bush_c.glb | 1,727 | 412 | 69 | – | 高さ1.1m |
| grass_short | grass/grass_short.glb | 50 | – | – | – | 10 blades、0.08–0.14m |
| grass_normal | grass/grass_normal.glb | 60 | – | – | – | 12 blades、0.15–0.28m (2A) |
| grass_tall | grass/grass_tall.glb | 98 | – | – | – | 14 blades (4段)、0.30–0.48m |
| grass_wild | grass/grass_wild.glb | 128 | – | – | – | 14 blades + 穂3本、0.18–0.45m |
| flower_grass_a | flowers/flower_grass_a.glb | 124 | – | – | – | 葉8 + 星形の花5輪、0.16–0.28m |
| flower_grass_b | flowers/flower_grass_b.glb | 89 | – | – | – | 葉7 + 穂状花序3本、0.26–0.40m |

全TreeがLOD0 2,000–6,000 / LOD1 800–2,500 / LOD2 200–800 (§13) と高さ5–9m (§14) に収まる (verify scriptで検査)。

### Shape design

- **Broadleaf B / C、Oak A / B** は Broadleaf A の構造 (曲がったTrunk → 黄金角のPrimary → Secondary → 先端Mass + Top / Fill Mass)
  を `design_spreading()` のパラメータで描き分けた。Silhouetteだけで種類が分かることを優先。
  - **B**: まっすぐ高いTrunk、2.6mから急角度 (50–60°) のLimb、Top Massを2段重ねた縦長の楕円樹冠。
  - **C**: 強く傾いたTrunkが1.6mで副幹 (co-dominant stem) と5本のLimbに分かれる。低く広い、傾き側に重い樹冠。
  - **Oak A**: 太いTrunk (根元半径0.7m + 大きなroot flare)、ほぼ水平 (8–25°) で先端だけ上がる長いLimb、扁平なMassで低く広い樹冠 (§9)。
  - **Oak B**: 1本のLimbが4.8m横へ低く伸び、樹冠もそれに引かれる非対称のLandmark Tree。Hero Tree候補 (§40)。
- **Conifer** は円錐の重ね合わせではなく、新しい `Tier` (branch whorl) で作った (§10)。上面は平らに近く外周で垂れ下がるskirt、
  外周は6–9本の枝先 (lobe) に割れて枝先ほど垂れ、底面は暗い。whorlごとにlobe位相・片寄り・中心のずれが違うので外形は段ごとに不規則。
  Bは垂れが強く、4段目を細くして外形に隙間を作り、上部が傾く。
- **Bush** は樹冠と同じ `Mass` を低木サイズで組み合わせ、短いtwigを入れた。A = ドーム、B = 低く横長 (道端・畑の縁)、C = 縦に積んだ下層木。
- **Grass** は2Aのblade生成を関数化して共有。Tallは4段に曲げて長いbladeの折れを抑え、Wildは幅・傾きのばらつきを大きくし穂を3本加えた。
- **Flower** は葉のclumpに花茎を立て、A = 5–6弁の星形の花 (中心は頂点tone 0で黄色に塗る)、B = 3つの小花を積んだ穂状花序。

## 5. Material構成 (§57)

`assets/environment/vegetation/materials/` の4つを全16Assetで共有 (Bush専用Materialは作らずTreeFoliageMaterialを共有)。

| Material | Shader | 使用Asset |
|---|---|---|
| TreeTrunkMaterial (`tree_trunk.tres`) | open_field_tree.gdshader (`foliage = 0`) | Tree 7種のTrunk / Limb、Bushのtwig |
| TreeFoliageMaterial (`tree_foliage.tres`) | open_field_tree.gdshader (`foliage = 1`) | Tree 7種の葉、Bush 3種 |
| GrassMaterial (`grass.tres`) | open_field_grass.gdshader (`flower = 0`) | Grass 4種、Flowerの葉・茎 |
| FlowerMaterial (`flower.tres`) **新規** | open_field_grass.gdshader (`flower = 1`) | Flowerの花弁のみ |

- Flowerの花弁色はShader側で決める。vertex alphaでwarm / coolの組を選び、ノイズpatchごとにその組の1色 (白か黄、紫か青) にするので、
  1つのdriftが同じ色で咲く (§31)。色はAshen Vowに合わせて彩度を抑えた。
- Shadow / Base / Highlight の3段palette、Biome tint harmony、天候追従は2Aのまま全Assetに効く。

## 6–7. Wind

2Aの実装 (`open_field_wind.gdshaderinc`: Base + Spatial Noise + Gust、vertex G = wind weight) をそのまま使う。新Assetはweightの付け方だけ決めた。

- **Conifer**: whorlの根元0.3 → 枝先0.9、Trunkはほぼ0。枝先が垂れている部分ほど動く。
- **Bush**: Massのweightを0.45倍 (最大0.45)。低木が樹冠と同じ振幅で揺れないようにした。
- **Grass Tall / Wild**: 根元0、先端1。穂 (seed head) と花は先端と同じweight 1で茎ごと揺れる。

## 8. MultiMesh

| 種類 | 方式 | Visibility / Shadow |
|---|---|---|
| Tree 7種 | `add_tree_chunk` (2Aの階層LOD): 32m Coarse Cell LOD2/3 + 16m Fine Cell LOD0/1 | LOD0 0–34m、LOD1 34–80m、LOD2 80–160m (shadow ON)、LOD3 160m– (shadow OFF) |
| Bush 3種 | `add_bush_chunk` **新規**: 32m Cell、LODごとに1 MultiMesh | LOD0 0–26m (shadow ON)、LOD1 26–60m、LOD2 60–120m、それ以遠は描画しない |
| Grass 4種 | `add_grass_chunk` (2A): 20m chunk、近景は全Cluster、36–70mは1つおき | shadow OFF、52–68mで地面へ沈める |
| Flower 2種 | `add_grass_chunk`: 疎なのでmid bandを作らず1 MultiMeshで0–70m | shadow OFF |

木・草・低木とも1本ごとのNodeは作らない。世界全体のNode数は9,297。

## 9–11. Placement / Biome / Sightline

配置の骨格 (Biome density × density rhythm × sightline mask × grove noise) は2Aのまま。Cluster Based Placement (§33–40) はPhase 2Cの範囲。
2Bでは、既存の配置点ごとにどのAssetを置くかを以下で決めた。

- **乱数列を変えない**: Variantは既にある乱数 (`pick`) のhashで選ぶ。新しい乱数を引かないので、木・岩の位置は2Aと同じ。
- **Broadleaf / Oak**: 開けた土地 (PLAINS + LAKESHORE + FARMLAND + HIGHLAND のweight) ほどOakの比率が上がる (10% → 55%)。
  Oak Bはその3割。森の中はBroadleaf A / B / Cを均等に置く。Blossom tree (手続き生成) は従来通り草原と湖畔のまれなアクセント。
- **Conifer A / B**: 高度30–50mにかけてB (広く垂れたspruce) の比率が35% → 65%に上がる。
- **Bush (新規)**: 3m gridで、木の密度 (tree_density × rhythm) が中間の帯、つまりForest Edgeで最も多く、森の内部では下層木として少し、
  道端 (道から2–4m、7mまでに減衰) にも少し置く。Sightline内は半分に減らす (低木は視線を塞ぎにくいため)。
  深い森ほどC (縦長)、道端ほどB (横長)。世界全体で963株。
- **Grass**: Biomeのdensityとtall_share (wetnessで上昇) は2Aのまま。Clusterの種類は地面で決める。
  - Short: 道から2.2m以内、斜面 (slope > 0.45)、grass_densityの低いBiome、ノイズで作る短い芝のpatch。
  - Tall / Wild: tall_shareで選び、道から2m以内には置かない。岩の多い土地 (rockiness) とノイズpatchでWild。
  - Flower: 2Aのdriftはそのまま。driftごとにA / Bを決め、湿った土地ほどB (cool) が増える。
  - 世界全体: Normal 69,623 / Short 38,667 / Tall 39,048 / Wild 19,639 / Flower A 3,264 / Flower B 1,878 Cluster。
- **Sightline**: 2Aの `_sightline_mask` (Castle / Windmill / Mountain / Ruins / Lakeへの回廊) を木とBushの両方に使う。

## SRPG (§52–54)

- Tree: 従来通りTrunkのobstacle rectを登録 (Oakは幹が太いので半幅0.65 × scale、他は0.45)。葉にcollisionはない。
- `cover_cells` (CELL_SIZEごと) を新設: 幹のあるcellは `"TREE"`、Bushのあるcellは `"LIGHT"` (walkableのまま)。
  `get_cell_info()` が `"cover"` を返すので、将来のBattleCellはここから `cover = TREE / LIGHT` を作れる。
- Grass / Flowerはobstacleにもcoverにもならない。見た目の植生と、gameplay用のterrain / obstacleは分離したまま。

## 12. Performance

`samples/JRPGWorldSample2.tscn`、1920×1080、vsync OFF、300 frame平均、各2回。2A列は2Aの文書の値。

| View | Frame (2A → 2B) | Primitives (2A → 2B) | Draw calls (2A → 2B) |
|---|---|---|---|
| hero | 5.20 → 5.36–6.97 ms | 1.17M → 1.01M (−14%) | 2,324 → 2,658 (+14%) |
| forest_edge | 3.18 → 3.36–4.39 ms | 1.18M → 0.90M (−24%) | 433 → 875 (+102%) |
| plains | 3.72 → 3.82–5.04 ms | 1.09M → 0.92M (−15%) | 1,133 → 1,417 (+25%) |

- Primitivesは全viewで減った。手続き生成のConiferとtall tuftがLODつきのAssetに置き換わったため。
- Draw callsは増えた。1つのcellに入る植生の種類が増え (Tree 1 → 7種、草 2 → 6種、Bush 3種)、種類ごとに1 MultiMeshになる。
  Shadow passも同じだけ増える。forest_edgeが最大 (+102%)。
- 今回の計測では同条件の連続2回でFrame timeが最大1.6ms違い、2Aとの差 (+0.2–1.8ms) はこのばらつきと区別できなかった。
  Draw callsの増加は確実なので、下の課題として扱う。

## スクリーンショット (§70)

| 項目 | ファイル |
|---|---|
| Broadleaf A 単体 | `vegetation_broadleaf_a_single.png`、`vegetation_broadleaf_a_lods.png` |
| Tree 7種 / LOD | `vegetation_trees_lineup.png`、`vegetation_oak_a_lods.png`、`vegetation_conifer_a_lods.png` |
| Bush / Grass / Flower | `vegetation_bushes.png`、`vegetation_grass_types.png` |
| Grass Close-up / Grassland | `vegetation_grass_closeup.png`、`vegetation_grass_meadow.png`、`open_field_plains_day.png` |
| Broadleaf Forest / Forest Edge | `open_field_forest_edge_day.png` |
| Conifer Highland | `open_field_highland_day.png` |
| 森の近景 | `open_field_forest_day.png` |
| Lakeshore / Hero View / Overview | `open_field_lakeshore_day.png`、`open_field_hero_day.png`、`open_field_overview_day.png` |

Deep Forest専用のcamera shotはまだない (`SHOTS` に追加するのはPhase 2Cで森の構造を作ってから)。

## 13. Phase 2C / Phase 3への課題

- **Draw calls**: 植生の種類が増えた分だけ増えた。候補は、Coarse Cellの拡大 (32 → 64m)、Fine CellをAsset種類でなくcell単位にまとめる、
  LOD1のshadowをLOD2 meshで代用する、遠景のTree variantを1種にまとめる、など。Phase 2Cのcamera条件で計測して決める。
- **Cluster Based Placement**: Forest Core / Edge / Meadow / Small Grove / Hero Tree はまだない。Forest Edgeは木の密度で間接的に表しているだけで、
  forest_edge viewでは樹冠がまだ「木の壁」に近い。Oak Bを見晴らしの丘・湖畔・遺跡に1本ずつHero Treeとして置くのも2C。
- **Tree Base / Rock周辺のGrass密度** (§45–46)、**Road Edgeの段階的なTransition** (§44): Shortを道の近くに置いた以外は未着手。
- **Blossom tree**: 手続き生成のまま (Phase 2の16Assetに含まれない)。Broadleaf Cの花色版にするかは要判断。
- **Mass形状**: Broadleaf / Oakの樹冠Massは近景で「平たいクッション」に見えやすい。Phase 3でMassの縁を切り欠く (lobeを深くする) か、
  alpha cardのleaf edgeを足すかを検討する。
- **Flower B**: 近景で穂状花序の小花が単純なひし形に見える。
- `source/environment/vegetation/*.blend1` (Blenderの自動バックアップ) と、Godotが `.blend` をimportしている `*.blend.import` は2Aから
  そのまま。`source/` に `.gdignore` を置くかは別途判断する。
