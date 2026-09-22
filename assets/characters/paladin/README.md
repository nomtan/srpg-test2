# Paladin

参考画像をもとに Blender MCP で作成した、白銀の鎧・金の装飾・青い布地のブロック調パラディンです。

## ファイル

- `paladin.blend` — 編集用。`PALADIN | Studio` シーンにキャラクター、照明、前後のカメラを収録。
- `paladin.glb` — キャラクターのみのマテリアル付き glTF。背景・カメラ・照明を除外。
- `paladin_front.png` / `paladin_rear.png` — 1400 × 1400 の前後のレンダリング。
- `asset_report.json` — メッシュ数・三角形数・形状の検証結果。
- [create_paladin_blender.py](../../../tools/create_paladin_blender.py) — 再生成用の Blender Python スクリプト。

## 構成

兜、胴、左右の脚、腕、手、前掛け、マント、剣、盾をオブジェクト階層で分割しています。剣と盾はそれぞれ手の子オブジェクトです。兜のスリットは形状として開いており、盾の十字・背面ストラップ・マントの金十字も立体です。

全高は 2.20 m、原点は足元中央。Blender での正面は -Y、GLB では +Z です。234 メッシュ、ベベル適用後 12,470 三角形、15 マテリアル。各パーツは閉じたメッシュとして検証済みです。

静止モデルです。スケルトン、スキニング、アニメーションは含みません。色はマテリアルで設定しており、画像テクスチャへの依存はありません。ゲーム内への組み込みは行っていません。

## 編集・再生成

Blender で `paladin.blend` を開くと前面カメラが有効になります。背面は `Camera | Rear three-quarter` をアクティブカメラに指定してください。正投影の前面・背面カメラもあります。

スクリプトを Blender のテキストエディターで開いて実行するか、リポジトリ直下から次のコマンドを実行できます。

```text
blender --background --python tools/create_paladin_blender.py
```

新しいシーンを作成して `.blend` と `.glb` を保存します。PNG は各カメラからレンダリングしてください。同じ出力先のファイルは再生成時に更新されます。

画像を個別に出力する場合は次のコマンドを使用できます。前面は末尾の `rear` を `front` に変更してください。

```text
blender --background assets/characters/paladin/paladin.blend --python tools/render_paladin_blender.py -- rear
```
