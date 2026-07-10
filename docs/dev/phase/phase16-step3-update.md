# Phase16-Step3-Fix: Step3レビュー指摘の修正

## 目的

Phase16-Step3のコードレビューで見つかった不整合の修正と確認を行い、
Step4（ライティング・判読性調整）に進める状態にする。

## 背景

Step3実機確認で「Nearest単体は遠景でモアレる」ことが判明し、
`NEAREST_WITH_MIPMAPS` 方針へ転換された（規格書6章も更新済み）。
ただしこの転換が一部のテクスチャに反映されておらず、設定の不整合が残っている。

## 作業内容

### 1. mipmap設定の不整合修正【必須】

現状:

- GLB抽出テクスチャ（`assets/terrain/terrain_*_terrain_*.png.import`）: `mipmaps/generate=true` ✅
- 生PNG（`assets/terrain/textures/*.png.import`）: `mipmaps/generate=false` ❌

問題: 水・溶岩シェーダーは `filter_nearest_mipmap` ヒントで
`assets/terrain/textures/terrain_water_top_01.png` / `terrain_lava_top_01.png` を
直接参照しているが、mipmapが生成されていないためヒントが機能せず、
水面・溶岩にのみ遠景モアレが残る。

対応:

- `assets/terrain/textures/` 配下の**全PNG**のインポート設定を
  `mipmaps/generate=true` に変更し再インポートする
  （水・溶岩の2枚だけでも直るが、規格書6章「Mipmaps: ON」との整合のため全部揃える）
- ゲームを起動し、引きのカメラで水面・溶岩のモアレが消えていることを確認する

### 2. シェーダーのテクスチャリピート明示【推奨】

水・溶岩シェーダーはUVが0〜1を超えてスクロールし続けるため、
テクスチャリピートが必須。現状サンプラーに `repeat_enable` の明示がなく、
デフォルト挙動に依存している。

対応: 両シェーダーのサンプラー宣言に `repeat_enable` を明示する。

```glsl
uniform sampler2D water_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D lava_texture : source_color, filter_nearest_mipmap, repeat_enable;
```

修正後、水面を60秒以上表示し続け、端の色引き伸ばしや模様の停止が
起きないことを確認する。

### 3. docs/ のGodotインポート除外【任意】

`docs/dev/sample-image/` の参考JPGがres://内にあるため、Godotが
.importファイルを生成している。動作に害はないが、リポジトリのノイズになる。

対応: `docs/.gdignore`（空ファイル）を作成する。作成後、docs配下の
既存 `.import` ファイルを削除してコミットする。

### 4. ゲーム内目視確認【必須・コード変更なし】

以下を実機で確認し、問題があれば内容を記録する（修正はStep4以降で判断）。

- [ ] 階段の向き: 実マップ上で階段の昇降方向が地形と食い違っていないか
      （現実装は向き固定。違和感が実害レベルなら課題として docs/status.md に記録）
- [ ] 水面の透け: alpha 0.8 の水面越しに「何もない空間」が見えるセルがないか
      （見える場合は水セルの下に底タイルを敷く対応を検討課題として記録）
- [ ] 崖3種（土・草垂れ・石）が意図した地形で出ているか

## 完了条件

- textures/ 配下全PNGが mipmaps ON で再インポートされている
- 両シェーダーに repeat_enable が明示されている
- docs/.gdignore が存在し、docs配下の.importが削除されている
- 目視確認3項目の結果が記録されている（問題があれば docs/status.md に課題として残す）
- 引きカメラで水面・溶岩を含む画面にモアレ・ちらつきがない