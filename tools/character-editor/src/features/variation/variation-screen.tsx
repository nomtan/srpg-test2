"use client";

// Phase 8 Character Variation Generator screen (spec section 1, 24, 30-33, 41-47).
// Preset list + Preset Editor + Palette Sets + preview batch + single-character detail.
// Committing writes Character Recipes only — GLB baking stays in the Character Library's Export.
import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { downloadBlob } from "@/features/asset-creator/zip";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { useLibraryIndex, refreshLibrary } from "@/features/library/use-library-index";
import { deletePreset as deletePresetApi, putPalettes, putPreset } from "@/features/library/api";
import { commitVariations } from "@/features/library/mutations";
import { stageRecipeForBuilder } from "@/features/character-builder/builder-storage";
import { nextDuplicateId, normalizeTag } from "@/domain/library-ids";
import type { PaletteLibrary } from "@/domain/variation-palette";
import {
  duplicatePreset, emptyPreset, parsePreset, presetText, type VariationPreset,
} from "@/domain/variation-preset";
import { validatePreset, countIssues } from "@/domain/variation-validation";
import {
  generateVariations, markDuplicates, rerollVariation,
  type GeneratedVariation, type GenerationReport, type LockField,
} from "@/domain/variation-generator";
import { candidatesFromLibrary, libraryTags } from "./adapt";
import { PresetEditor } from "./preset-editor";
import { PaletteSetEditor } from "./palette-set-editor";
import { VariationGrid } from "./variation-grid";
import { VariationDetail } from "./variation-detail";

type Tab = "generate" | "preset" | "palette";

export function VariationGeneratorScreen() {
  const router = useRouter();
  const { index, error, loading } = useLibraryIndex();
  const library = useMergedLibrary();

  const assets = useMemo(() => candidatesFromLibrary(library), [library]);
  const assetsById = useMemo(() => new Map(assets.map((a) => [a.id, a])), [assets]);
  const tags = useMemo(() => libraryTags(assets), [assets]);

  const [tab, setTab] = useState<Tab>("generate");
  // `draft` is the edited copy; with nothing chosen yet the first stored preset is shown, so no
  // effect has to push state on load.
  const [editing, setEditing] = useState<VariationPreset | null>(null);
  const draft = editing ?? index.presets[0] ?? null;
  const selectedPresetId = draft?.id ?? null;
  const [isNew, setIsNew] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const [report, setReport] = useState<GenerationReport | null>(null);
  const [variations, setVariations] = useState<GeneratedVariation[]>([]);
  const [selectedVariationId, setSelectedVariationId] = useState<string | null>(null);
  const [locksById, setLocksById] = useState<Record<string, LockField[]>>({});
  const [commitMsg, setCommitMsg] = useState<string | null>(null);

  const validation = useMemo(
    () => draft
      ? validatePreset(draft, {
        assets,
        palettes: index.palettes,
        otherPresetIds: index.presets.filter((p) => p.id !== selectedPresetId).map((p) => p.id),
      })
      : null,
    [draft, assets, index.palettes, index.presets, selectedPresetId],
  );

  const takenCharacterIds = useMemo(
    () => new Set(index.characters.map((c) => c.recipe.id)),
    [index.characters],
  );

  function selectPreset(preset: VariationPreset) {
    if (dirty && !confirm("保存していない Preset の変更があります。破棄して切り替えますか？")) return;
    setEditing(preset);
    setIsNew(false);
    setDirty(false);
    setMsg(null);
  }

  function editDraft(next: VariationPreset) {
    setEditing(next);
    setDirty(true);
  }

  async function run(label: string, fn: () => Promise<unknown>) {
    setBusy(label); setMsg(null);
    try { await fn(); setMsg(`${label} 完了`); }
    catch (e) { setMsg(`${label} 失敗: ${e instanceof Error ? e.message : String(e)}`); }
    finally { setBusy(null); }
  }

  async function savePreset() {
    if (!draft) return;
    const taken = index.presets.map((p) => p.id);
    if (isNew && taken.includes(draft.id)) { setMsg(`Preset ID が重複しています: ${draft.id}`); return; }
    if (validation && validation.issues.some((i) => i.code === "id" || i.code === "id_duplicate")) {
      setMsg("Preset ID を修正してください。");
      return;
    }
    await run("Save Preset", async () => {
      const next: VariationPreset = {
        ...draft,
        presetVersion: isNew ? 1 : draft.presetVersion + 1,
        updatedAt: new Date().toISOString(),
      };
      await putPreset(next);
      await refreshLibrary();
      setEditing(next);
      setIsNew(false);
      setDirty(false);
    });
  }

  function newPreset() {
    const id = nextDuplicateId("preset_001", index.presets.map((p) => p.id));
    const preset = emptyPreset(id);
    setEditing(preset);
    setIsNew(true);
    setDirty(true);
    setTab("preset");
  }

  function duplicateCurrent() {
    if (!draft) return;
    const id = nextDuplicateId(draft.id, index.presets.map((p) => p.id));
    const copy = duplicatePreset(draft, id, `${draft.name} Copy`);
    setEditing(copy);
    setIsNew(true);
    setDirty(true);
    setTab("preset");
    setMsg(`${draft.id} を ${id} として複製しました。Save Preset で保存してください。`);
  }

  async function removePreset() {
    if (!draft || isNew) return;
    if (!confirm(`Preset ${draft.id} を削除しますか？（生成済み Character は削除されません）`)) return;
    await run("Delete Preset", async () => {
      await deletePresetApi(draft.id);
      await refreshLibrary();
      setEditing(null);
      setDirty(false);
    });
  }

  function exportPreset() {
    if (!draft) return;
    downloadBlob(new Blob([presetText(draft)], { type: "application/json" }), `${draft.id}.json`);
  }

  async function importPreset(file: File | undefined) {
    if (!file) return;
    await run("Import Preset", async () => {
      const parsed = parsePreset(JSON.parse(await file.text()));
      const taken = index.presets.map((p) => p.id);
      const id = taken.includes(parsed.id) ? nextDuplicateId(parsed.id, taken) : parsed.id;
      const preset = { ...parsed, id, idPrefix: parsed.idPrefix || id };
      await putPreset(preset);
      await refreshLibrary();
      setEditing(preset);
      setIsNew(false);
      setDirty(false);
    });
  }

  // ---- generation ---------------------------------------------------------------

  function preview() {
    if (!draft || !validation) return;
    if (!validation.canGenerate) {
      setCommitMsg("Preset に Error があります。Preset Editor の Validation を解消してください。");
      setTab("preset");
      return;
    }
    const result = generateVariations({
      preset: draft,
      assets,
      palettes: index.palettes,
      takenIds: takenCharacterIds,
    });
    setReport(result);
    setVariations(result.variations);
    setLocksById({});
    setSelectedVariationId(result.variations[0]?.id ?? null);
    setCommitMsg(
      `Generated: ${result.variations.length} / Failed: ${result.failures.length}` +
      (result.duplicates ? ` / Duplicate: ${result.duplicates}` : ""),
    );
  }

  function reroll() {
    if (!draft || !selectedVariationId) return;
    const current = variations.find((v) => v.id === selectedVariationId);
    if (!current) return;
    const others = new Set(variations.filter((v) => v.id !== current.id).map((v) => v.signature));
    const result = rerollVariation(
      { preset: draft, assets, palettes: index.palettes, takenIds: takenCharacterIds },
      current,
      locksById[current.id] ?? [],
      others,
    );
    if (!result.ok || !result.variation) { setCommitMsg(`Reroll 失敗: ${result.error}`); return; }
    const next = result.variation;
    setVariations((list) => markDuplicates(list.map((v) => (v.id === next.id ? next : v))));
    setCommitMsg(`${next.id} を Reroll しました（salt ${next.salt}）。`);
  }

  function toggleLock(field: LockField) {
    if (!selectedVariationId) return;
    setLocksById((prev) => {
      const current = prev[selectedVariationId] ?? [];
      const next = current.includes(field) ? current.filter((f) => f !== field) : [...current, field];
      return { ...prev, [selectedVariationId]: next };
    });
  }

  async function commit() {
    if (!draft || variations.length === 0) return;
    const usable = variations.filter((v) => !v.duplicate);
    const dupCount = variations.length - usable.length;
    if (dupCount > 0 && !confirm(`Duplicate Variation が ${dupCount} 件あります。除外して ${usable.length} 体を登録しますか？`)) return;
    await run("Generate Characters", async () => {
      const result = await commitVariations({
        variations: usable,
        index,
        tags: [draft.faction, draft.role, "generated", ...draft.tags].filter(Boolean).map(normalizeTag),
        onProgress: (done, total) => setCommitMsg(`Character Library へ登録中… ${done}/${total}`),
      });
      await refreshLibrary();
      setCommitMsg(
        `Character Library へ ${result.created.length} 体を登録しました` +
        (result.skipped.length ? `（skip ${result.skipped.length}: ${result.skipped[0].reason}）` : "") +
        "。GLB は Export 時に生成されます。",
      );
      setVariations([]);
      setReport(null);
      setSelectedVariationId(null);
    });
  }

  function openInBuilder() {
    const current = variations.find((v) => v.id === selectedVariationId);
    if (!current) return;
    if (!stageRecipeForBuilder(current.recipe, current.name)) {
      setCommitMsg("localStorage が使用できないため Builder へ渡せませんでした。");
      return;
    }
    router.push("/");
  }

  const selectedVariation = variations.find((v) => v.id === selectedVariationId) ?? null;
  const counts = validation ? countIssues(validation.issues) : { errors: 0, warnings: 0 };

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">CHARACTER VARIATION GENERATOR</p>
          <h1>Variation Generator</h1>
          <p>Asset Tag / Compatibility / Weighted Random で Character Recipe を一括生成します。GLB は生成せず、Export 時にのみ Bake します。</p>
        </div>
        <span className="badge">PHASE 8 · {index.presets.length} PRESETS</span>
      </div>

      {error && <p className="err">Library API エラー: {error}</p>}

      <div className="lib-layout">
        <aside className="panel lib-side">
          <div className="panel-heading"><h2>Presets</h2><span className="count">{index.presets.length}</span></div>
          <ul className="cat-tree">
            {index.presets.map((p) => (
              <li key={p.id}>
                <button className={selectedPresetId === p.id ? "on" : ""} onClick={() => selectPreset(p)}>
                  {p.name}
                  <small className="muted"> {p.id}</small>
                </button>
              </li>
            ))}
            {index.presets.length === 0 && !loading && <li className="muted">Preset がありません。</li>}
          </ul>
          <div className="lib-import">
            <button type="button" onClick={newPreset}>New Preset</button>
            <button type="button" disabled={!draft} onClick={duplicateCurrent}>Duplicate Preset</button>
            <button type="button" disabled={!draft || isNew || !!busy} onClick={removePreset} className="danger">Delete Preset</button>
          </div>
          <div className="lib-import">
            <button type="button" disabled={!draft} onClick={exportPreset}>Export Preset JSON</button>
            <label className="filebtn">Import Preset JSON
              <input type="file" accept=".json" hidden onChange={(e) => importPreset(e.target.files?.[0])} />
            </label>
            {msg && <p className="muted">{msg}</p>}
          </div>
        </aside>

        <section className="panel lib-main">
          <div className="lib-toolbar">
            <div className="seg">
              <button className={tab === "generate" ? "on" : ""} onClick={() => setTab("generate")}>Generate</button>
              <button className={tab === "preset" ? "on" : ""} onClick={() => setTab("preset")}>Preset Editor</button>
              <button className={tab === "palette" ? "on" : ""} onClick={() => setTab("palette")}>Palette Sets</button>
            </div>
            {draft && (
              <>
                <span className={counts.errors ? "err" : "muted"}>
                  Validation: {counts.errors} error / {counts.warnings} warning
                </span>
                <button type="button" disabled={!dirty || !!busy} onClick={savePreset}>
                  {isNew ? "Save Preset (new)" : "Save Preset"}
                </button>
              </>
            )}
          </div>

          {!draft && <p className="empty-list">左の一覧から Preset を選ぶか、New Preset を作成してください。</p>}

          {draft && tab === "generate" && (
            <div className="var-generate">
              <div className="var-controls">
                <label className="inline">Preset<strong>{draft.name}</strong></label>
                <label className="inline">Count
                  <input type="number" min={1} max={100} value={draft.count}
                    onChange={(e) => editDraft({ ...draft, count: Math.min(100, Math.max(1, Number(e.target.value) || 1)) })} />
                </label>
                <label className="inline">Body Type<strong>{draft.bodyTypes.join(" / ")}</strong></label>
                <label className="inline">Gender<strong>{draft.genderExpression}</strong></label>
                <label className="inline">Seed
                  <input type="number" min={0} value={draft.seed}
                    onChange={(e) => editDraft({ ...draft, seed: Math.abs(Math.floor(Number(e.target.value) || 0)) })} />
                </label>
                <button type="button" onClick={() => editDraft({ ...draft, seed: Math.floor(Math.random() * 1_000_000_000) })}>Generate New Seed</button>
                <button type="button" onClick={preview}>Preview Variations</button>
                <button type="button" disabled={variations.length === 0 || !!busy} onClick={commit}>Generate Characters</button>
              </div>

              {validation && !validation.canGenerate && (
                <p className="err">
                  生成できない Preset です（error {counts.errors} 件）。Preset Editor で修正してください。
                </p>
              )}
              {commitMsg && <p className="save-msg">{commitMsg}</p>}

              {report && report.failures.length > 0 && (
                <details className="preview-warn-list">
                  <summary>Failed: {report.failures.length} 件</summary>
                  <ul>{report.failures.map((f) => <li key={f.index}>[{f.index + 1}] {f.id}: {f.reason}</li>)}</ul>
                </details>
              )}

              <VariationGrid
                variations={variations}
                assetsById={assetsById}
                selectedId={selectedVariationId}
                onSelect={setSelectedVariationId}
              />

              <p className="muted">
                生成されるのは Character Recipe（Asset References + Scale + Palette）のみです。
                Batch Export は <Link href="/characters">Character Library</Link> で行います。
              </p>
            </div>
          )}

          {draft && tab === "preset" && validation && (
            <>
              {validation.issues.length > 0 && (
                <ul className="val-list var-issues">
                  {validation.issues.map((i, k) => (
                    <li key={k} className={`val ${i.level}`}><span className="val-tag">{i.level.toUpperCase()}</span><span>{i.message}</span></li>
                  ))}
                </ul>
              )}
              <PresetEditor
                draft={draft}
                onChange={editDraft}
                assets={assets}
                libraryTags={tags}
                palettes={index.palettes}
                validation={validation}
                idEditable={isNew}
              />
            </>
          )}

          {tab === "palette" && (
            <PaletteSetEditor
              key={index.palettes.updatedAt}
              library={index.palettes}
              busy={!!busy}
              onSave={(next: PaletteLibrary) => run("Save Palette Sets", async () => {
                await putPalettes(next);
                await refreshLibrary();
              })}
            />
          )}
        </section>

        <aside className="panel lib-detail-wrap">
          {selectedVariation ? (
            <VariationDetail
              variation={selectedVariation}
              assetsById={assetsById}
              library={library}
              locks={locksById[selectedVariation.id] ?? []}
              onToggleLock={toggleLock}
              onReroll={reroll}
              onOpenInBuilder={openInBuilder}
              busy={!!busy}
              message={commitMsg}
            />
          ) : (
            <p className="muted lib-detail-empty">Preview 一覧から Character を選択すると 3D Preview を表示します。</p>
          )}
        </aside>
      </div>
    </>
  );
}
