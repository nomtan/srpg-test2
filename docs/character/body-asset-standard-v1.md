# Body Asset Standard v1

## Required Contract

- Standard: `ashen_character_v1`, version 1
- `Skeleton3D` / glTF Skin: exactly 1
- Skeleton: `humanoid_v1` と bone name、parent hierarchy、rest translation / rotation / scale が一致
- bone count: 65
- required bones: hips 系 root と `head`
- maximum influences: 4
- unweighted / zero-weight / invalid-joint vertices: 0
- required clips: `idle`, `walk`, `attack`, `hit`（追加 clip は許可）
- animation track は `humanoid_v1` joint を対象にする。
- render mesh transform は identity。
- 首は Body に含め、Face の頭部 geometry と接続する。Body の頭部表示を前提にしない。

## Reference Measurements

| ID | vertices | triangles | materials | textures | bounds W×H×D (m) |
|---|---:|---:|---:|---:|---|
| 001 | 11,188 | 11,843 | 1 | 1 | 0.9680 × 0.9627 × 0.5381 |
| 002 | 8,565 | 8,896 | 1 | 1 | 1.0299 × 0.9627 × 0.6048 |
| 003 | 8,898 | 9,210 | 1 | 1 | 0.9969 × 0.9627 × 0.5143 |
| 004 | 9,563 | 9,758 | 1 | 1 | 1.0440 × 0.9627 × 0.5603 |
| 005 | 10,977 | 11,324 | 1 | 1 | 1.0140 × 0.9627 × 0.4984 |
| 006 | 10,436 | 10,116 | 1 | 2 | 0.9589 × 0.9627 × 0.5482 |

全 Body は65 bones、全頂点 weighted、最大4 influences。4 clips の duration / track 数は `attack 1.033s/195`、`hit 0.833s/195`、`idle 2.033s/195`、`walk 1.033s/195` で一致した。

## Performance Budget

| metric | recommended | warning ceiling | hard limit |
|---|---:|---:|---:|
| vertices | 12,000 | 16,000 | 24,000 |
| triangles | 12,000 | 16,000 | 24,000 |
| materials | 1 | 2 | 4 |
| textures | 2 | 3 | 4 |
| texture side | 512 | 1,024 | 2,048 |

この値は Reference Set と最大60 battle units を根拠にする。absolute FPS は環境依存なので hard requirement にしない。

## Normalization

Normalizer は raw Body を直接上書きせず、`humanoid_v1.glb` を rig / weight donor として読み、transform、rest pose、weight、animation、toon material を正規化する。PBR normal / metallic / roughness はゲーム shader が利用しないため、新規アセットでは base color 以外の接続を除去する。Body001 は Reference Set の一例であり reference rig ではない。

