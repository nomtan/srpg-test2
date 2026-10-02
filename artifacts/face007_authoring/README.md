# Face007 手動分類作業

Blender MCP接続確認済み。Blender 5.1.2。
`face007-working.blend` の `Phase5_Face007_Authoring` シーンに原本のコピーを読み込んだ。
既存の初期Sceneは残している。原本GLBは変更していない。

## 現状

- mesh: `Face007_Working`
- material slot 0: 元の未分類材質（6,087 polygons）
- material slot 1: `Head`（未割当）
- material slot 2: `Hair`（未割当）
- Head/Hairの2材質は原本materialの複製で、texture / UV0を保持。
- UV継ぎ目で695島。重複頂点を仮想的につないだ非破壊の調査でも2成分（6,025面と62面）。
  Head/Hairの明示的な境界にはならないので自動分類していない。

## 操作

1. `Face007_Working` を選択してEdit Mode、Face Selectへ切り替える。
2. 頭・顔・耳・首のポリゴンを目視で選び、Material Propertiesの`Head`を選択しAssign。
3. 髪・前髪のポリゴンを選び、`Hair`を選択しAssign。
4. slot 0のSelectで未分類面を確認する。未分類面が0になるまで分類する。
5. このworking .blendへ保存し、Codexに「Head/Hairの割当完了」と知らせる。

UV0の編集・頂点merge・原本GLBへのexportは不要。
Head/Hair割当後、CodexがUV／mask制作、正規化、Validator、Godot組合せ・captureへ進む。
元依頼の「色・位置・法線から勝手にHairを推測して分類することは禁止」に従い、
このworking fileは未分類のまま正式アセット扱いにしていない。
