# キャラクターアニメーションのGUI編集

## Normal Attack

1. Godotで `male_front_left.tscn` を開く。
2. シーンツリーの `AnimationPlayer` を選択する。
3. 画面下部のAnimationパネルで `authored/attack` を選択する。
4. タイムラインを再生し、次の2トラックのキーを編集する。
   - `ArmRUpper:rotation_degrees`
   - `ArmRLower:rotation_degrees`
5. 編集後は `character_attack_animations.tres` を保存する。

`attack` は起動時にコードから再生成されないため、GUIで編集したキーは保持される。
Male／FemaleとFront／Backは同じノード構造を利用するため、このアニメーションが4体すべてに適用される。

現在のタイミングは次の通り。

- 0.0〜0.5秒: 振り上げ
- 0.5〜1.5秒: 構えたまま停止
- 1.5秒: 中間フレームなしで振り下ろし
- 1.666667秒: Idleへ復帰

IdleとWalkは体格・方向ごとの足固定位置を計算するため、引き続き実行時生成としている。
