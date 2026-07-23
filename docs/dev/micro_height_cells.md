# 3x3 micro-height terrain cells

`MapCellVisualData` can optionally store nine row-major `micro_heights` values:

```text
index:  0 1 2
        3 4 5
        6 7 8
```

Each value is clamped to `0`, `1`, or `2`. These are the lower, middle, and
upper thirds of the cell's current logical height level. An empty array keeps
the legacy one-block rendering path, so existing stage data is unchanged.

Example staircase rising northward:

```gdscript
cell.height = 2
cell.set_micro_height_profile(PackedInt32Array([
    2, 2, 2,
    1, 1, 1,
    0, 0, 0,
]))
```

The nine values are a compact height field representing up to 27 stacked
micro-cubes. `VoxelMap` currently emits one rectangular column per value,
which gives the same visible result with nine meshes instead of 27.

This subdivision is visual only. Movement, occupancy, range, and pathfinding
continue to use the parent cell and its integer `height`. Grass overlays and
grass-to-dirt transition planes are omitted on subdivided cells until they can
sample the micro-height surface without floating across steps.

`flat_validation.gd` places 18 canonical profiles in a spaced gallery on the
screen's left-rear terrace: three flat levels, four cardinal stairs, four
diagonal stairs, peak, pit, vertical/horizontal ridges, two saddles, and an L
corner. This is the practical visual test set; the literal exhaustive set
would contain `3^9 = 19,683` combinations.
