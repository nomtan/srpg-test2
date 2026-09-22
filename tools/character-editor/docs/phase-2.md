# Phase 2: 正式基準素体 base_1

正式Sourceは **`assets/characters/base/base_1.bbmodel`**。
ユーザーのパス訂正を反映し、旧 `base.bbmodel` から切り替えた。
どちらのSourceも既存GLBもゲーム側も変更していない。

## 再生成

Node.js 22.18以上（確認環境24.14.1）。追加npmパッケージなし。

```powershell
cd tools/character-editor
npm.cmd run build:base
npm.cmd run verify:base
npm.cmd run dev
```

- `src/domain/base-rig.ts`: Source・座標規格・既存Group→Role・仮Socket定義。
- `scripts/build-base-model.mjs`: ビルド時の解析・GLB生成。Sourceへの書込処理はない。
- `scripts/verify-base-model.mjs`: Sourceハッシュ、Group階層、頂点・UV、Explorerとの比較。
- `docs/base-model-analysis.md`: 再生成可能なGroup・Body Part・Animation一覧。
- `public/generated-assets/base_body/analysis.json`: 全Outliner・Group・Mesh/Cube・Pivot・UV・元Animation・分類・Socket親UUID。
- `public/generated-assets/base_body/model.glb`: Preview生成物。元のbbmodelの代わりにはしない。
- `public/generated-assets/base_body/comparison.json`: 数値検証と目視確認の状態。

## 解析結果

46 Group、102 Element（30 Mesh／72 Cube）、Body Partは20 Meshで全て表示対象。
頭は `ganmenn`。旧Sourceにあった `beveled_cuboid` はこのSourceには存在しない。
18 Animation（うち `animation` は0秒・0キー）、Texture画像0件、UV空間32×32。
元の全AnimationトラックをJSONに記録。GLBはRest Poseのみで、Animation再生は追加しない。

Groupの名前とUUIDは旧Sourceと共通だが、Pivot・部品形状・部品UUIDには変更があるため、
全データを新Sourceから再解析した。Mappingは実在するGroup名を再照合して利用する。

- `hand_left/right` は上腕、`hand_left_te/right_te` が手。
- `foot_left/right` は大腿の親、`ashi_left/right` は下腿・足先の親。
- 左上腕はX=-20°、右上腕はX=15°、左大腿はX=-7.5°、右大腿はX=7.5°のRest Poseを保持。
- 首・肩・耳はMesh。独立Boneや新Skeletonは作らない。
- `onehand_sword`、`gread_sword`、`spear`、`bow`、`shield`、`dagger_left/right`、`allow` を装備階層として分類。
- 元の綴りを変更しない（左右の意味づけは SOURCE_NODE_BY_SIDE で解決する）。全46 GroupをGLB Nodeとして残し、非表示装備MeshはPreviewに出力しない。
- Socket は当初、既存 Group のローカル原点（＝回転 Pivot）を指す `pivot_only_uncalibrated` だった。
  **Phase 10 で校正済み**: Pivot は取り付け点ではなく、socket_chest は胴体から 0.53 m、socket_back は
  0.50 m ずれていた。現在は各 Socket が担当する Body Region の中心に置かれ（`SOCKET_REGION` in
  `scripts/build-measurements.mjs`）、オフセットは親ノードのローカル系で保存される。

Materialは中立の単色。UVは保持するが、ゲームのPalette適用・色の一致は今回の範囲外。
Blockbench 5の保存済みFace順で三角化し、未対応形式やTexture追加時には変換を停止する。
参考: [Blockbench 5 MeshFace保存処理](https://github.com/JannisX11/blockbench/blob/v5.0.0/js/outliner/mesh.js)。

## Explorerとの一致

比較対象は `assets/world_jrpg/explorer_base_1.glb`。
`scripts/world_jrpg/explorer_actor.gd` が読み込み、
`tools/asset_gen/export_explorer_model.py` が同じ `base_1.bbmodel` から生成している。
既存Exporterの1/12スケール、+X前方・+Y上を採用する。軸変換、中心移動、姿勢の補正は行わない。

**左右について（Phase 9 で訂正）**: 当初この文書は「+Z 左」としていたが、右手系では
`forward × left = up`、つまり `+X × -Z = +Y` なので、**キャラクターの左は -Z、右は +Z** が正しい。
Source のグループ名は左右が逆で、`hand_left_te`（z = +0.48 m）は実際には右手、
`hand_right_te`（z = -0.44 m）は左手である。Source の武器階層もこれと整合しており、
`onehand_sword` は `hand_left_te`＝実際の右手にぶら下がっている。
Source の綴りは変更せず、`src/domain/base-rig.ts` の `SOURCE_NODE_BY_SIDE` が
物理的な左右 → Source グループ名を解決する。

静止姿勢のサイズはX=約0.583333m、Y=約1.845372m、Z=約1.215658m。
傾いた脚を含む実形状のBoundsであり、地面よりわずかに下の頂点も勝手に持ち上げない。

検証は、Sourceの160頂点を独立した軸回転計算で評価し、生成GLBのワールド頂点と比較する。
さらにExplorerと全表示三角形（頂点順を含む）・頂点集合・共通15 GroupのPivotを比較する。
許容誤差は1e-6m。結果はcomparison.jsonへ生成する。
旧 `assets/characters/base/base.glb` は別Sourceの参考比較であり、一致の必須条件ではない。

## 完了条件

1–5: 解析・部品一覧・Mapping・Equipment分類・Animation一覧を更新済み。
6: Builder／Creatorの初期表示をbase_1由来GLBへ切り替え済み。
7: Explorerと静止形状・Scale・向きの数値比較は一致。
実画面のThree.js／Godotの目視比較は引き続き未完了。
目視確認前にHair／Armor／Weapon装着へは進まない。
