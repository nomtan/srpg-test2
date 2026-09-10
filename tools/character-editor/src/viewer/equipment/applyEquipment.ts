import type { Object3D } from "three";
import type { CharacterRecipe } from "../../domain/character-recipe";
import { WORKSHOP_ASSETS, assetById } from "../../domain/phase3.ts";

/** Authored groups already follow the rig; fixtures are parented to app sockets offline. */
export function applyEquipment(root: Object3D, recipe: CharacterRecipe): string[] {
  const selected = new Set(Object.values(recipe.assets).filter(Boolean));
  const nodes = new Map<string, Object3D>();
  root.traverse((node) => { if (node.userData.bindingRoot) nodes.set(node.userData.bindingRoot, node); });
  const hideHair = recipe.assets.headgear && assetById(recipe.assets.headgear)?.hairPolicy === "hide";
  const warnings: string[] = [];
  for (const asset of WORKSHOP_ASSETS) for (const name of asset.binding.roots) {
    const node = nodes.get(name);
    if (!node) { warnings.push(`装備Groupがありません: ${name}`); continue; }
    node.visible = selected.has(asset.id) && !(asset.type === "hair" && hideHair);
  }
  const weapon = recipe.assets.mainHand && assetById(recipe.assets.mainHand);
  if (weapon && weapon.equipment?.handling === "two_hand" && recipe.assets.offHand) warnings.push("両手武器とShieldを同時選択しています。手のConstraint・干渉解決は未対応です。");
  return warnings;
}
