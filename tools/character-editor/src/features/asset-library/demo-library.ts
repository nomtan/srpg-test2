import type { AssetMetadata } from "@/domain/asset";
import { createAssetLibrary } from "./library";

const common = { specVersion: 1, assetVersion: 1, bodyTypes: ["adult"], appearance: { paletteSlots: [] }, hairPolicy: null, hideParts: [], model: "model.glb" } satisfies Partial<AssetMetadata>;
export const demoLibrary = createAssetLibrary([
  { metadata: { ...common, id: "demo_adult_001", name: "Adult · Block Study", type: "base" }, baseUrl: "/demo-assets/demo_adult_001" },
  { metadata: { ...common, id: "demo_sword_001", name: "Iron · Training Sword", type: "weapon", equipment: { slot: "main_hand", handling: "one_hand", animationSet: "onehand_sword", weaponType: "sword" }, attachment: { main: { assetPoint: "grip_main", characterSocket: "socket_hand_right" } } }, baseUrl: "/demo-assets/demo_sword_001" },
  { metadata: { ...common, id: "demo_shield_001", name: "Oak · Training Shield", type: "shield", equipment: { slot: "off_hand", handling: "off_hand" } }, baseUrl: "/demo-assets/demo_shield_001" },
]);
