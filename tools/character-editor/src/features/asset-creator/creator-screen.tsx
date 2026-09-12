"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  ANIMATION_SETS, BODY_TYPES, CHARACTER_SOCKETS, PALETTE_SLOTS, WEAPON_HANDLING, WEAPON_TYPES,
  type BodyType, type CharacterSocket, type PaletteSlot,
} from "@/domain/constants";
import {
  ASSET_TYPES, ASSET_TYPE_LABELS, HAIR_POLICY_TYPES, RECOMMENDED_SOCKET, SUGGESTED_PALETTE_SLOTS,
  WEAPON_TEXTURE_SIZES, WEAPON_TYPE_ANIMATION_SET, WEAPON_TYPE_HANDLING,
  applyTypeDefaults, assetDir, assetJsonText, draftToAssetJson, emptyDraft, gripPointsFor,
  isWeapon, isSnakeCase, suggestId, type AssetDraft, type AssetType, type GripPoint,
} from "@/domain/asset-spec";
import { DEFAULT_PALETTE } from "@/domain/phase3";
import { GRIP_ORIENTATION_DEGREES } from "@/domain/base-rig";
import { countByLevel, validateDraft, type GlbStats, type TextureStats, type ValidationItem } from "@/domain/asset-validation";
import { buildPrompts } from "@/prompt/promptBuilder";
import { BAKED_BASE_CLIPS, resolveAnimation } from "@/viewer/animation/animationMapping";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { saveUserAsset } from "@/features/asset-library/user-assets";
import { CreatorLibrarySave } from "@/features/library/creator-save";
import { ProductionPanel } from "@/features/production/production-panel";
import { CreatorPreview } from "./creator-preview";
import { BASE_PARTS, BASE_REST_SIZE_METERS } from "./base-parts";
import { inspectImage } from "./inspect";
import { createZip, dataUrlToBytes, downloadBlob } from "./zip";

const ANIM_ROLES = ["idle", "walk", "run", "attack"] as const;
const weaponOrShield = (type: AssetType) => type === "weapon" || type === "shield";

export function CreatorScreen() {
  const library = useMergedLibrary();
  const [draft, setDraft] = useState<AssetDraft>(() => emptyDraft("hair"));
  const [idEdited, setIdEdited] = useState(false);

  const [model, setModel] = useState<{ url: string; name: string } | null>(null);
  const [textureFile, setTextureFile] = useState<{ url: string; name: string } | null>(null);
  const [glbStats, setGlbStats] = useState<GlbStats | null>(null);
  const [textureStats, setTextureStats] = useState<TextureStats | null>(null);

  const [mode, setMode] = useState<"asset" | "base">("asset");
  const [animRole, setAnimRole] = useState<(typeof ANIM_ROLES)[number]>("idle");
  const [animPlaying, setAnimPlaying] = useState(false);
  const [animSpeed, setAnimSpeed] = useState(1);
  const [animLoop, setAnimLoop] = useState(true);

  const [palette, setPalette] = useState<Record<PaletteSlot, string>>({ ...DEFAULT_PALETTE });
  const [prompts, setPrompts] = useState<{ model: string; texture: string } | null>(null);
  const [copied, setCopied] = useState<"model" | "texture" | null>(null);
  const [validation, setValidation] = useState<ValidationItem[] | null>(null);
  const [thumb, setThumb] = useState<string | null>(null);
  const [captureSignal, setCaptureSignal] = useState(-1);
  const [saveMsg, setSaveMsg] = useState<string | null>(null);
  const [showHideParts, setShowHideParts] = useState(false);

  const modelInput = useRef<HTMLInputElement>(null);
  const textureInput = useRef<HTMLInputElement>(null);
  const sourceInput = useRef<HTMLInputElement>(null);

  const update = (patch: Partial<AssetDraft>) => setDraft((d) => ({ ...d, ...patch }));

  function changeType(type: AssetType) {
    setDraft((d) => {
      const next = applyTypeDefaults(d, type);
      if (!idEdited) next.id = suggestId(next.name, type);
      return next;
    });
  }
  function changeName(name: string) {
    setDraft((d) => ({ ...d, name, id: idEdited ? d.id : suggestId(name, d.type) }));
  }
  function changeWeaponType(weaponType: AssetDraft["weaponType"]) {
    setDraft((d) => {
      const handling = WEAPON_TYPE_HANDLING[weaponType];
      return { ...d, weaponType, handling, animationSet: WEAPON_TYPE_ANIMATION_SET[weaponType], gripPoints: gripPointsFor(handling) };
    });
  }
  function changeHandling(handling: AssetDraft["handling"]) {
    setDraft((d) => ({ ...d, handling, gripPoints: gripPointsFor(handling) }));
  }
  const toggle = <T,>(list: T[], value: T): T[] =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  // Import handling -----------------------------------------------------------
  useEffect(() => () => { if (model) URL.revokeObjectURL(model.url); }, [model]);
  useEffect(() => () => { if (textureFile) URL.revokeObjectURL(textureFile.url); }, [textureFile]);
  useEffect(() => {
    if (!textureFile) return;
    let alive = true;
    inspectImage(textureFile.url).then((s) => { if (alive) setTextureStats(s); }).catch(() => { if (alive) setTextureStats(null); });
    return () => { alive = false; };
  }, [textureFile]);

  function onPickModel(file: File | undefined) {
    if (!file) return;
    setModel({ url: URL.createObjectURL(file), name: file.name });
  }
  function onPickTexture(file: File | undefined) {
    if (!file) return;
    setTextureStats(null);
    setTextureFile({ url: URL.createObjectURL(file), name: file.name });
  }
  function onPickSource(file: File | undefined) {
    if (!file) return;
    update({ sourceFileName: file.name.endsWith(".bbmodel") ? file.name : `${file.name}.bbmodel` });
  }

  // Derived -----------------------------------------------------------------
  const existingIds = useMemo(
    () => library.ids.filter((id) => id !== draft.id),
    [library.ids, draft.id],
  );
  const willReplace = draft.id ? library.byId[draft.id]?.provenance === "user" : false;

  const previewSet = isWeapon(draft.type) ? draft.animationSet : "default";
  const anim = useMemo(
    () => resolveAnimation(previewSet, animRole, BAKED_BASE_CLIPS),
    [previewSet, animRole],
  );

  const paletteColor = draft.paletteSlots[0] ? palette[draft.paletteSlots[0]] : null;
  // Weapons / shields attach by a grip point, so the preview uses the standard weapon orientation.
  const gripRotationDeg = weaponOrShield(draft.type)
    ? (draft.type === "shield" ? GRIP_ORIENTATION_DEGREES.off_hand : GRIP_ORIENTATION_DEGREES.main_hand)
    : null;
  const referenceHair: "none" | "shown" | "hidden" =
    mode === "base" && HAIR_POLICY_TYPES.includes(draft.type)
      ? (draft.hairPolicy === "hide" ? "hidden" : "shown")
      : "none";

  function runValidation() {
    setValidation(validateDraft(draft, {
      existingIds,
      model: glbStats,
      texture: textureStats,
      baseSize: BASE_REST_SIZE_METERS,
      hasSourceFile: !!draft.sourceFileName,
    }));
  }
  function generatePrompts() {
    setPrompts(buildPrompts(draft));
  }
  async function copyPrompt(which: "model" | "texture") {
    if (!prompts) return;
    try {
      await navigator.clipboard.writeText(prompts[which]);
      setCopied(which);
      setTimeout(() => setCopied(null), 1500);
    } catch {
      setCopied(null);
    }
  }

  async function saveAsset() {
    const items = validateDraft(draft, {
      existingIds, model: glbStats, texture: textureStats,
      baseSize: BASE_REST_SIZE_METERS, hasSourceFile: !!draft.sourceFileName,
    });
    setValidation(items);
    if (items.some((i) => i.level === "error")) {
      setSaveMsg("Error があります。修正してから保存してください。");
      return;
    }
    const metadata = draftToAssetJson(draft);
    const toDataUrl = (url: string | null | undefined) =>
      url ? fetch(url).then((r) => r.blob()).then(blobToDataUrl) : Promise.resolve(undefined);
    const [modelData, textureData, thumbData] = await Promise.all([
      toDataUrl(model?.url), toDataUrl(textureFile?.url), Promise.resolve(thumb ?? undefined),
    ]);
    try {
      const { replaced } = saveUserAsset({
        metadata, model: modelData, texture: textureData, thumbnail: thumbData,
        savedAt: new Date().toISOString(),
      });
      setSaveMsg(`${replaced ? "更新" : "保存"}しました: ${metadata.id} — Character Builder の Asset Library に表示されます。`);
    } catch (error) {
      setSaveMsg(error instanceof Error ? error.message : "保存に失敗しました。");
    }
  }

  function downloadJson() {
    downloadBlob(new Blob([assetJsonText(draft)], { type: "application/json" }), `${draft.id || "asset"}.asset.json`);
  }
  async function downloadPackage() {
    const entries: { name: string; data: Uint8Array }[] = [
      { name: "asset.json", data: new TextEncoder().encode(assetJsonText(draft)) },
    ];
    if (model) entries.push({ name: "model.glb", data: new Uint8Array(await (await fetch(model.url)).arrayBuffer()) });
    if (textureFile) entries.push({ name: "texture.png", data: new Uint8Array(await (await fetch(textureFile.url)).arrayBuffer()) });
    if (thumb) entries.push({ name: "thumbnail.png", data: await dataUrlToBytes(thumb) });
    downloadBlob(createZip(entries), `${draft.id || "asset"}.zip`);
  }

  const counts = validation ? countByLevel(validation) : null;
  const weapon = isWeapon(draft.type);
  const hasHairPolicy = HAIR_POLICY_TYPES.includes(draft.type);

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">ASSET WORKSPACE</p>
          <h1>Asset Creator</h1>
          <p>新規 Asset を定義し、Preview / Validation し、AI Agent 向け Prompt を生成します。</p>
        </div>
        <span className="badge">PHASE 4</span>
      </div>

      <div className="creator-workspace">
        {/* ---- Form ---- */}
        <section className="panel creator-form">
          <h2>Asset Definition</h2>

          <label>Asset Type
            <select value={draft.type} onChange={(e) => changeType(e.target.value as AssetType)}>
              {ASSET_TYPES.map((t) => <option key={t} value={t}>{ASSET_TYPE_LABELS[t]}</option>)}
            </select>
          </label>

          <label>Name
            <input value={draft.name} placeholder="例: Short Hair 01" onChange={(e) => changeName(e.target.value)} />
          </label>

          <label>ID (snake_case)
            <input
              value={draft.id}
              onChange={(e) => { setIdEdited(true); update({ id: e.target.value }); }}
              aria-invalid={!!draft.id && !isSnakeCase(draft.id)}
            />
          </label>
          <div className="form-hint">
            <button type="button" className="mini" onClick={() => { setIdEdited(false); update({ id: suggestId(draft.name, draft.type) }); }}>Name から再生成</button>
            {draft.id && !isSnakeCase(draft.id) && <span className="err"> snake_case ではありません</span>}
            {draft.id && existingIds.includes(draft.id) && <span className="err"> ID 重複</span>}
            {willReplace && <span className="warn"> 既存ユーザー Asset を更新します</span>}
          </div>

          <fieldset>
            <legend>Body Type</legend>
            {BODY_TYPES.map((bt) => (
              <label key={bt} className="check">
                <input type="checkbox" checked={draft.bodyTypes.includes(bt)}
                  onChange={() => update({ bodyTypes: toggle(draft.bodyTypes, bt) as BodyType[] })} />
                {bt}
              </label>
            ))}
          </fieldset>

          <label>Description
            <textarea rows={3} value={draft.description} onChange={(e) => update({ description: e.target.value })} placeholder="形状・用途のメモ" />
          </label>

          <label>Attachment Socket
            <select value={draft.socket} onChange={(e) => update({ socket: e.target.value as CharacterSocket })}>
              {CHARACTER_SOCKETS.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <div className="form-hint">
            推奨: {RECOMMENDED_SOCKET[draft.type]}
            {draft.socket !== RECOMMENDED_SOCKET[draft.type] &&
              <button type="button" className="mini" onClick={() => update({ socket: RECOMMENDED_SOCKET[draft.type] })}>推奨に戻す</button>}
          </div>

          <fieldset>
            <legend>Palette Slots</legend>
            {PALETTE_SLOTS.map((slot) => (
              <label key={slot} className="check">
                <input type="checkbox" checked={draft.paletteSlots.includes(slot)}
                  onChange={() => update({ paletteSlots: toggle(draft.paletteSlots, slot) as PaletteSlot[] })} />
                {slot}
              </label>
            ))}
            <button type="button" className="mini" onClick={() => update({ paletteSlots: [...SUGGESTED_PALETTE_SLOTS[draft.type]] })}>推奨セット</button>
          </fieldset>

          {hasHairPolicy && (
            <label>Hair Policy
              <select value={draft.hairPolicy ?? ""} onChange={(e) => update({ hairPolicy: (e.target.value || null) as AssetDraft["hairPolicy"] })}>
                <option value="hide">hide (髪を隠す)</option>
                <option value="overlay">overlay (髪と共存)</option>
              </select>
            </label>
          )}

          {weapon && (
            <fieldset className="weapon-block">
              <legend>Weapon</legend>
              <label>Weapon Type
                <select value={draft.weaponType} onChange={(e) => changeWeaponType(e.target.value as AssetDraft["weaponType"])}>
                  {WEAPON_TYPES.map((w) => <option key={w} value={w}>{w}</option>)}
                </select>
              </label>
              <label>Handling
                <select value={draft.handling} onChange={(e) => changeHandling(e.target.value as AssetDraft["handling"])}>
                  {WEAPON_HANDLING.map((h) => <option key={h} value={h}>{h}</option>)}
                </select>
              </label>
              <label>Animation Set
                <select value={draft.animationSet} onChange={(e) => update({ animationSet: e.target.value as AssetDraft["animationSet"] })}>
                  {ANIMATION_SETS.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
              </label>
              <div className="grip-row">
                <span>Grip Point</span>
                {(["grip_main", "grip_sub"] as GripPoint[]).map((g) => (
                  <label key={g} className="check">
                    <input type="checkbox" checked={draft.gripPoints.includes(g)}
                      onChange={() => update({ gripPoints: toggle(draft.gripPoints, g) })} />
                    {g}
                  </label>
                ))}
              </div>
              <p className="muted">
                {draft.handling === "two_hand"
                  ? "grip_main → socket_hand_right, grip_sub → socket_hand_left"
                  : draft.handling === "off_hand"
                    ? "grip_main → socket_hand_left"
                    : "grip_main → socket_hand_right"}
              </p>
              <label>Texture Resolution
                <select value={draft.textureResolution} onChange={(e) => update({ textureResolution: Number(e.target.value) })}>
                  {WEAPON_TEXTURE_SIZES.map((n) => <option key={n} value={n}>{n} × {n}</option>)}
                </select>
              </label>
            </fieldset>
          )}

          <div className="hideparts">
            <button type="button" className="mini" onClick={() => setShowHideParts((v) => !v)}>
              {showHideParts ? "▼" : "▶"} Hide Parts ({draft.hideParts.length})
            </button>
            {showHideParts && (
              <div className="hidepart-list">
                {BASE_PARTS.map((part) => (
                  <label key={part.name} className="check">
                    <input type="checkbox" checked={draft.hideParts.includes(part.name)}
                      onChange={() => update({ hideParts: toggle(draft.hideParts, part.name) })} />
                    {part.name}{part.hint && <em> · {part.hint}</em>}
                  </label>
                ))}
              </div>
            )}
          </div>

          <div className="imports">
            <input ref={modelInput} type="file" accept=".glb,model/gltf-binary" hidden onChange={(e) => onPickModel(e.target.files?.[0])} />
            <input ref={textureInput} type="file" accept=".png,image/png" hidden onChange={(e) => onPickTexture(e.target.files?.[0])} />
            <input ref={sourceInput} type="file" accept=".bbmodel" hidden onChange={(e) => onPickSource(e.target.files?.[0])} />
            <button type="button" onClick={() => modelInput.current?.click()}>Import Model (.glb)</button>
            <button type="button" onClick={() => textureInput.current?.click()}>Import Texture (.png)</button>
            <button type="button" onClick={() => sourceInput.current?.click()}>Link Source (.bbmodel)</button>
            <ul className="import-status">
              <li>Model: {model ? model.name : "—"}</li>
              <li>Texture: {textureFile ? `${textureFile.name}${textureStats ? ` (${textureStats.width}×${textureStats.height})` : ""}` : "—"}</li>
              <li>Source: {draft.sourceFileName ?? "—"}</li>
            </ul>
            <p className="muted">
              <code>.bbmodel</code> はブラウザで解析しないため Preview は変化しません。ここではファイル名を
              <code> asset.json</code> の <code>source.path</code> に記録するだけで、ファイル自体は保存されません。
              実ファイルを保管するのは AI Production の Import です。
              Texture は Model の UV に従って貼られます（UV が無い GLB では反映されません）。
            </p>
          </div>

          <div className="dir-hint">出力先: <code>{assetDir(draft)}/</code></div>
        </section>

        {/* ---- Preview ---- */}
        <section className="panel preview-panel">
          <div className="panel-heading">
            <h2>3D Preview</h2>
            <div className="seg">
              <button type="button" className={mode === "asset" ? "on" : ""} onClick={() => setMode("asset")}>Asset Only</button>
              <button type="button" className={mode === "base" ? "on" : ""} onClick={() => setMode("base")}>Base + Asset</button>
            </div>
          </div>

          <div className="anim-bar" aria-disabled={mode !== "base"}>
            <label className="inline">Animation
              <select value={animRole} disabled={mode !== "base"} onChange={(e) => setAnimRole(e.target.value as typeof animRole)}>
                {ANIM_ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </label>
            <button type="button" disabled={mode !== "base"} onClick={() => setAnimPlaying((p) => !p)}>{animPlaying ? "⏸ Pause" : "▶ Play"}</button>
            <label className="inline">Speed
              <input type="range" min={0.25} max={2} step={0.25} value={animSpeed} disabled={mode !== "base"} onChange={(e) => setAnimSpeed(Number(e.target.value))} />
              <span>{animSpeed.toFixed(2)}×</span>
            </label>
            <label className="check"><input type="checkbox" checked={animLoop} disabled={mode !== "base"} onChange={(e) => setAnimLoop(e.target.checked)} />loop</label>
          </div>
          {mode === "base" && anim.warnings.length > 0 && (
            <p className="muted anim-warn">{anim.warnings.join(" / ")}</p>
          )}

          <CreatorPreview
            key={`${mode}:${model?.url ?? "none"}:${referenceHair !== "none"}`}
            assetModelUrl={model?.url ?? null}
            assetTextureUrl={textureFile?.url ?? null}
            mode={mode}
            socket={draft.socket}
            paletteColor={paletteColor}
            hideParts={draft.hideParts}
            animationClip={anim.name}
            animationPlaying={animPlaying}
            animationSpeed={animSpeed}
            animationLoop={animLoop}
            referenceHair={referenceHair}
            gripRotationDeg={gripRotationDeg}
            captureSignal={captureSignal}
            onThumbnail={setThumb}
            onModelStats={setGlbStats}
          />

          <div className="preview-extras">
            <div className="palette-row">
              {draft.paletteSlots.length === 0 && <span className="muted">Palette Slot 未選択</span>}
              {draft.paletteSlots.map((slot) => (
                <label key={slot} className="swatch">
                  <input type="color" value={palette[slot]} onChange={(e) => setPalette((p) => ({ ...p, [slot]: e.target.value }))} />
                  {slot}
                </label>
              ))}
            </div>
            <div className="thumb-row">
              <button type="button" onClick={() => setCaptureSignal((n) => n + 1)}>Capture Thumbnail</button>
              {thumb
                // eslint-disable-next-line @next/next/no-img-element
                ? <img className="thumb" src={thumb} alt="thumbnail preview" width={72} height={72} />
                : <span className="muted">未生成</span>}
            </div>
          </div>
          {mode === "base" && (
            <p className="creator-note">
              Base + Asset は base_1.bbmodel 由来の GLB（Rest + Animation bake）に Socket 取り付けした表示です。IK なし、Grip / Socket の位置整合確認まで。
              {hasHairPolicy && " Hair Policy の効果は socket_hair の参照ブロックで確認できます。"}
            </p>
          )}
        </section>
      </div>

      {/* ---- Prompt ---- */}
      <section className="panel prompt-panel">
        <div className="panel-heading">
          <h2>AI Prompt Generator</h2>
          <button type="button" onClick={generatePrompts}>Generate Prompt</button>
        </div>
        {!prompts && <p className="muted">Generate Prompt で 3D Model Prompt と Texture Prompt を生成します。生成後にこの場で編集できます。</p>}
        {prompts && (
          <div className="prompt-grid">
            {(["model", "texture"] as const).map((which) => (
              <div key={which} className="prompt-col">
                <div className="prompt-col-head">
                  <strong>{which === "model" ? "3D Model Prompt" : "Texture Prompt"}</strong>
                  <button type="button" onClick={() => copyPrompt(which)}>{copied === which ? "Copied" : "Copy"}</button>
                </div>
                <textarea
                  rows={18}
                  value={prompts[which]}
                  onChange={(e) => setPrompts((p) => (p ? { ...p, [which]: e.target.value } : p))}
                />
              </div>
            ))}
          </div>
        )}
      </section>

      {/* ---- AI Production (Phase 9) ---- */}
      <ProductionPanel draft={draft} />

      {/* ---- Validation ---- */}
      <section className="panel validation-panel">
        <div className="panel-heading">
          <h2>Validation</h2>
          <button type="button" onClick={runValidation}>Validate</button>
        </div>
        {!validation && <p className="muted">Metadata / Model / Texture / Attachment を検証します（Error / Warning / Info）。</p>}
        {validation && (
          <>
            <p className="val-counts">
              <span className="err">Error {counts!.error}</span>
              <span className="warn">Warning {counts!.warning}</span>
              <span className="info">Info {counts!.info}</span>
            </p>
            <ul className="val-list">
              {validation.length === 0 && <li>問題は検出されませんでした。</li>}
              {validation.map((item, i) => (
                <li key={i} className={`val ${item.level}`}>
                  <span className="val-tag">{item.level.toUpperCase()}</span>
                  <span className="val-sec">{item.section}</span>
                  <span>{item.message}</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>

      {/* ---- Save ---- */}
      <section className="panel save-panel">
        <div className="panel-heading"><h2>Save Asset</h2></div>
        <div className="save-actions">
          <button type="button" onClick={saveAsset}>Save Asset (localStorage)</button>
          <button type="button" onClick={downloadJson}>Download asset.json</button>
          <button type="button" onClick={downloadPackage}>Download Package (.zip)</button>
        </div>
        {saveMsg && <p className="save-msg">{saveMsg}</p>}
        <CreatorLibrarySave
          metadata={draftToAssetJson(draft)}
          modelUrl={model?.url ?? null}
          textureUrl={textureFile?.url ?? null}
          thumbnail={thumb}
        />
        <p className="muted">
          Phase 7: 「Save to Asset Library」は <code>library-data/assets/&lt;id&gt;/</code> に永続化し、Asset Library / Character Builder に即時反映します。
        </p>
        <p className="muted">
          Save Asset は localStorage に保存し、Character Builder と共有します。リポジトリへの書き込みは Phase 4 では行いません。
          Package は <code>asset.json / model.glb / texture.png / thumbnail.png</code> をまとめた zip です。
        </p>
      </section>
    </>
  );
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}
