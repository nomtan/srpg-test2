// Headless checks for the Phase 8 Variation Generator. Runs the real domain modules against a
// synthetic Asset Library, so the guarantees the UI relies on (determinism, weighting, asset
// compatibility, duplicate detection, locked reroll, impossible-preset detection) are verified
// without a browser.
//
//   node --import ./scripts/register-ts-alias.mjs scripts/verify-variation.mjs
import { emptyPreset, defaultPalettePlan, bodyScaleForProfile } from "../src/domain/variation-preset.ts";
import { defaultPaletteLibrary } from "../src/domain/variation-palette.ts";
import { generateVariations, rerollVariation, variationSignature } from "../src/domain/variation-generator.ts";
import { validatePreset } from "../src/domain/variation-validation.ts";
import { resolveWeight } from "../src/domain/variation-candidates.ts";

const fail = [];
const ok = (cond, msg) => { console.log(`${cond ? "PASS" : "FAIL"}: ${msg}`); if (!cond) fail.push(msg); };

// ---- synthetic asset library -------------------------------------------------
const asset = (o) => ({
  bodyTypes: ["adult"], tags: [], hairPolicy: null, hideParts: [], hasModel: true,
  thumbnailUrl: null, name: o.id, ...o,
});
const ASSETS = [
  asset({ id: "base_body", type: "base" }),
  asset({ id: "hair_short_001", type: "hair", tags: ["human", "male_style"], weight: 10 }),
  asset({ id: "hair_long_001", type: "hair", tags: ["human", "female_style"], weight: 2 }),
  asset({ id: "hair_elf_001", type: "hair", tags: ["elf"], rarity: "rare" }),
  asset({ id: "helm_kingdom_001", type: "headgear", tags: ["kingdom", "soldier"], hairPolicy: "hide" }),
  asset({ id: "armor_kingdom_001", type: "chest_armor", tags: ["kingdom", "soldier", "medium"] }),
  asset({ id: "armor_kingdom_002", type: "chest_armor", tags: ["kingdom", "soldier", "light"], rarity: "uncommon" }),
  asset({ id: "pauldron_left_001", type: "shoulder_left", tags: ["kingdom"] }),
  asset({ id: "pauldron_right_001", type: "shoulder_right", tags: ["kingdom"] }),
  asset({ id: "sword_kingdom_001", type: "weapon", tags: ["kingdom"], equipmentless: true, weaponType: "sword", handling: "one_hand", animationSet: "onehand_sword" }),
  asset({ id: "spear_kingdom_001", type: "weapon", tags: ["kingdom"], weaponType: "spear", handling: "two_hand", animationSet: "spear" }),
  asset({ id: "bow_kingdom_001", type: "weapon", tags: ["kingdom"], weaponType: "bow", handling: "two_hand", animationSet: "bow" }),
  asset({ id: "shield_kingdom_001", type: "shield", tags: ["kingdom"], handling: "off_hand" }),
  asset({ id: "armor_child_001", type: "chest_armor", bodyTypes: ["child"], tags: ["villager"] }),
  asset({ id: "armor_nomodel_001", type: "chest_armor", tags: ["kingdom"], hasModel: false }),
];
const PALETTES = defaultPaletteLibrary();
const base = (patch = {}) => {
  const p = emptyPreset("test_preset");
  return {
    ...p, palette: defaultPalettePlan("kingdom"), idPrefix: "test", namePrefix: "Test",
    count: 20, seed: 4242, shoulderMode: "both", ...patch,
    slots: { ...p.slots, ...(patch.slots ?? {}) },
  };
};
const rule = (o) => ({ presence: "optional", probability: 0.5, tags: [], excludeTags: [], assetIds: [], weaponTypes: [], weights: {}, ...o });
const input = (preset, taken = new Set()) => ({ preset, assets: ASSETS, palettes: PALETTES, takenIds: taken });

// ---- 1. Determinism (spec section 20) ---------------------------------------
const soldier = base({
  slots: {
    hair: rule({ presence: "optional", probability: 0.8, tags: ["human"] }),
    chestArmor: rule({ presence: "required", tags: ["kingdom"] }),
    mainHand: rule({ presence: "required", weaponTypes: ["sword", "spear"] }),
    offHand: rule({ presence: "optional", probability: 0.5 }),
  },
});
const runA = generateVariations(input(soldier));
const runB = generateVariations(input(soldier));
const sigs = (r) => r.variations.map((v) => v.signature).join("\n");
ok(runA.variations.length === 20, `generated 20 variations (got ${runA.variations.length})`);
ok(sigs(runA) === sigs(runB), "same preset + seed reproduces the identical batch");
const runSeed = generateVariations(input({ ...soldier, seed: 99 }));
ok(sigs(runSeed) !== sigs(runA), "a different seed produces a different batch");
ok(
  runA.variations.every((v) => v.recipe.generation.seed === soldier.seed && v.recipe.generation.preset === "test_preset"),
  "generation metadata records preset + seed on every recipe",
);

// ---- 2. Ids / names (spec section 22-23) ------------------------------------
ok(runA.variations[0].id === "test_001" && runA.variations[19].id === "test_020", "ids are prefix_NNN sequential");
ok(new Set(runA.variations.map((v) => v.id)).size === 20, "ids are unique inside a batch");
const collide = generateVariations(input(soldier, new Set(["test_001", "test_002"])));
ok(collide.variations[0].id === "test_003", "existing Character ids are skipped");
ok(runA.variations[0].name === "Test 001", "display name follows the preset name prefix");

// ---- 3. Compatibility (spec section 11-13) ----------------------------------
ok(runA.variations.every((v) => v.recipe.assets.chestArmor !== "armor_nomodel_001"), "assets without model.glb are never selected");
ok(runA.variations.every((v) => v.recipe.assets.chestArmor !== "armor_child_001"), "assets for another bodyType are never selected");
ok(
  runA.variations.every((v) => ["sword_kingdom_001", "spear_kingdom_001"].includes(v.recipe.assets.mainHand)),
  "weapon type restriction (sword / spear) is respected",
);
const twoHandCases = runA.variations.filter((v) => v.recipe.assets.mainHand === "spear_kingdom_001");
ok(twoHandCases.length > 0, `two-hand weapons do occur (${twoHandCases.length})`);
ok(twoHandCases.every((v) => !v.recipe.assets.offHand), "two-hand main hand always clears the off hand");

const bowPreset = base({
  count: 10,
  slots: { mainHand: rule({ presence: "required", weaponTypes: ["bow"] }), offHand: rule({ presence: "optional", probability: 1 }) },
});
const bowRun = generateVariations(input(bowPreset));
ok(bowRun.variations.every((v) => v.recipe.assets.mainHand === "bow_kingdom_001" && !v.recipe.assets.offHand),
  "bow (two-hand) + 100% off hand still yields no off hand");

const forbidden = generateVariations(input(base({
  count: 10,
  slots: { back: rule({ presence: "forbidden" }), hair: rule({ presence: "required", tags: ["human"] }) },
})));
ok(forbidden.variations.every((v) => !v.recipe.assets.back), "forbidden category is never filled");
ok(forbidden.variations.every((v) => !!v.recipe.assets.hair), "required category is always filled");

// Headgear with hairPolicy hide suppresses an optional hairstyle.
const hatRun = generateVariations(input(base({
  count: 20,
  slots: {
    headgear: rule({ presence: "required", tags: ["kingdom"] }),
    hair: rule({ presence: "optional", probability: 1, tags: ["human"] }),
  },
})));
ok(hatRun.variations.every((v) => v.recipe.assets.headgear === "helm_kingdom_001" && !v.recipe.assets.hair),
  "hairPolicy hide headgear suppresses optional hair");

// ---- 4. Probability + weights (spec section 9-10, 14-15) --------------------
const never = generateVariations(input(base({ count: 20, slots: { hair: rule({ probability: 0 }) } })));
ok(never.variations.every((v) => !v.recipe.assets.hair), "probability 0 never equips");
const always = generateVariations(input(base({
  count: 20,
  slots: { hair: rule({ probability: 1, tags: ["human"] }), headgear: rule({ presence: "forbidden" }) },
})));
ok(always.variations.every((v) => !!v.recipe.assets.hair), "probability 1 always equips (no hair-hiding headgear)");

const weighted = generateVariations(input(base({
  count: 100, seed: 7, slots: { hair: rule({ presence: "required", tags: ["human"] }) },
})));
const shortCount = weighted.variations.filter((v) => v.recipe.assets.hair === "hair_short_001").length;
const longCount = weighted.variations.filter((v) => v.recipe.assets.hair === "hair_long_001").length;
ok(shortCount > longCount * 2, `weight 10 beats weight 2 (${shortCount} vs ${longCount})`);
ok(resolveWeight(ASSETS.find((a) => a.id === "hair_elf_001")) === 1, "rarity rare converts to weight 1");
ok(resolveWeight(ASSETS.find((a) => a.id === "armor_kingdom_002")) === 4, "rarity uncommon converts to weight 4");
ok(resolveWeight(ASSETS.find((a) => a.id === "armor_kingdom_001")) === 10, "no rarity defaults to common weight 10");
ok(resolveWeight(ASSETS.find((a) => a.id === "hair_elf_001"), rule({ weights: { hair_elf_001: 50 } })) === 50,
  "preset weight override wins over rarity");

// ---- 5. Body scale (spec section 6-7) ---------------------------------------
const scaled = generateVariations(input(base({
  count: 30, bodyScale: bodyScaleForProfile("wide_variation"),
  slots: { mainHand: rule({ presence: "forbidden" }) },
})));
const inRange = scaled.variations.every((v) => {
  const s = v.recipe.body.scale;
  return [s.height, s.bodyWidth, s.headScale].every((x) => x >= 0.85 && x <= 1.15);
});
ok(inRange, "body scale always lands inside the 0.85 - 1.15 safety clamp");
ok(new Set(scaled.variations.map((v) => v.recipe.body.scale.bodyWidth)).size > 3, "wide_variation actually varies the body width");

// ---- 6. Duplicate detection (spec section 28) -------------------------------
const tiny = [asset({ id: "base_body", type: "base" }), asset({ id: "only_armor", type: "chest_armor", tags: ["kingdom"] })];
const rigid = base({
  count: 5,
  bodyScale: { profile: "custom", height: { min: 1, max: 1 }, bodyWidth: { min: 1, max: 1 }, headScale: { min: 1, max: 1 } },
  palette: { ...defaultPalettePlan("kingdom"), slots: Object.fromEntries(
    ["primary", "secondary", "metal", "leather", "hair", "skin"].map((s) => [s, { mode: "fixed", fixed: "#123456" }]),
  ) },
  slots: Object.fromEntries(Object.keys(base().slots).map((s) => [s, rule({ presence: s === "chestArmor" ? "required" : "forbidden" })])),
});
const dupRun = generateVariations({ preset: rigid, assets: tiny, palettes: PALETTES, takenIds: new Set() });
ok(dupRun.duplicates === 4, `identical rules flag 4 duplicates out of 5 (got ${dupRun.duplicates})`);
ok(dupRun.variations.filter((v) => v.duplicate).every((v) => v.warnings.some((w) => w.startsWith("Duplicate Variation"))),
  "duplicates carry a Duplicate Variation warning");

// ---- 7. Reroll + locks (spec section 26-27) ---------------------------------
const target = runA.variations[6];
const others = new Set(runA.variations.filter((v) => v.id !== target.id).map((v) => v.signature));
const rerolled = rerollVariation(input(soldier), target, ["chestArmor", "palette"], others);
ok(rerolled.ok, "reroll succeeds");
ok(rerolled.variation.recipe.assets.chestArmor === target.recipe.assets.chestArmor, "locked Armor survives the reroll");
ok(JSON.stringify(rerolled.variation.recipe.palette) === JSON.stringify(target.recipe.palette), "locked Palette survives the reroll");
ok(rerolled.variation.salt === target.salt + 1, "reroll bumps only this character's salt");
ok(rerolled.variation.id === target.id && rerolled.variation.index === target.index, "reroll keeps the character id / index");
const untouched = generateVariations(input(soldier));
ok(sigs(untouched) === sigs(runA), "re-running the batch after a reroll reproduces the original characters");

// ---- 8. Preset validation / impossible rules (spec section 43-44) -----------
const vctx = { assets: ASSETS, palettes: PALETTES, otherPresetIds: [] };
const good = validatePreset(soldier, vctx);
ok(good.canGenerate, `valid preset passes validation (${good.issues.map((i) => i.message).join(" | ")})`);

const impossible = validatePreset(base({
  slots: { mainHand: rule({ presence: "required", weaponTypes: ["bow"] }), offHand: rule({ presence: "required" }) },
}), vctx);
ok(!impossible.canGenerate && impossible.issues.some((i) => i.code === "impossible"),
  "required bow + required off hand is reported as impossible before generating");

const noCandidate = validatePreset(base({
  slots: { chestArmor: rule({ presence: "required", tags: ["does_not_exist"] }) },
}), vctx);
ok(!noCandidate.canGenerate && noCandidate.issues.some((i) => i.code === "no_candidate"),
  "required category with 0 candidates is an error");

const badRange = validatePreset(base({
  bodyScale: { profile: "custom", height: { min: 1.1, max: 0.9 }, bodyWidth: { min: 1, max: 1 }, headScale: { min: 1, max: 1 } },
}), vctx);
ok(badRange.issues.some((i) => i.code === "scale_range"), "min > max is reported");

const badPalette = validatePreset(base({ palette: defaultPalettePlan("no_such_set") }), vctx);
ok(badPalette.issues.some((i) => i.code === "palette_set"), "missing Palette Set is reported");

const dupId = validatePreset(base(), { ...vctx, otherPresetIds: ["test_preset"] });
ok(dupId.issues.some((i) => i.code === "id_duplicate"), "duplicate Preset ID is reported");

const badCount = validatePreset(base({ count: 500 }), vctx);
ok(badCount.issues.some((i) => i.code === "count"), "count beyond 100 is refused");

// ---- 9. Generation failure is contained (spec section 45) -------------------
const starved = generateVariations({
  preset: base({ count: 5, slots: { chestArmor: rule({ presence: "required", tags: ["kingdom"] }) } }),
  assets: [asset({ id: "base_body", type: "base" })],
  palettes: PALETTES,
  takenIds: new Set(),
});
ok(starved.variations.length === 0 && starved.failures.length === 5, "an unsatisfiable required slot fails per character instead of throwing");
ok(starved.failures.every((f) => f.reason.includes("chestArmor")), "failure reason names the slot");

// ---- 10. Palette comes from the curated sets (spec section 18-19) -----------
const kingdom = PALETTES.sets.find((s) => s.id === "kingdom");
ok(runA.variations.every((v) => kingdom.colors.primary.includes(v.recipe.palette.primary)),
  "primary colour always comes from the Palette Set");
ok(runA.variations.every((v) => PALETTES.skinPool.includes(v.recipe.palette.skin)),
  "skin colour always comes from the Skin Pool");
ok(new Set(runA.variations.map((v) => v.recipe.palette.skin)).size > 1, "skin colour actually varies");
ok(runA.variations.every((v) => variationSignature(v.recipe) === v.signature), "signatures match their recipes");

console.log(`\n${fail.length ? `FAILED (${fail.length})` : "ALL PASS"} — Phase 8 Variation Generator`);
process.exit(fail.length ? 1 : 0);
