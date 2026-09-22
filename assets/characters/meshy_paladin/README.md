# Blue Plume Paladin

Meshy製の騎士にBlenderで24本のボーンと歩行ループを付けたモデルです。
`samples/JRPGWorldSample.tscn` の操作キャラクターとして使用します。

- 高さ：約2.2 Godot単位。正面：+X。足元：Y=0。
- `idle`：両足を接地させた立ち姿。
- `walk`：32フレーム、24fps、1.333秒のその場歩き。
- 専用の走行クリップはなく、Shift移動時は歩行の再生速度を変更。
- 元のカラー（2K）、ノーマル（2K）、金属感／粗さ（4K）を保持。

再生成：`tools/export_meshy_paladin.py` をBlenderで実行します。
入力は `artifacts/meshy_paladin/blue_plume_paladin_walk.blend`。元のblendには上書きしません。
Godotの `animation/remove_immutable_tracks=false` は停止時の姿勢を正しく復元するために必要です。
