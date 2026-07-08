# テクスチャ規格書（map_texture_standard）

本書は「灰土の誓い（Ashen Vow）」で使用するテクスチャの共通規格を定義する。
テクスチャの新規作成・修正を依頼する際は、必ず本書と `texture_request_template.md` をセットで参照すること。

---

## 1. 基本方針

- テクスチャは原則として **スクリプトによる手続き生成**（`tools/asset_gen/gen_terrain_textures.py`）で作成する
- 色の定義は **パレットファイル（`tools/asset_gen/palette.json`）を唯一の真実** とし、スクリプト内に直接色コードを書かない
- 世界観（ダークファンタジー）の色調整はパレットの変更→全再生成で行う。個別テクスチャの手修正は原則行わない
- 写実的なPBRテクスチャ（Meshy等の生成物）は使用しない

## 2. 解像度・形式

| 分類 | 解像度 | 形式 | 備考 |
|---|---|---|---|
| terrain（地形上面・側面） | 32×32 | PNG (RGB) | 1面=1タイル貼り |
| prop（装飾小物） | 32×32 | PNG (RGBA可) | 透過は葉・草のみ許可 |
| character（キャラクター） | 64×64 | PNG (RGBA) | 1キャラ1枚のUVアトラス |
| effect用 | 32×32 or 64×64 | PNG (RGBA) | シェーダー側で加工前提 |

- 解像度の混在は禁止。上表以外のサイズが必要な場合は本書を先に改定する
- アルファは2値（0 or 255）のみ。半透明はシェーダー側で表現する

## 3. スタイル規定

- 色数: 1テクスチャあたり **5〜8色**（パレット量子化を通すこと）
- ディテールはノイズの塊感・ひび・発光コアなど「離れて見て判別できる要素」のみ
- グラデーション・アンチエイリアス・ぼかしは禁止（ドット感を殺すため）
- terrainテクスチャは **上下左右シームレス必須**（隣接タイルと連続すること）
- 陰影はテクスチャに描き込まない（ライティングはGodot側の仕事）

## 4. 命名規則

```
<category>_<name>_<variant番号2桁>.png
例: terrain_grass_top_01.png / terrain_grass_side_01.png / prop_broken_stone_01.png
```

- category: `terrain` / `prop` / `char` / `fx`
- terrainは面の役割を含める: `_top` / `_side` / `_bottom`
- バリエーションは番号を増やす（`_02`, `_03`）。同名上書きは禁止

## 5. パレット管理

`tools/asset_gen/palette.json` に以下の形式で定義する。

```json
{
  "grass": ["#4f8f3b", "#5da344", "#437a32", "#6bb350", "#3c6e2c", "#57993f"],
  "dirt":  ["#7a5a3a", "#6e5033", "#856343", "#64482d", "#8f6d4b", "#755638"],
  "accent": { "lava_core": "#ffd23f", "stone_crack": "#5a5a5f" }
}
```

- 新地形の追加=パレット1エントリの追加を基本とする
- 全体トーン調整（彩度・明度）はパレット全体への一括処理として実装する

## 6. Godotインポート設定（必須）

すべてのピクセルテクスチャ・テクスチャ埋め込みGLBについて以下を確認する。

- Filter: **Nearest（Mipmap併用）**（Linearになっているとボケる。GLB内サンプラーはNEAREST指定済みだが、
  インポート後に必ず目視確認。単純なNearest単体は本番カメラ距離でモアレ状にエイリアシングすることが
  Phase16-Step3実機確認で判明したため、`texture_filter = NEAREST_WITH_MIPMAPS`
  （`scripts/map/voxel_map.gd`の`_apply_nearest_mipmap_filter()`で自動適用、シェーダーは
  `filter_nearest_mipmap`ヒント）を標準とする。近距離のドット感は維持しつつ遠距離のちらつきを抑える）
- Mipmaps: **ON**（上記の理由によりMipmapは生成し使用する。OFFにすると遠景でモアレが出る）
- Compress: Lossless（VRAM Compressedはドット絵と相性が悪い）

## 7. 受け入れ基準（チェックリスト）

- [ ] 規定解像度・命名規則に従っている
- [ ] パレット定義から生成されている（直書き色がない）
- [ ] terrainの場合、2×2で並べて継ぎ目が見えない
- [ ] Godotのゲーム内カメラ距離で確認し、ノイズが細かすぎて「ざらつき」に見えない
  （細かすぎる場合は生成スクリプトのfbm octavesを下げて塊を大きくする）
- [ ] Nearest + Mipmap ON（NEAREST_WITH_MIPMAPS相当）で表示され、本番カメラ距離でモアレが出ていない
