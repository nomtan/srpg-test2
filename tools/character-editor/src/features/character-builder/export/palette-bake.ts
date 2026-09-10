// Palette bake (spec section 10 / prompt 10): the exported GLB carries the palette as material
// baseColorFactor, and this PNG is the human-readable "final texture" companion so the file always
// exists and matches the Three.js preview colours 1:1. v1 does not do per-texel palette-swap bake.
import { PALETTE_SLOTS, type PaletteSlot } from "@/domain/constants";

export const PALETTE_TEXTURE_SIZE = 64;

export interface PaletteBakeResult {
  blob: Blob;
  dataUrl: string;
  /** Pixel row range (y0..y1) each slot occupies, so Godot / future assets can sample it. */
  regions: Record<PaletteSlot, [number, number]>;
}

export async function bakePaletteTexture(palette: Record<string, string>): Promise<PaletteBakeResult> {
  const size = PALETTE_TEXTURE_SIZE;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas コンテキストを取得できませんでした。");
  ctx.imageSmoothingEnabled = false;

  const band = Math.floor(size / PALETTE_SLOTS.length);
  const regions = {} as Record<PaletteSlot, [number, number]>;
  PALETTE_SLOTS.forEach((slot, i) => {
    const y0 = i * band;
    const y1 = i === PALETTE_SLOTS.length - 1 ? size : y0 + band;
    ctx.fillStyle = /^#[0-9a-f]{6}$/i.test(palette[slot] ?? "") ? palette[slot] : "#808080";
    ctx.fillRect(0, y0, size, y1 - y0);
    regions[slot] = [y0, y1];
  });

  const blob = await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("PNG 生成に失敗しました。"))), "image/png");
  });
  const dataUrl = canvas.toDataURL("image/png");
  return { blob, dataUrl, regions };
}
