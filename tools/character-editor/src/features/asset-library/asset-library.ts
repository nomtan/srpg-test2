import { createAssetLibrary } from "./library";
import { demoLibrary } from "./demo-library";
import { BASE_COORDINATES } from "@/domain/base-rig";

export const assetLibrary = createAssetLibrary([
  {
    metadata: {
      specVersion: 1, assetVersion: 1, id: "base_body", name: "Base Body · base_1.bbmodel",
      type: "base", bodyTypes: ["adult"], appearance: { paletteSlots: [] }, hairPolicy: null,
      hideParts: [], model: "model.glb",
      source: { format: "bbmodel", path: BASE_COORDINATES.source },
    },
    baseUrl: "/generated-assets/base_body", provenance: "source",
  },
  ...demoLibrary.ids.filter((id) => demoLibrary.byId[id].metadata.type !== "base").map((id) => ({ ...demoLibrary.byId[id], provenance: "demo" as const })),
]);
