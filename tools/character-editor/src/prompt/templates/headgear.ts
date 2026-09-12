// Headgear / head accessory prompt rules (spec section 32).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

export const headgearTemplate: TypeTemplate = {
  geometry: (ctx) => [
    "Fit the existing head dimensions without clipping through the skull.",
    `hairPolicy: ${ctx.hairPolicy ?? "(unset)"} — ${
      ctx.hairPolicy === "hide"
        ? "the hair asset is hidden while this is equipped, so the inside of the helmet must read as filled"
        : "the hair asset stays visible, so leave room above the skull and do not enclose the head"
    }.`,
    "Face visibility: keep eyes and the front of the face readable unless the design is a full helm.",
    "Head clearance: leave a small gap over the crown so hair or a hood can coexist.",
    "Attach at the head socket; the piece must be centred on the socket, not offset by hand.",
  ],
  negatives: () => [
    ...onlyThisAsset("headgear", ["face", "hair", "body", "armor", "weapon"]),
    "Do not model a head inside the helmet.",
    "Do not extend the piece below the neck.",
  ],
  texture: () => [
    "Separate metal / cloth / leather regions cleanly by UV island so each maps to one palette slot.",
    "Rivets and trim at most 1px wide.",
    "Keep the face opening a hard-edged shape; no soft shading around it.",
  ],
};

export const headAccessoryTemplate: TypeTemplate = {
  geometry: () => [
    "Small accessory (ornament, band, pin, feather) that coexists with hair and headgear.",
    "Must not clip through the head or flatten the hair silhouette.",
    "Keep the footprint small; the silhouette contribution should be a single readable shape.",
    "Attach at socket_head, centred on the socket.",
  ],
  negatives: () => [
    ...onlyThisAsset("head accessory", ["face", "hair", "helmet", "body", "weapon"]),
    "Do not add detail smaller than one texture pixel at the target resolution.",
  ],
  texture: () => [
    "Few, large, readable colour areas; avoid fine detail that disappears at isometric distance.",
    "One accent palette slot carries the colour identity.",
  ],
};
