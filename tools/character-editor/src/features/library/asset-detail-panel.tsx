"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { bumpVersionHistory, type AssetRecord, type LibraryIndex } from "@/domain/library-index";
import { BODY_TYPES, CHARACTER_SOCKETS, PALETTE_SLOTS, WEAPON_HANDLING, WEAPON_TYPES, ANIMATION_SETS, type BodyType, type CharacterSocket, type PaletteSlot } from "@/domain/constants";
import { RECOMMENDED_SOCKET, type AssetType } from "@/domain/asset-spec";
import { addTag, removeTag } from "@/domain/library-ids";
import { validateAssetRecord } from "@/domain/library-validation";
import { AssetPreview } from "@/components/preview/asset-preview";
import { CreatorPreview } from "@/features/asset-creator/creator-preview";
import { libFileUrl, deleteAsset, putFile } from "./api";
import { duplicateAsset, patchAsset, bumpAssetVersion } from "./mutations";
import { refreshLibrary } from "./use-library-index";
import { ValidationBadge } from "./components/badges";
import { usersOfAsset } from "@/domain/library-dependency";
import type { DerivedLibrary } from "./derive";

type PreviewMode = "asset" | "base" | "anim";

export function AssetDetailPanel({ record, index, derived }: { record: AssetRecord; index: LibraryIndex; derived: DerivedLibrary }) {
  const m = record.metadata;
  const [tab, setTab] = useState<"detail" | "edit">("detail");
  const [mode, setMode] = useState<PreviewMode>("asset");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const modelUrl = record.files.model ? libFileUrl("asset", m.id, "model.glb") : null;
  const textureUrl = record.files.texture ? libFileUrl("asset", m.id, "texture.png") : null;
  const thumbUrl = record.files.thumbnail ? libFileUrl("asset", m.id, "thumbnail.png") : null;
  const socket = (m.attachment?.main?.characterSocket ?? RECOMMENDED_SOCKET[m.type as AssetType] ?? "socket_chest") as CharacterSocket;
  const usedBy = usersOfAsset(derived.graph, m.id);
  const liveIssues = useMemo(() => validateAssetRecord(record), [record]);

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
          <h2>{m.name} <ValidationBadge status={record.validation.status} /></h2>
          <p className="muted">{m.id} · {m.type}{m.equipment?.weaponType ? ` / ${m.equipment.weaponType}` : ""} · v{m.assetVersion}</p>
        </div>
        <div className="seg">
          <button className={tab === "detail" ? "on" : ""} onClick={() => setTab("detail")}>Detail</button>
          <button className={tab === "edit" ? "on" : ""} onClick={() => setTab("edit")}>Edit</button>
        </div>
      </div>

      <div className="seg preview-modes">
        <button className={mode === "asset" ? "on" : ""} onClick={() => setMode("asset")}>Asset Only</button>
        <button className={mode === "base" ? "on" : ""} onClick={() => setMode("base")}>Base + Asset</button>
        <button className={mode === "anim" ? "on" : ""} onClick={() => setMode("anim")}>Animation Preview</button>
      </div>
      <div className="lib-detail-preview">
        {mode === "asset" && <AssetPreview url={modelUrl} name={m.name} />}
        {mode !== "asset" && (
          <CreatorPreview
            key={`${m.id}:${mode}`}
            assetModelUrl={modelUrl}
            assetTextureUrl={textureUrl}
            mode="base"
            socket={socket}
            paletteColor={null}
            hideParts={m.hideParts}
            animationClip={mode === "anim" ? "animation.walk_mcp_test" : null}
            animationPlaying={mode === "anim"}
            animationSpeed={1}
            animationLoop
            referenceHair="none"
            captureSignal={-1}
          />
        )}
      </div>

      {tab === "detail" ? (
        <div className="lib-detail-body">
          <dl>
            <dt>Description</dt><dd>{m.description || "—"}</dd>
            <dt>Body Type</dt><dd>{m.bodyTypes.join(", ") || "—"}</dd>
            <dt>Socket</dt><dd>{socket}</dd>
            <dt>Palette Slots</dt><dd>{m.appearance.paletteSlots.join(", ") || "—"}</dd>
            <dt>Hide Parts</dt><dd>{m.hideParts.join(", ") || "—"}</dd>
            <dt>Hair Policy</dt><dd>{m.hairPolicy ?? "—"}</dd>
            {m.equipment && <>
              <dt>Weapon Type</dt><dd>{m.equipment.weaponType ?? "—"}</dd>
              <dt>Handling</dt><dd>{m.equipment.handling ?? "—"}</dd>
              <dt>Animation Set</dt><dd>{m.equipment.animationSet ?? "—"}</dd>
            </>}
            <dt>Tags</dt><dd>{record.tags.join(", ") || "—"}</dd>
            <dt>Version</dt><dd>v{m.assetVersion} (前: {record.versionHistory.at(-1)?.previousVersion ?? "—"})</dd>
            <dt>Created / Updated</dt><dd>{new Date(record.createdAt).toLocaleString()} / {new Date(record.updatedAt).toLocaleString()}</dd>
            <dt>Model / Texture</dt><dd>{record.files.model ? "model.glb" : "—"} / {record.files.texture ? "texture.png" : "—"}</dd>
            <dt>Source</dt><dd>{m.source?.path ?? "—"}</dd>
            <dt>Thumbnail</dt><dd>{thumbUrl ? "thumbnail.png" : "—"}</dd>
          </dl>

          <div className="lib-detail-section">
            <h3>Used By Characters ({usedBy.length})</h3>
            {usedBy.length === 0 ? <p className="muted">どの Character にも使われていません。</p> : (
              <ul className="chip-list">{usedBy.map((id) => <li key={id}><Link href={`/characters?id=${id}`}>{id}</Link></li>)}</ul>
            )}
          </div>

          <div className="lib-detail-section">
            <h3>Version History</h3>
            <ul className="hist-list">
              {[...record.versionHistory].reverse().map((h) => (
                <li key={h.version}>v{h.version} ← v{h.previousVersion ?? "—"} · {new Date(h.updatedAt).toLocaleString()} · {h.note}</li>
              ))}
            </ul>
          </div>

          {liveIssues.length > 0 && (
            <div className="lib-detail-section">
              <h3>Live Validation</h3>
              <ul className="val-list">
                {liveIssues.map((i, k) => <li key={k} className={`val ${i.level}`}><span className="val-tag">{i.level.toUpperCase()}</span><span>{i.message}</span></li>)}
              </ul>
            </div>
          )}

          <div className="lib-actions">
            <button disabled={!!busy} onClick={() => run("Duplicate", () => duplicateAsset(record, index))}>Duplicate</button>
            <button disabled={!!busy} onClick={() => run("Validate", () => patchAsset(record, {}))}>Validate</button>
            <button disabled={!!busy} onClick={() => run("Version +1", () => bumpAssetVersion(record, "manual bump"))}>Bump Version</button>
            <button
              disabled={!!busy}
              className="danger"
              onClick={() => run("Delete", async () => {
                try { await deleteAsset(m.id); }
                catch (e) {
                  const body = (e as { body?: { usedByCount?: number } }).body;
                  if (body?.usedByCount) {
                    if (!confirm(`This asset is used by ${body.usedByCount} character(s). Force delete?`)) throw new Error("キャンセルしました");
                    await deleteAsset(m.id, true);
                  } else throw e;
                }
              })}
            >Delete</button>
          </div>
          {msg && <p className="save-msg">{msg}</p>}
        </div>
      ) : (
        <AssetEditForm record={record} index={index} onDone={(t) => { setMsg(t); setTab("detail"); }} />
      )}
    </div>
  );
}

function AssetEditForm({ record, index, onDone }: { record: AssetRecord; index: LibraryIndex; onDone: (msg: string) => void }) {
  const m = record.metadata;
  const [name, setName] = useState(m.name);
  const [description, setDescription] = useState(m.description ?? "");
  const [bodyTypes, setBodyTypes] = useState<BodyType[]>([...m.bodyTypes]);
  const [socket, setSocket] = useState<CharacterSocket>((m.attachment?.main?.characterSocket ?? "socket_chest") as CharacterSocket);
  const [paletteSlots, setPaletteSlots] = useState<PaletteSlot[]>([...m.appearance.paletteSlots]);
  const [hairPolicy, setHairPolicy] = useState(m.hairPolicy ?? "");
  const [handling, setHandling] = useState(m.equipment?.handling ?? "one_hand");
  const [animationSet, setAnimationSet] = useState(m.equipment?.animationSet ?? "onehand_sword");
  const [weaponType, setWeaponType] = useState(m.equipment?.weaponType ?? "sword");
  const [tags, setTags] = useState<string[]>([...record.tags]);
  const [tagInput, setTagInput] = useState("");
  const [modelFile, setModelFile] = useState<File | null>(null);
  const [textureFile, setTextureFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const isWeapon = m.type === "weapon";
  const showHair = ["headgear", "head_accessory"].includes(m.type);
  const toggle = <T,>(list: T[], v: T): T[] => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

  async function save() {
    setBusy(true);
    try {
      const attachment = { ...(m.attachment ?? { main: { assetPoint: "fixture_origin", characterSocket: socket } }) };
      attachment.main = { ...attachment.main, characterSocket: socket };
      const { version, history } = bumpVersionHistory(record.versionHistory, m.assetVersion, "metadata / files updated");
      const nextMeta = {
        ...m,
        name: name.trim() || m.id,
        description: description.trim() || undefined,
        bodyTypes,
        tags,
        assetVersion: version,
        attachment,
        appearance: { paletteSlots },
        hairPolicy: showHair ? ((hairPolicy || null) as typeof m.hairPolicy) : m.hairPolicy,
        equipment: isWeapon
          ? { ...m.equipment, slot: "main_hand" as const, handling, animationSet, weaponType }
          : m.equipment,
      };
      if (modelFile) await putFile("asset", m.id, "model.glb", modelFile);
      if (textureFile) await putFile("asset", m.id, "texture.png", textureFile);
      await patchAsset(record, { metadata: nextMeta, versionHistory: history, tags });
      void index;
      await refreshLibrary();
      onDone(`保存しました（assetVersion v${m.assetVersion} → v${version}）`);
    } catch (e) {
      onDone(`保存失敗: ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(false); }
  }

  return (
    <div className="lib-detail-body lib-edit">
      <label>Name<input value={name} onChange={(e) => setName(e.target.value)} /></label>
      <label>Description<textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></label>
      <fieldset><legend>Body Type</legend>{BODY_TYPES.map((b) => (
        <label key={b} className="check"><input type="checkbox" checked={bodyTypes.includes(b)} onChange={() => setBodyTypes(toggle(bodyTypes, b))} />{b}</label>
      ))}</fieldset>
      <label>Attachment Socket<select value={socket} onChange={(e) => setSocket(e.target.value as CharacterSocket)}>
        {CHARACTER_SOCKETS.map((s) => <option key={s} value={s}>{s}</option>)}
      </select></label>
      <fieldset><legend>Palette Slots</legend>{PALETTE_SLOTS.map((s) => (
        <label key={s} className="check"><input type="checkbox" checked={paletteSlots.includes(s)} onChange={() => setPaletteSlots(toggle(paletteSlots, s))} />{s}</label>
      ))}</fieldset>
      {showHair && <label>Hair Policy<select value={hairPolicy} onChange={(e) => setHairPolicy(e.target.value as typeof hairPolicy)}>
        <option value="">—</option><option value="hide">hide</option><option value="overlay">overlay</option>
      </select></label>}
      {isWeapon && <fieldset className="weapon-block"><legend>Weapon</legend>
        <label>Weapon Type<select value={weaponType} onChange={(e) => setWeaponType(e.target.value as typeof weaponType)}>{WEAPON_TYPES.map((w) => <option key={w}>{w}</option>)}</select></label>
        <label>Handling<select value={handling} onChange={(e) => setHandling(e.target.value as typeof handling)}>{WEAPON_HANDLING.map((h) => <option key={h}>{h}</option>)}</select></label>
        <label>Animation Set<select value={animationSet} onChange={(e) => setAnimationSet(e.target.value as typeof animationSet)}>{ANIMATION_SETS.map((s) => <option key={s}>{s}</option>)}</select></label>
      </fieldset>}
      <div className="lib-tag-editor">
        <span>Tags</span>
        <ul className="chip-list">{tags.map((t) => <li key={t}>{t} <button className="mini" onClick={() => setTags(removeTag(tags, t))}>×</button></li>)}</ul>
        <input value={tagInput} placeholder="tag を追加して Enter" onChange={(e) => setTagInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { setTags(addTag(tags, tagInput)); setTagInput(""); } }} />
      </div>
      <label>Replace model.glb<input type="file" accept=".glb" onChange={(e) => setModelFile(e.target.files?.[0] ?? null)} /></label>
      <label>Replace texture.png<input type="file" accept=".png" onChange={(e) => setTextureFile(e.target.files?.[0] ?? null)} /></label>
      <button disabled={busy} onClick={save}>Save (assetVersion +1)</button>
    </div>
  );
}
