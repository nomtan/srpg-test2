"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { CharacterRecipe } from "@/domain/character-recipe";
import { ANIMATION_SETS, PALETTE_SLOTS, type PaletteSlot } from "@/domain/constants";
import { EXPORT_ASSET_SLOTS, type ExportAssetSlot } from "@/domain/character-export";
import {
  SLOT_CATEGORY, SLOT_LABEL, SLOT_SOCKET, SCALE_MIN, SCALE_MAX, clampScale,
  emptyRecipe, validateRecipeShape, recipeText,
} from "@/domain/builder-recipe";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { downloadBlob } from "@/features/asset-creator/zip";
import { BuilderLibrarySave } from "@/features/library/builder-save";
import { CharacterPreview } from "./character-preview";
import { ExportPanel } from "./export/export-panel";
import { BUILDER_NAME_KEY, BUILDER_RECIPE_KEY, readStagedName } from "./builder-storage";

const RECIPE_KEY = BUILDER_RECIPE_KEY;
const ANIM_ROLES = ["idle", "walk", "run", "attack"] as const;
const ANIM_SETS = ["default", ...ANIMATION_SETS] as const;
const SCALE_KEYS = [
  ["height", "Height"], ["bodyWidth", "Body Width"], ["headScale", "Head Scale"],
] as const;

function loadStoredRecipe(): CharacterRecipe {
  if (typeof window === "undefined") return emptyRecipe();
  try {
    const raw = window.localStorage.getItem(RECIPE_KEY);
    if (!raw) return emptyRecipe();
    const parsed = validateRecipeShape(JSON.parse(raw));
    return parsed.recipe ?? emptyRecipe();
  } catch {
    return emptyRecipe();
  }
}

export function BuilderScreen() {
  const library = useMergedLibrary();
  const [recipe, setRecipe] = useState<CharacterRecipe>(emptyRecipe);
  const [charName, setCharName] = useState("Vein");
  const [animSetOverride, setAnimSetOverride] = useState<string | null>(null);
  const [animRole, setAnimRole] = useState<(typeof ANIM_ROLES)[number]>("idle");
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [loop, setLoop] = useState(true);
  const [captureSignal, setCaptureSignal] = useState(-1);
  const [thumb, setThumb] = useState<string | null>(null);
  const [previewWarnings, setPreviewWarnings] = useState<string[]>([]);
  const [previewNotices, setPreviewNotices] = useState<string[]>([]);
  const [restSize, setRestSize] = useState<[number, number, number] | null>(null);
  const [recipeMsg, setRecipeMsg] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const hydrated = useRef(false);

  useEffect(() => {
    // Deferred so the first client paint matches SSR (empty recipe), then hydrate from storage.
    queueMicrotask(() => {
      setRecipe(loadStoredRecipe());
      setCharName((n) => readStagedName(n));
      hydrated.current = true;
    });
  }, []);
  useEffect(() => {
    if (!hydrated.current) return;
    try { window.localStorage.setItem(RECIPE_KEY, recipeText(recipe)); } catch { /* quota — non-fatal */ }
  }, [recipe]);
  useEffect(() => {
    if (!hydrated.current) return;
    try { window.localStorage.setItem(BUILDER_NAME_KEY, charName); } catch { /* quota — non-fatal */ }
  }, [charName]);

  // Weapon Animation Set (spec section 14): follow the equipped main-hand weapon unless overridden.
  const weaponSet = useMemo(() => {
    const id = recipe.assets.mainHand;
    const set = id ? library.byId[id]?.metadata.equipment?.animationSet : undefined;
    return set && (ANIMATION_SETS as readonly string[]).includes(set) ? set : "default";
  }, [recipe.assets.mainHand, library]);
  const activeAnimationSet = animSetOverride ?? weaponSet;

  const patchRecipe = useCallback((patch: Partial<CharacterRecipe>) => setRecipe((r) => ({ ...r, ...patch })), []);
  const setSlot = (slot: ExportAssetSlot, value: string | null) =>
    setRecipe((r) => ({ ...r, assets: { ...r.assets, [slot]: value } }));
  const setScale = (key: "height" | "bodyWidth" | "headScale", value: number) =>
    setRecipe((r) => ({ ...r, body: { ...r.body, scale: { ...r.body.scale, [key]: clampScale(value) } } }));
  const setPalette = (slot: PaletteSlot, value: string) =>
    setRecipe((r) => ({ ...r, palette: { ...r.palette, [slot]: value } }));

  const optionsFor = useCallback((slot: ExportAssetSlot) => {
    const cats = SLOT_CATEGORY[slot];
    return library.ids
      .map((id) => library.byId[id])
      .filter((e) => cats.includes(e.metadata.type));
  }, [library]);

  function saveRecipe() {
    downloadBlob(new Blob([recipeText(recipe)], { type: "application/json" }), `${recipe.id || "character"}.recipe.json`);
  }
  function loadRecipe(file: File | undefined) {
    if (!file) return;
    file.text().then((text) => {
      let parsed;
      try { parsed = validateRecipeShape(JSON.parse(text)); }
      catch { setRecipeMsg("Recipe を JSON として解析できませんでした。"); return; }
      if (!parsed.recipe) { setRecipeMsg(`Recipe 読み込みエラー: ${parsed.issues.find((i) => i.level === "error")?.message ?? "不正な Recipe"}`); return; }
      setRecipe(parsed.recipe);
      setAnimSetOverride(null);
      const warnings = parsed.issues.filter((i) => i.level === "warning");
      setRecipeMsg(warnings.length ? `読み込みました（警告 ${warnings.length} 件: ${warnings[0].message}）` : "Recipe を読み込みました。");
    });
  }
  function resetRecipe() {
    setRecipe(emptyRecipe());
    setAnimSetOverride(null);
    setRecipeMsg("Recipe を初期状態に戻しました。");
  }

  const baseEntry = library.byId[recipe.body.assetId ?? "base_body"];
  const equippedCount = EXPORT_ASSET_SLOTS.filter((s) => recipe.assets[s]).length;

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">CHARACTER WORKSPACE</p>
          <h1>Character Builder</h1>
          <p>base_1.bbmodel を基準に装備・Palette・Scale・Animation を合成し、Godot 向け Baked Character として Export します。</p>
        </div>
        <span className="badge">PHASE 5 · GODOT EXPORT · {equippedCount} EQUIPPED</span>
      </div>

      <div className="builder-workspace">
        {/* ---- Slots ---- */}
        <section className="panel builder-slots">
          <div className="panel-heading"><h2>Assets</h2><span className="count">{library.ids.length}</span></div>
          <div className="slot-list">
            <div className="slot-row base-row">
              <span className="slot-label">Base Body</span>
              <span className="slot-fixed">{baseEntry?.metadata.name ?? "— 見つかりません —"}</span>
            </div>
            {EXPORT_ASSET_SLOTS.map((slot) => {
              const options = optionsFor(slot);
              return (
                <label key={slot} className="slot-row">
                  <span className="slot-label">{SLOT_LABEL[slot]}<em>{SLOT_SOCKET[slot].replace("socket_", "")}</em></span>
                  <select value={recipe.assets[slot] ?? ""} onChange={(e) => setSlot(slot, e.target.value || null)}>
                    <option value="">— None —</option>
                    {options.map((e) => <option key={e.metadata.id} value={e.metadata.id}>{e.metadata.name}</option>)}
                  </select>
                </label>
              );
            })}
          </div>
          <p className="muted">選択肢は Asset Library のカテゴリ一致 Asset です。Asset Creator で保存すると増えます。</p>
        </section>

        {/* ---- Preview ---- */}
        <section className="panel preview-panel">
          <div className="panel-heading">
            <h2>{charName || recipe.id}</h2>
            <span className="muted">{restSize ? `≈ ${restSize[1].toFixed(2)} m` : "Composed Preview"}</span>
          </div>
          <div className="anim-bar">
            <label className="inline">Anim Set
              <select value={activeAnimationSet} onChange={(e) => setAnimSetOverride(e.target.value === weaponSet ? null : e.target.value)}>
                {ANIM_SETS.map((s) => <option key={s} value={s}>{s}{s === weaponSet ? " (weapon)" : ""}</option>)}
              </select>
            </label>
            <label className="inline">Action
              <select value={animRole} onChange={(e) => setAnimRole(e.target.value as (typeof ANIM_ROLES)[number])}>
                {ANIM_ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </label>
            <button type="button" onClick={() => setPlaying((p) => !p)}>{playing ? "⏸ Pause" : "▶ Play"}</button>
            <label className="inline">Speed
              <input type="range" min={0.25} max={2} step={0.25} value={speed} onChange={(e) => setSpeed(Number(e.target.value))} />
              <span>{speed.toFixed(2)}×</span>
            </label>
            <label className="check"><input type="checkbox" checked={loop} onChange={(e) => setLoop(e.target.checked)} />loop</label>
            <button type="button" className="mini" onClick={() => setCaptureSignal((n) => n + 1)}>Capture Thumbnail</button>
          </div>

          <CharacterPreview
            key={`${JSON.stringify(recipe)}|${library.ids.length}`}
            recipe={recipe}
            library={library}
            animationSet={activeAnimationSet}
            animationRole={animRole}
            playing={playing}
            speed={speed}
            loop={loop}
            captureSignal={captureSignal}
            onThumbnail={setThumb}
            onWarnings={setPreviewWarnings}
            onNotices={setPreviewNotices}
            onRestSize={setRestSize}
          />

          {previewNotices.length > 0 && (
            <details className="preview-notes">
              <summary>自動補正 {previewNotices.length} 件</summary>
              <ul>{previewNotices.map((n, i) => <li key={i}>{n}</li>)}</ul>
            </details>
          )}
          {previewWarnings.length > 0 && (
            <details className="preview-warn-list">
              <summary>合成の警告 {previewWarnings.length} 件</summary>
              <ul>{previewWarnings.map((w, i) => <li key={i}>{w}</li>)}</ul>
            </details>
          )}
        </section>

        {/* ---- Controls ---- */}
        <aside className="panel builder-controls">
          <h2>Body Scale</h2>
          <div className="control-block">
            {SCALE_KEYS.map(([key, label]) => (
              <label key={key} className="slider">
                <span>{label}<em>{recipe.body.scale[key].toFixed(2)}</em></span>
                <input type="range" min={SCALE_MIN} max={SCALE_MAX} step={0.01}
                  value={recipe.body.scale[key]}
                  onChange={(e) => setScale(key, Number(e.target.value))} />
              </label>
            ))}
            <p className="muted">非一様スケールは既存 Rig の傾いた四肢をわずかに歪めます。極端値は Export 警告になります。</p>
          </div>

          <h2>Palette</h2>
          <div className="control-block palette-grid">
            {PALETTE_SLOTS.map((slot) => (
              <label key={slot} className="swatch">
                <input type="color" value={recipe.palette[slot]} onChange={(e) => setPalette(slot, e.target.value)} />
                {slot}
              </label>
            ))}
          </div>

          <h2>Recipe</h2>
          <div className="control-block recipe-actions">
            <input ref={fileInput} type="file" accept=".json,application/json" hidden onChange={(e) => loadRecipe(e.target.files?.[0])} />
            <button type="button" onClick={saveRecipe}>Save Recipe (.json)</button>
            <button type="button" onClick={() => fileInput.current?.click()}>Load Recipe</button>
            <button type="button" onClick={resetRecipe}>Reset</button>
            {recipeMsg && <p className="save-msg">{recipeMsg}</p>}
            <p className="muted">Recipe は再編集用（localStorage 自動保存）。Godot 用の character.json は Export で別に生成します。</p>
          </div>

          <BuilderLibrarySave recipe={recipe} name={charName} thumbnail={thumb} />
        </aside>
      </div>

      <ExportPanel
        recipe={recipe}
        onId={(id) => patchRecipe({ id })}
        name={charName}
        onName={setCharName}
        library={library}
        activeAnimationSet={activeAnimationSet}
        thumbnailDataUrl={thumb}
      />
    </>
  );
}
