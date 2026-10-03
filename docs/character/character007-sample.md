# Character007（modular化 + 刀）

旧walk-onlyサンプル（`generated/character007/character.glb`、Body007の元Mixamoリグ）を廃止し、
Character001〜006と同じmodular経路へ移行した。

```text
scenes/characters/tripo_roster/character007.tscn
  → definitions/character007.tres (body007 + face007)
  → CharacterAssembler → humanoid_v1 Skeleton + FaceSocket(head)
```

## Body007

- 原本（2026-10-04更新）はリグなしの静的メッシュ（7,000三角形 / 1材質）。001〜006と同じくhumanoid_v1へ高さ合わせ＋ウェイト転写、4 clips生成。
- 旧原本は65骨Mixamoリグ付き・41k三角形だったため `source_rig: discard` と `decimate_ratio: 0.23` を使っていたが、
  現原本では不要なので `normalization.json` から削除した（`build_modular_parts.py` 側のオプションは残してある）。

## Face007

- 001〜006と同じ横幅（0.4195m、scale .54）。Face007は同じ幅で奥行き・高さが約25%大きく、
  旧配置では顔前面が他より約5cm前に出ていた（「Faceが前にずれる」の原因）。
- position を `[0, -0.055, 0.89]` → `[0, -0.01, 0.86]`（後ろ4.5cm・下3cm）とし、側面で耳と顎が首の上に来る位置へ補正。
  bounds中心のzは後ろ髪（ポニーテール）のため推奨範囲外のWARNINGになるが、顔面位置は001〜006と揃う。
- Head/Hair分離とExpressionUV authoringは未実施のため、001〜006と同じlegacy_projectionで運用する
  （`character_asset_standard_v1.json` の `legacy_combined_ids` に007を追加）。表情は `legacy_size007_007` profile。

## 刀（`SwordCombat` loadout `katana`）

- `assets/weapons/katana/001/model.glb`（抜き身）、`saya.model.glb`（納刀状態）、
  `scabbard.glb`（`tools/asset_gen/build_katana_scabbard.py` が saya から鍔下で切り出した空の鞘）。
- 待機・歩行・被弾中は左腰に納刀。攻撃・防御clipで柄に手をかけたkey（`KT_HILT`）から抜き身＋空鞘へ切替え、
  納刀keyで戻す。鞘は柄keyの手の位置から逆算して骨盤に付けるので、切替えは見た目上連続する。
- clip: `katana/iai`（抜刀横薙ぎ・片手、通常攻撃）、`katana/kesa`（両手袈裟斬り、強攻撃）、`katana/guard`（中段構え）。

検証: `scripts/world_jrpg/verify_character007.gd`（`-- --capture` で `artifacts/katana/` に撮影）、
`verify_tripo_switching.gd`、`verify_modular_parts.gd`、`validate_modular_parts.py`。
Face配置比較: `tools/asset_gen/character_pipeline/capture_character007.gd` → `artifacts/character007/lineup_{front,side}.png`。
