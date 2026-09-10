export const PREVIEW_SETS = ["default", "onehand_sword", "great_sword", "spear", "bow", "dagger", "staff"] as const;
export const ANIMATION_ROLES = ["idle", "walk", "run", "attack", "damage", "death", "skill"] as const;
export type PreviewSet = typeof PREVIEW_SETS[number];
export type AnimationRole = typeof ANIMATION_ROLES[number];
export interface AnimationMeaning { set: PreviewSet; action: AnimationRole }
export const animationMapping: Record<string, AnimationMeaning> = {
  "animation.walk_mcp_test": { set: "default", action: "walk" },
  "animation.run": { set: "default", action: "run" },
  "animation.onehand_sword_idle": { set: "onehand_sword", action: "idle" },
  "animation.onehand_sword_run": { set: "onehand_sword", action: "run" },
  "animation.onehand_sword_attack": { set: "onehand_sword", action: "attack" },
  "animation.great_sword_idle": { set: "great_sword", action: "idle" },
  "animation.great_sword_run": { set: "great_sword", action: "run" },
  "animation.gread_sword_attack": { set: "great_sword", action: "attack" },
  "animation.spear_idle": { set: "spear", action: "idle" },
  "animation.spear_run": { set: "spear", action: "run" },
  "animation.spear_attack": { set: "spear", action: "attack" },
  "animation.bow_idle": { set: "bow", action: "idle" },
  "animation.bow_run": { set: "bow", action: "run" },
  "animation.bow_attack": { set: "bow", action: "attack" },
  "animation.dagger_idle": { set: "dagger", action: "idle" },
  "animation.dagger_run": { set: "dagger", action: "run" },
  "animation.dagger_attack": { set: "dagger", action: "attack" },
};
/** Clip names baked into /generated-assets/base_body/model.glb by build:base. */
export const BAKED_BASE_CLIPS = [
  "animation.walk_mcp_test", "animation.run",
  "animation.onehand_sword_idle", "animation.onehand_sword_run", "animation.onehand_sword_attack",
  "animation.great_sword_idle", "animation.great_sword_run", "animation.gread_sword_attack",
  "animation.bow_idle", "animation.bow_run", "animation.bow_attack",
  "animation.spear_idle", "animation.spear_run", "animation.spear_attack",
  "animation.dagger_idle", "animation.dagger_run", "animation.dagger_attack",
] as const;

export function resolveAnimation(set: string, action: string, clips: readonly string[]) {
  const warnings: string[] = [];
  if (!PREVIEW_SETS.includes(set as PreviewSet)) warnings.push(`未定義Animation Set: ${set}`);
  for (const candidate of [...new Set([set, "default"])]) {
    const name = Object.keys(animationMapping).find((key) => animationMapping[key].set === candidate && animationMapping[key].action === action);
    if (name && clips.includes(name)) {
      if (candidate !== set) warnings.push(`${set}.${action} → default.${action}へFallback`);
      return { name, warnings };
    }
    if (name) warnings.push(`Animation Clipがありません: ${name}`);
  }
  warnings.push(`Animationがありません: ${set}.${action}（停止）`);
  return { name: null, warnings };
}
export const defaultLoop = (action: string) => ["idle", "walk", "run"].includes(action);
