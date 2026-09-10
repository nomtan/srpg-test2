import { Mesh, MeshStandardMaterial, type Object3D } from "three";
import { PALETTE_SLOTS, type PaletteSlot } from "../../domain/constants.ts";
import { BASE_PALETTE_SLOTS, WORKSHOP_ASSETS, isHexColor, type Palette } from "../../domain/phase3.ts";

/** GLB material extras implement palette-map.json's material bindings. */
export function applyPalette(root: Object3D, palette: Palette): string[] {
  const warnings = new Set<string>();
  for (const [slot, color] of Object.entries(palette)) {
    if (!PALETTE_SLOTS.includes(slot as PaletteSlot)) warnings.add(`未定義Palette Slot: ${slot}`);
    if (!isHexColor(color)) warnings.add(`不正なColor値: ${slot}`);
  }
  root.traverse((node) => {
    if (!(node instanceof Mesh)) return;
    const owner = node.userData.assetId as string;
    const allowed = owner === "base_body" ? BASE_PALETTE_SLOTS : WORKSHOP_ASSETS.find((a) => a.id === owner)?.appearance.paletteSlots ?? [];
    for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
      const slot = material.userData.paletteSlot as PaletteSlot | undefined;
      if (!slot) { warnings.add(`Palette情報がありません: ${owner ?? node.name}`); continue; }
      if (!PALETTE_SLOTS.includes(slot)) { warnings.add(`未定義Palette Slot: ${slot}`); continue; }
      if (!allowed.includes(slot)) { warnings.add(`Assetが使用しないPalette Slot: ${owner}/${slot}`); continue; }
      if (material instanceof MeshStandardMaterial && isHexColor(palette[slot])) material.color.set(palette[slot]);
    }
  });
  return [...warnings];
}
