# base.bbmodel → セルルック素体 + アニメーション (Blender / Godot)

Blockbench の `base.bbmodel`（generic/free 形式）から、**リグ・スキニング・全アニメーションを含む GLB** を生成し、Blender 側で**セルルック（トゥーン）**に仕上げるための一式です。GLB はそのまま Godot にも読み込めます。

Blender MCP が応答しなかったため、ライブ操作ではなく「検証可能なファイル成果物」として構成しています。変換の正しさは、こちらで FK＋スキニングを numpy 再実装し、`run` / `attack` / `idle` を画像化して目視確認済みです。GLB のボーン行列も参照実装と一致（最大偏差 2.95e-05、float32 丸め誤差レベル）しています。

---

## 中身
ゲーム内に配置
| ファイル | 役割 |
|---|---|
| `base_body.glb` | **素体本体**。46 ボーン + スキンメッシュ（肌/上衣/ブーツ/差し色の4ゾーン）+ 全17アニメーション |
| `base_full.glb` | 素体＋武器（全武器同時表示。武器種ごとに不要な物を非表示で使う） |
| `bbmodel_to_glb.py` | 変換器（本体）。ジオメトリ＋アーマチュア＋スキニング＋アニメーション |
| `bbcommon.py` | 変換器が使う bbmodel 解析・座標計算モジュール |
| `character_palette.json` | 色ゾーン定義（`palette.json` と同じ発想の単一ソース。ここを編集すれば色が変わる） |
| `setup_cel_shading.py` | Blender 4.x でセルルックを組む（トゥーンバンド＋インバーテッドハル輪郭線＋EEVEE） |
| `cel_preview.png` | 仕上がりイメージ（Blender を使わずこちらで近似描画したもの） |
| `verify_anim.py`, `glb_check.py` | 検証ツール（任意）。Blender 無しでアニメを画像確認／GLB を検算 |

素体の色ゾーン：肌=color2 / 上衣=color6 / ブーツ=color5 / 差し色(腰・手首)=color9。

---

## 使い方

### 1. GLB を作り直す（bbmodel を更新したとき）
```bash
python3 bbmodel_to_glb.py base.bbmodel base_body.glb --mode body
python3 bbmodel_to_glb.py base.bbmodel base_full.glb --mode full
# オプション: --fps 30（アニメのベイク間隔） --scale 0.0625（1bb単位→m。27単位≒1.69m）
```

### 2. Blender でセルルック化
```bash
blender --python setup_cel_shading.py -- /path/to/base_body.glb
```
または Scripting タブに貼り付け、冒頭の `GLB_PATH` を設定して実行。
- 全マテリアルを 2バンドのトゥーンシェーダに変換（Diffuse → Shader to RGB → 定数 ColorRamp）
- Solidify によるインバーテッドハルで黒輪郭線を付与
- View Transform を Standard にし、キー/フィルライトを配置
- 全アニメは Action として保持し、NLA トラックに積む（ミュート状態。1つアンミュートすればプレビュー可）

冒頭の調整値：`SHADOW_TONE`（影の濃さ）, `BAND_SPLIT`（陰陽の境目）, `OUTLINE`（線の太さ）, `BG_VALUE`（背景）。

### 3. Godot
`base_body.glb` をインポート → AnimationPlayer に17本のアニメーションが入ります。トゥーンは Godot 側で別途シェーダ化するのが定石なので、GLB のマテリアルはあえて素直な PBR（metallic0 / rough1）にしてあります。

---

## アニメーション一覧（17本）

武器種ごとの idle / run / attack が揃っています：
`onehand_sword` `great_sword`(内部名 `gread_sword`) `bow` `spear` `dagger` の idle/run/attack、
加えて汎用の `run`・旧テストの `walk_mcp_test`。空アニメ（length0）は除外済み。

> great_sword の attack だけ元データのタイポで `gread_sword_attack` になっています。気になるなら Blockbench 側でリネームしてから再変換してください。

---

## 座標・変換規約（うまくいかない時の調整点）

- Blockbench(free) と glTF はどちらも右手系・Y-up なので、座標はスケール以外そのまま対応します。Blender は取り込み時に Z-up へ自動変換するので直立します。素体は +X 前方向（元データの仕様）。
- アニメーションは**符号反転なし**でボディの run/attack/idle が正しく再現することを確認済み。もし武器の取り付け角やアニメが鏡像・軸ズレした場合は、`bbcommon.py` 冒頭の `EULER_ORDER` / `ANIM_ROT_SIGN` / `ANIM_POS_SIGN` を切り替えてください（ボディは rest 回転0なので影響しませんが、武器の rest 回転はここに依存します）。

---

## 次の一手（提案）

- **イージング**：現状はキーフレームを 30fps で線形ベイク。より滑らかにするなら Blockbench 側で catmullrom/bezier を使い、変換器の線形サンプルを密にする（`sample_channel` を補間対応に拡張）か、Blender で F-Curve に Auto Ease を適用。
- **武器の差し替え**：`base_full.glb` は全武器同時表示なので、Blender/Godot で武器種ごとにコレクション分けして表示切り替えするか、武器を別 GLB として `hand_*_te` ボーンにアタッチする運用が扱いやすいです（必要なら武器単体エクスポートも追加します）。
- **セルの階調**：影を2段でなく3段（ハイライト＋中間＋影）にしたい場合、`setup_cel_shading.py` の ColorRamp に stop を1つ足すだけです。
