"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import type { CharacterRecord, LibraryIndex } from "@/domain/library-index";
import { PALETTE_SLOTS } from "@/domain/constants";
import { EXPORT_ASSET_SLOTS } from "@/domain/character-export";
import { SLOT_LABEL } from "@/domain/builder-recipe";
import { addTag, removeTag } from "@/domain/library-ids";
import { validateCharacterRecord } from "@/domain/library-validation";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { CharacterPreview } from "@/features/character-builder/character-preview";
import { patchCharacter, duplicateCharacter, registerCharacter, unregisterCharacter } from "./mutations";
import { reexportCharacter, activeAnimationSetFor } from "./export-helpers";
import { refreshLibrary } from "./use-library-index";
import { deleteCharacter } from "./api";
import { ExportBadge, RegistryBadge, ValidationBadge } from "./components/badges";
import type { DerivedLibrary } from "./derive";

export function CharacterDetailPanel({ record, index, derived, autoRegister }: {
  record: CharacterRecord; index: LibraryIndex; derived: DerivedLibrary; autoRegister: boolean;
}) {
  const library = useMergedLibrary();
  const recipe = record.recipe;
  const [tab, setTab] = useState<"detail" | "tags">("detail");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [tagInput, setTagInput] = useState("");

  const evalResult = derived.exportEval.get(recipe.id);
  const refs = derived.graph.byCharacter[recipe.id] ?? [];
  const liveIssues = useMemo(
    () => validateCharacterRecord(record, { assetsById: derived.assetsById }),
    [record, derived.assetsById],
  );
  const animSet = activeAnimationSetFor(recipe, library);

  async function run(label: string, fn: () => Promise<unknown>) {
    setBusy(label); setMsg(null);
    try { await fn(); await refreshLibrary(); setMsg(`${label} 完了`); }
    catch (e) { setMsg(`${label} 失敗: ${e instanceof Error ? e.message : String(e)}`); }
    finally { setBusy(null); }
  }

  return (
    <div className="lib-detail">
      <div className="lib-detail-head">
        <div>
          <h2>{record.name} <ValidationBadge status={record.validation.status} /></h2>
          <p className="muted">{recipe.id} · {recipe.body.base} · v{recipe.characterVersion ?? 1}</p>
          <p><ExportBadge status={evalResult?.status ?? record.export.status} /> <RegistryBadge status={record.registry.status} /></p>
        </div>
      </div>

      <div className="lib-detail-preview">
        <CharacterPreview
          key={recipe.id + JSON.stringify(recipe.assets)}
          recipe={recipe}
          library={library}
          animationSet={animSet}
          animationRole="idle"
          playing
          speed={1}
          loop
          captureSignal={-1}
        />
      </div>

      {tab === "detail" ? (
        <div className="lib-detail-body">
          <dl>
            <dt>Body / Scale</dt><dd>{recipe.body.preset} · H {recipe.body.scale.height} / W {recipe.body.scale.bodyWidth} / Head {recipe.body.scale.headScale}</dd>
            {EXPORT_ASSET_SLOTS.map((slot) => {
              const id = recipe.assets[slot] ?? null;
              const ref = refs.find((r) => r.slot === slot);
              return (
                <div key={slot} style={{ display: "contents" }}>
                  <dt>{SLOT_LABEL[slot]}</dt>
                  <dd>{id ? <>{id}{ref?.missing && <span className="err"> ⚠ Missing Asset</span>}</> : "—"}</dd>
                </div>
              );
            })}
            <dt>Palette</dt><dd className="pal-row">{PALETTE_SLOTS.map((s) => <span key={s} style={{ background: recipe.palette[s] }} title={`${s} ${recipe.palette[s]}`} />)}</dd>
            <dt>Animation Set</dt><dd>{animSet}</dd>
            <dt>Character Version</dt><dd>v{recipe.characterVersion ?? 1}</dd>
            <dt>Godot Export</dt><dd>{record.export.exportedAt ? `${new Date(record.export.exportedAt).toLocaleString()} (v${record.export.exportedCharacterVersion})` : "未 Export"}</dd>
            <dt>Registry</dt><dd>{record.registry.registeredAt ? new Date(record.registry.registeredAt).toLocaleString() : "未登録"}</dd>
          </dl>

          {evalResult && evalResult.reasons.length > 0 && (
            <div className="lib-detail-section">
              <h3>Re-export Reasons</h3>
              <ul className="hist-list">{evalResult.reasons.map((r, i) => <li key={i}>{r}</li>)}</ul>
            </div>
          )}

          <div className="lib-detail-section">
            <h3>Uses Assets ({refs.length})</h3>
            <ul className="chip-list">
              {refs.map((r) => (
                <li key={r.slot + r.assetId} className={r.missing ? "chip-missing" : ""}>
                  {r.missing ? r.assetId : <Link href={`/assets?id=${r.assetId}`}>{r.assetId}</Link>}
                  {r.missing && " ⚠"}
                </li>
              ))}
              {refs.length === 0 && <li className="muted">Base のみ</li>}
            </ul>
          </div>

          {liveIssues.length > 0 && (
            <div className="lib-detail-section">
              <h3>Validation</h3>
              <ul className="val-list">
                {liveIssues.map((i, k) => <li key={k} className={`val ${i.level}`}><span className="val-tag">{i.level.toUpperCase()}</span><span>{i.message}</span></li>)}
              </ul>
            </div>
          )}

          <div className="lib-actions">
            <button disabled={!!busy} onClick={() => run("Export for Godot", async () => {
              const r = await reexportCharacter(record, library, index, { autoRegister, download: true });
              setMsg(r.message + (r.registered ? " · Registry 更新" : ""));
              if (!r.ok) throw new Error(r.message);
            })}>Export for Godot</button>
            <button disabled={!!busy || record.registry.status === "registered"} onClick={() => run("Register", async () => {
              await registerCharacter({ ...record }, index.registry);
            })}>Register Character</button>
            {record.registry.status === "registered" && (
              <button disabled={!!busy} onClick={() => run("Unregister", () => unregisterCharacter(record, index.registry))}>Unregister</button>
            )}
            <button disabled={!!busy} onClick={() => run("Duplicate Recipe", () => duplicateCharacter(record, index))}>Duplicate Recipe</button>
            <button disabled={!!busy} onClick={() => run("Validate", () => patchCharacter(record, {}, index))}>Validate</button>
            <button disabled={!!busy} className="danger" onClick={() => run("Delete", async () => {
              try { await deleteCharacter(recipe.id); }
              catch (e) {
                if ((e as { status?: number }).status === 409) {
                  if (!confirm("Registry 登録中の Character です。Registry から外して削除しますか？")) throw new Error("キャンセルしました");
                  await unregisterCharacter(record, index.registry);
                  await deleteCharacter(recipe.id, true);
                } else throw e;
              }
            })}>Delete</button>
          </div>
          {msg && <p className="save-msg">{msg}</p>}
        </div>
      ) : (
        <div className="lib-detail-body lib-tag-editor">
          <span>Tags</span>
          <ul className="chip-list">{record.tags.map((t) => <li key={t}>{t} <button className="mini" onClick={() => run("Tag 削除", () => patchCharacter(record, { tags: removeTag(record.tags, t) }, index))}>×</button></li>)}</ul>
          <input value={tagInput} placeholder="hero / enemy / npc …" onChange={(e) => setTagInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && tagInput.trim()) { run("Tag 追加", () => patchCharacter(record, { tags: addTag(record.tags, tagInput) }, index)); setTagInput(""); } }} />
        </div>
      )}

      <div className="seg" style={{ marginTop: 8 }}>
        <button className={tab === "detail" ? "on" : ""} onClick={() => setTab("detail")}>Detail</button>
        <button className={tab === "tags" ? "on" : ""} onClick={() => setTab("tags")}>Tags</button>
      </div>
    </div>
  );
}
