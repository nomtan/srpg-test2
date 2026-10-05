# Open Field Phase 2A — Vegetation Quality Standard

Phase 2 (植生品質改革) の最初の実装単位。仕様 §58–61 / §71 に従い、量産前の品質基準Assetとして
**Broadleaf A** と **Grass Normal** の2つだけを制作し、Godotへ導入した。
残り14Asset (Phase 2B)、Cluster配置 (Phase 2C) は本Phaseの合格判定後に着手する。

スクリーンショット: [showcase/open-field-phase2a/](showcase/open-field-phase2a/)

続き: [Phase 2B — 残り14Assetの制作と導入](open-field-phase2b-vegetation.md)

## Pipeline

```text
tools/vegetation/build_vegetation_assets.py  (bpy, Blender 5.1)
  → source/environment/vegetation/<asset>.blend          編集用Blender Scene
  → assets/environment/vegetation/<group>/<asset>.glb    Godot runtime source
  → scripts/world_jrpg/open_field_vegetation.gd          GLB読込・共有Material割当・MultiMesh/LOD
  → scripts/world_jrpg/open_field_world.gd               既存Biome配置から呼び出し
```

```bash
# 再生成 (GLBを手修正しない。形状はスクリプトで変更する)
blender -b --factory-startup --python tools/vegetation/build_vegetation_assets.py -- [broadleaf_a grass_normal]
# 検証 (headless)
godot --headless --path . -s res://scripts/world_jrpg/verify_vegetation_phase2.gd
# Asset単体キャプチャ
godot --path . -s res://scripts/world_jrpg/verify_vegetation_phase2.gd -- --render --capture-dir=<dir>
```

Blender操作はBlender MCPと同じbpyコードをheadless実行している (MCPセッションに貼っても動く)。
再現性のため、Scene状態ではなくスクリプトを正とする。

### Asset規約 (Blender ↔ Godot)

| 項目 | 規約 |
|---|---|
| 単位 / 軸 | m、Blender Z-up → glTF Y-up、Godot Scale 1.0 |
| Origin | Trunk / Cluster の底面中心 (Treeはroot flareが0.35m地中に沈む) |
| LOD | 1 GLB内に `<asset>_LOD0` … `_LOD3` の別Object |
| Material Slot | Tree: `Trunk` + `Leaves`、Grass: `Grass` (名前でGodot共有Materialへ差替え) |
| Vertex Color `Color` (float, linear) | R = tone (0 shadow / 0.5 base / 1 highlight)、G = wind weight (根元0 → 先端1)、B = mass/blade毎のphase |
| GLB内容 | Meshのみ (Camera / Light / Animation なし)、Godot側の自動LOD生成は無効 |

## Asset

| Asset | GLB | LOD0 | LOD1 | LOD2 | LOD3 | 寸法 |
|---|---|---|---|---|---|---|
| broadleaf_a | trees/broadleaf/broadleaf_a.glb | 4,820 | 1,269 | 665 | 172 | 高さ7.8m、樹冠半径3.4m |
| grass_normal | grass/grass_normal.glb | 60 | – | – | – | 12 blades、高さ0.15–0.28m |

**Broadleaf A** — 少し曲がったTrunk (root flare付き) が2.0–3.5mで5本のPrimary Branchに分岐し、
各PrimaryにSecondaryを1本。樹冠はLarge 1 + 内部Fill 2 + Medium 5 (Primary先端) + Small Accent 5
(Secondary先端) の13 Mass。Massはlobe付き・底面を平らにした不規則形状で、Mass間の隙間から枝が見える。
NormalはMass自身と樹冠全体のblendでsoftな一体感を出す。LOD1でSecondary Branchを、LOD2で全Branchと
Small Massを落とし、残りのMassを拡大して外形を維持。LOD3は同じMassの20面体版。

**Grass Normal** — 12枚のBladeを黄金角で扇状に配置したCluster。1 Bladeは2段の曲がり + 先端の3 polygon。
外側ほど外へ傾き、Normalは上向き寄りにしてGroundと同じように照らされる。

## Material構成 (§57)

`assets/environment/vegetation/materials/` の3つを全Assetで共有。

| Material | Shader | 役割 |
|---|---|---|
| TreeTrunkMaterial (`tree_trunk.tres`) | open_field_tree.gdshader (`foliage = 0`) | Bark gradient + 縦streak |
| TreeFoliageMaterial (`tree_foliage.tres`) | open_field_tree.gdshader (`foliage = 1`) | Shadow / Base / Highlight 3段palette |
| GrassMaterial (`grass.tres`) | open_field_grass.gdshader | 根元のGround色 + 4 variant |

- Foliageはvertex toneで Shadow (青緑) → Base → Highlight (暖かい黄緑) を塗り分け、Lightingに依存しない (§12)。
  `light()` は wrap diffuse + 逆光translucency + 太陽連動のfillで、樹冠の影側を黒にしない (§51)。
- Biome Harmony (§50): Tree paletteはbiome tintへ45%寄せる。Grassは根元で地面と同じ `of_grass_tinted` を使い、
  先端だけ Light / Base / Yellow / Dark Green のvariantへ寄せる (patch noise + clump hash)。
- 天候 (wetness / snow_cover)、Biome Debug表示 (F3) は既存Materialと同様に追従。

## Wind (§26–29)

`open_field_wind.gdshaderinc` を両Shaderで共有。

```text
push = (Base 0.4 + Spatial Noise (風下へ流れる) + Gust (風向に沿って進む帯)) × wind_strength
```

- **Grass**: vertex G (根元0 / 先端1) × push で風下へ曲げ、曲げ量に応じて先端を下げる (伸びない弧)。
  bladeごとのphaseで横揺れを加える。Gustが通過すると先端が明るくなり、草原を風の帯が流れる。
- **Tree**: 木全体で1つのpush (幹位置で評価) × weight。Trunk 0–0.06、Primary 0.04–0.28、
  Secondary 0.2–0.42、Foliage 0.42–0.93 なので幹は動かず、外側の葉Massだけが揺れる。
  Massごとのphaseでbobし、表面をNormal方向に微小にrustleさせる。木全体を左右に振らない。
- 天候で `wind_strength` を変更: 晴1.0 / 雨1.7 / 曇1.3 / 雪0.6 (`_sync_conditions`)。
- Blender側で風をBakeしない。

## MultiMesh / LOD (§16–17, §55–56)

**Tree — Hierarchical LOD** (`Vegetation.add_tree_chunk`)

```text
32m Coarse Cell : LOD2 (80–160m, shadow ON) / LOD3 (160m–, shadow OFF)
  └ 16m Fine Cell : LOD0 (0–34m, shadow ON) / LOD1 (34m–, shadow ON)
     visibility_parent = Coarse LOD2
```

- Fine CellはCoarse LOD2がbegin距離より近い時だけ描画されるので、同じ木の二重描画や帯の抜けがない。
  遠方は32m Cellあたり1 draw。
- Visibility Rangeはcell AABB中心からの距離なので、16m Cellなら実際の木の距離との差は最大約11m。
- LOD2のShadowは仕様の推奨 (OFF) から変更してONにした。太陽のshadow距離が120mあり、LOD2の開始 (80m) より
  遠くまで影が届くため、OFFだと80m付近で影が消えるpopが出る。LOD3 (160m–) はOFF。
- 32 / 16m cellのMultiMeshInstance3Dのみで、木1本ごとのNodeは作らない (Forest全体で1,306 nodes)。

**Grass** (`Vegetation.add_grass_chunk`、20m chunk)

- 0–36m: 全Cluster。36–70m: 1つおきのClusterを15%拡大。Shadow OFF。
- Shaderで52–68mにかけてBladeを地面へ沈めるので、70mの描画境界が線として見えない (§49 Near / Mid / Far)。

## Placement (Phase 2Aの範囲)

配置ロジックはPhase 1のまま (Biome density + density rhythm + sightline mask + grove noise)。差替えは2点のみ。

- Broadleaf (通常2 variant) → `broadleaf_a`。Scaleは 0.85–1.15 × biome tree_scale、
  高さ方向の伸縮は ±5% (§64)。Obstacle rect (Trunk) は従来通り。
- Grass group 0 (通常の草) → `grass_normal`、Scale 0.85–1.15。

Conifer、Blossom、背の高い草、Flower、Rockは手続き生成のまま (Phase 2Bで置換)。
Cluster Based Placement (Forest Core / Edge / Meadow / Small Grove / Hero Tree)、Road EdgeのTransition、
Tree BaseのDensity低減はPhase 2Cの範囲。

## Performance

`samples/JRPGWorldSample2.tscn`、1920×1080、vsync OFF、300 frame平均。
Baseline = 同じworking tree (Phase 1) でPhase 2Aの差替えだけを戻したもの (2回計測)。

| View | Frame (Baseline → 2A) | Primitives | Draw calls |
|---|---|---|---|
| hero | 5.10–5.24 → 5.20 ms | 1.25M → 1.17M (−6%) | 2292 → 2324 |
| forest_edge | 3.39–3.59 → 3.18 ms | 0.88M → 1.18M (+34%) | 382 → 433 |
| plains | 3.77–3.81 → 3.72 ms | 0.95M → 1.09M (+15%) | 1076 → 1133 |

Frame timeは計測誤差 (約±10%) の範囲内で変化なし。近景の木 (LOD0 4.8k tris) とGrass Cluster (60 tris、
旧16 tris) でPrimitivesは増えたが、遠景はLOD2/3で減った。Draw callsはFine CellとGrass mid bandの分だけ増加。

## Phase 2A Acceptance (§61)

| 項目 | 結果 |
|---|---|
| Sphere Treeに見えない / Branch Silhouette / 複数Mass | ✔ `vegetation_broadleaf_a_single.png`、`open_field_plains_day.png` |
| 遠距離でもTreeとして成立 | ✔ LOD2/3でも外形を維持 (`vegetation_broadleaf_a_lods.png`、overview) |
| Godot Scale / Material正常 | ✔ verify script (高さ7.83m、origin、共有Material) |
| Grass Bladeとして認識できる / Groundと馴染む | ✔ `vegetation_grass_closeup.png` |
| Rootが動かずTipだけWind | ✔ vertex weight検証 (根元0.00 / 先端1.00)。動きは実機で要目視確認 |
| MultiMeshで大量表示 | ✔ 世界全体で107,279 grass_normal Cluster + 1,102 Broadleaf A、Frame timeは変化なし |

## Phase 2B以降への課題

- **背の高い草の手続きtuftが近景で目立つ**: hero viewの手前は旧tall tuftが支配的。`grass_tall` / `grass_wild` を最優先で置換する。
- **Conifer**: 森の近景で手続きConiferが巨大な平面Tierに見える (`open_field_forest_day.png`)。Conifer A/B を2Bで置換する。
- **Broadleafのvariation**: 現状1形状 + 色/scale variationのみ。密な森では同形の繰り返しが見えるため、Broadleaf B/Cが必要。
- **Forestが「木の壁」になる箇所**: forest_edgeで樹冠が連続している。Phase 2CのForest Core / Edge / Light Gapで解決する。
- **Tree Base**: 幹の周囲の草密度をまだ下げていない (§45)。Phase 2C。
- **Draw calls**: hero viewは約2,300 draw (大半は既存Landmark)。植生側はCoarse Cellを64mにすると遠景drawを1/4にできるが、
  LOD2の最短距離が短くなるため、Phase 2Cでcamera条件を見て調整する。
- **Battle Grid連携**: Treeは従来通りobstacle rectを登録。`cover = TREE` などのcell属性生成はPhase 2C以降。
