# 草アセット生成パイプライン整備 指示書

## 目的

コミット `78c6fb0a5006ae21e61e329f4ce788a788e23f95` で追加された草アセット生成処理を、特定のLinux一時環境に依存せず、Windowsを含むローカル開発環境から再実行できる正式なアセット生成パイプラインへ修正する。

対象ファイル：

* `tools/asset_gen/gen_grass_props.py`
* `tools/asset_gen/build_grass_props.py`
* `tools/asset_gen/palette.json`

必要に応じて追加するファイル：

* `requirements-asset-gen.txt`
* 草GLBを使用するGodotシーン
* MapVisualThemeおよびMapDecorationDataの拡張

---

## 1. 草PNG生成スクリプトの修正

`tools/asset_gen/gen_grass_props.py` を修正する。

### 必須要件

1. `/home/claude/props` の固定パスを完全に削除する。
2. `pathlib.Path` を使用する。
3. `argparse` で出力先を指定できるようにする。
4. デフォルト出力先は以下とする。

```text
assets/texture/grass
```

5. 出力先が存在しない場合は自動作成する。
6. `if __name__ == "__main__":` から `main()` を呼び出す構成にする。
7. 草色をPythonファイルへ直接記述せず、`tools/asset_gen/palette.json` から取得する。
8. 現在の生成結果を変更しない。既存のseed、草本数、高さ、枝分かれ確率を維持する。
9. 生成後に、生成したファイルの相対パスを標準出力へ表示する。

### コマンド仕様

次のコマンドで動作すること。

```powershell
python tools\asset_gen\gen_grass_props.py
```

または：

```powershell
python tools\asset_gen\gen_grass_props.py --out assets\texture\grass
```

### パレット修正

`palette.json` に穂先用の色を追加する。

例：

```json
{
  "grass": [
    "#3c5c2e",
    "#476b35",
    "#2f4a24",
    "#547a3d",
    "#284020",
    "#5c8449"
  ],
  "grass_prop_tip": [
    "#6b9455",
    "#7aa661"
  ]
}
```

既存のパレット項目を破壊しないこと。

---

## 2. 草GLB生成スクリプトの修正

`tools/asset_gen/build_grass_props.py` を修正する。

### 必須要件

1. `/home/claude/props` の固定パスを完全に削除する。
2. `pathlib.Path` を使用する。
3. Blenderスクリプト引数として以下を受け取る。

```text
--tex
--out
```

4. Blender自身の引数と区別するため、`--` 以降を解析する。
5. デフォルト値は設定せず、`--tex` と `--out` を必須としてよい。
6. 出力先ディレクトリを自動作成する。
7. 入力PNGが存在しない場合は、対象パスが分かる明確なエラーを出して終了する。
8. シーン初期化処理は既存の `build_terrain_glb.py` と同等の安全性を持たせる。
9. メッシュ、マテリアル、画像の不要データをアセットごとにクリアする。
10. アニメーションをエクスポートしない。
11. GLBの原点は底面中央とする。
12. `export_yup=True` を維持する。
13. アルファクリップ、両面描画、Closest補間を維持する。
14. 短草と長草のサイズを変更しない。

```text
prop_grass_short_01: 幅0.9、高さ0.45
prop_grass_tall_01:  幅0.9、高さ0.85
```

### コマンド仕様

次のコマンドで動作すること。

```powershell
blender --background ^
  --python tools\asset_gen\build_grass_props.py ^
  -- ^
  --tex assets\texture\grass ^
  --out assets\props\grass
```

PowerShellでも同等のコマンドで実行できること。

---

## 3. Python依存関係の追加

リポジトリ直下に以下を追加する。

```text
requirements-asset-gen.txt
```

内容：

```text
Pillow
```

READMEまたはアセット生成用ドキュメントに、次のセットアップ手順を追加する。

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-asset-gen.txt
```

`bpy` と `bmesh` はBlender内蔵モジュールなので、requirementsには追加しないこと。

---

## 4. 既存アセット生成処理との整合

既存の `gen_terrain_textures.py` および `build_terrain_glb.py` の実装方針に合わせる。

特に以下を統一する。

* `pathlib.Path`
* `argparse`
* `main()` エントリーポイント
* 出力フォルダの自動作成
* `palette.json` の利用
* Blenderの `--` 以降の引数解析
* 実行結果の標準出力

今回は草用ファイルを独立したまま整備してよい。

ただし、重複が大きくなる場合は、将来的に `build_terrain_glb.py` へ `cross` 種別として統合しやすい構造にすること。

---

## 5. Godot側への取り込み

短草と長草を別々に使用する場合は、以下を追加する。

### MapVisualTheme

現在の `grass_patch` だけでなく、次のPackedSceneを追加する。

```gdscript
@export var grass_short: PackedScene
@export var grass_tall: PackedScene
```

`decoration_scene_for()` に次を追加する。

```gdscript
"grass_short":
    return grass_short
"grass_tall":
    return grass_tall
```

既存の `grass_patch` は後方互換性のため削除しない。

### MapDecorationData

`kind` の選択肢を次のように拡張する。

```gdscript
@export_enum(
    "grass_patch",
    "grass_short",
    "grass_tall",
    "broken_stone",
    "flag_placeholder"
)
var kind := "grass_patch"
```

### 草シーン

次のシーンを作成する。

```text
assets/props/grass/prop_grass_short_01.tscn
assets/props/grass/prop_grass_tall_01.tscn
```

各シーンはNode3Dをルートとし、生成したGLBを子として配置する。

次を確認する。

* 原点が地面の高さに一致する
* スケールが1.0
* 草がセル外へ大きくはみ出さない
* 両面から表示される
* 透明部分に黒い縁が出ない
* 影が強すぎない

草が密集する用途を考慮し、必要であれば草マテリアルの影を無効化する。

---

## 6. 表示品質の確認

現在のマップ描画処理は、インスタンス化されたマテリアルにNearest＋Mipmapsを適用する。

1ピクセル幅の草は、カメラ距離によってMipmaps内で消える可能性があるため、次を確認する。

* 通常のゲームカメラ距離で草が消えない
* カメラ移動時に草が激しくちらつかない
* アルファクリップ部分にノイズが発生しない

問題がある場合のみ、草用マテリアルについて以下を検討する。

* Mipmapsを使用しないNearestフィルター
* アルファアンチエイリアス
* アルファしきい値の調整
* 草の主要部分を2ピクセル幅にする

地形全体のフィルター設定を変更せず、草アセットだけを対象とすること。

---

## 7. 完了条件

以下をすべて満たしたら完了とする。

1. `/home/claude/props` がコード内に残っていない。
2. Windowsから草PNGを再生成できる。
3. Blenderのバックグラウンド実行で草GLBを再生成できる。
4. 出力フォルダがなくても自動作成される。
5. PNG生成結果が現在コミットされている画像と同一になる。
6. GLBのサイズと原点が仕様どおりである。
7. Godotへインポートして透明部分と両面表示が正しく動く。
8. 短草と長草をマップ装飾として個別に指定できる。
9. 既存の地形アセット生成およびマップ表示を壊さない。
10. 実行方法をREADMEまたはアセット生成ドキュメントへ記載する。
