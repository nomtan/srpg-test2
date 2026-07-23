# Reference visual pass

`scenes/dev/flat_validation.tscn`を、提供された画面のピクセル密度・色面・
構図密度へ近づけるための検証専用アートパス。

## 方針

- 提供画像は品質・カメラ角度・色調の参照だけに使い、固有キャラクター、UI、
  ロゴ、個別アセットは複製しない
- 本番用の既存資産を上書きせず、`generated/`と`terrain/reference/`に分離する
- 生成画像はマゼンタ背景で作成し、ローカルで透過化・セル分割する
- 地形テクスチャは`palette.json/reference_target`から手続き生成する

## 画像生成プロンプト

組み込みの画像生成機能を使用した。

### プロップ

4x2アトラス。順番は木箱、樽、岩群、焚き火、短い草、長い草、柵、荷車。
等角投影の三分の四視点、暖色の日中光、手描きピクセルアート、均一な
`#ff00ff`背景、文字・UI・ロゴ・キャラクターなし。提供画像は品質と
ピクセル密度だけの参照とし、個別デザインは複製しない。

### キャラクター

4x1アトラス。青い短マントの傭兵女性、黄土色装備の衛兵、暗色フードの斥候、
生成りと苔色の治療師。全員を同一縮尺・同一向きの戦闘待機姿勢で描き、
三・五〜四頭身の手描きピクセルアート、均一な`#ff00ff`背景、文字・UI・
ロゴなし。提供画像の固有キャラクターや衣装は複製しない。

## 再生成

```powershell
python tools/asset_gen/split_reference_prop_atlas.py
python tools/asset_gen/split_reference_character_atlas.py
python tools/asset_gen/gen_reference_terrain_textures.py
```

画像アトラスを再生成した場合は、先にimagegenスキルの
`remove_chroma_key.py`で`*_atlas_rgba.png`を作成してから分割する。
