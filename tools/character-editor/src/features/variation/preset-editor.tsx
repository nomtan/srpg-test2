"use client";

// Phase 8 Preset Editor (spec section 40). Everything a preset holds is editable here: identity,
// faction / role, body type + scale ranges, gender expression, shoulder mode, palette plan and the
// per-category rule (required / optional / forbidden, probability, tags, weapon types, allowed
// assets, weights). The editor never generates — it only produces the preset object.
import { useMemo, useState } from "react";
import { BODY_TYPES, PALETTE_SLOTS, WEAPON_TYPES, type BodyType, type PaletteSlot, type WeaponType } from "@/domain/constants";
import { SLOT_LABEL } from "@/domain/builder-recipe";
import { normalizeTag } from "@/domain/library-ids";
import {
  BODY_SCALE_PROFILES, BODY_SCALE_PROFILE_LABEL, GENDER_EXPRESSIONS, PRESENCE_MODES,
  SHOULDER_MODES, SHOULDER_MODE_LABEL, SLOT_ORDER, bodyScaleForProfile, clampCount,
  clampVariationScale, MAX_COUNT,
  type BodyScaleProfile, type GenderExpression, type PresenceMode, type ShoulderMode,
  type SlotRule, type VariationPreset, type VariationSlot,
} from "@/domain/variation-preset";
import { buildPool, emptyContext, resolveWeight, REJECT_LABEL, type CandidateAsset } from "@/domain/variation-candidates";
import type { PaletteLibrary } from "@/domain/variation-palette";
import { randomSeed } from "@/domain/variation-rng";
import type { PresetValidationResult } from "@/domain/variation-validation";

export interface PresetEditorProps {
  draft: VariationPreset;
  onChange: (next: VariationPreset) => void;
  assets: readonly CandidateAsset[];
  libraryTags: readonly string[];
  palettes: PaletteLibrary;
  validation: PresetValidationResult;
  /** Preset id is the file name; it stays write-once, like Asset / Character ids (Phase 7). */
  idEditable: boolean;
}

const SCALE_AXES = [
  ["height", "Height"], ["bodyWidth", "Body Width"], ["headScale", "Head Scale"],
] as const;

export function PresetEditor(props: PresetEditorProps) {
  const { draft, onChange, assets, libraryTags, palettes, validation, idEditable } = props;
  const patch = (p: Partial<VariationPreset>) => onChange({ ...draft, ...p });
  const patchSlot = (slot: VariationSlot, p: Partial<SlotRule>) =>
    onChange({ ...draft, slots: { ...draft.slots, [slot]: { ...draft.slots[slot], ...p } } });

  const issuesBySlot = useMemo(() => {
    const map = new Map<VariationSlot, string[]>();
    for (const issue of validation.issues) {
      if (!issue.slot) continue;
      map.set(issue.slot, [...(map.get(issue.slot) ?? []), `${issue.level.toUpperCase()}: ${issue.message}`]);
    }
    return map;
  }, [validation.issues]);

  return (
    <div className="var-editor">
      <section className="var-block">
        <h3>Identity</h3>
        <div className="var-grid2">
          <label>Preset ID
            <input value={draft.id} readOnly={!idEditable}
              onChange={(e) => idEditable && patch({ id: normalizeTag(e.target.value) })} />
          </label>
          <label>Name<input value={draft.name} onChange={(e) => patch({ name: e.target.value })} /></label>
          <label>Faction<input value={draft.faction} placeholder="kingdom / empire / elf / bandit / civilian"
            onChange={(e) => patch({ faction: normalizeTag(e.target.value) })} /></label>
          <label>Role<input value={draft.role} placeholder="soldier / archer / knight / villager"
            onChange={(e) => patch({ role: normalizeTag(e.target.value) })} /></label>
          <label>Suggested Role<input value={draft.suggestedRole} placeholder="Metadata のみ。Job とは結合しません。"
            onChange={(e) => patch({ suggestedRole: normalizeTag(e.target.value) })} /></label>
          <label>Character ID Prefix<input value={draft.idPrefix}
            onChange={(e) => patch({ idPrefix: normalizeTag(e.target.value) })} /></label>
          <label>Display Name Prefix<input value={draft.namePrefix}
            onChange={(e) => patch({ namePrefix: e.target.value })} /></label>
          <label>Description<input value={draft.description} onChange={(e) => patch({ description: e.target.value })} /></label>
        </div>
        <TagField label="Character Tags" value={draft.tags} options={libraryTags}
          onChange={(tags) => patch({ tags })} />
        {!idEditable && <p className="muted">Preset ID は保存後は変更できません。別 ID が必要な場合は Duplicate を使用してください。</p>}
      </section>

      <section className="var-block">
        <h3>Batch</h3>
        <div className="var-grid2">
          <label>Count (1 - {MAX_COUNT})
            <input type="number" min={1} max={MAX_COUNT} value={draft.count}
              onChange={(e) => patch({ count: clampCount(Number(e.target.value)) })} />
          </label>
          <label>Seed
            <input type="number" min={0} value={draft.seed}
              onChange={(e) => patch({ seed: Math.abs(Math.floor(Number(e.target.value) || 0)) })} />
          </label>
        </div>
        <button type="button" className="mini" onClick={() => patch({ seed: randomSeed() })}>Generate New Seed</button>
      </section>

      <section className="var-block">
        <h3>Body</h3>
        <fieldset><legend>Body Type</legend>
          {BODY_TYPES.map((b) => (
            <label key={b} className="check">
              <input type="checkbox" checked={draft.bodyTypes.includes(b)}
                onChange={() => {
                  const next: BodyType[] = draft.bodyTypes.includes(b)
                    ? draft.bodyTypes.filter((x) => x !== b)
                    : [...draft.bodyTypes, b];
                  patch({ bodyTypes: next });
                }} />{b}
            </label>
          ))}
        </fieldset>
        <div className="var-grid2">
          <label>Gender Expression
            <select value={draft.genderExpression} onChange={(e) => patch({ genderExpression: e.target.value as GenderExpression })}>
              {GENDER_EXPRESSIONS.map((g) => <option key={g} value={g}>{g === "any" ? "Any" : g}</option>)}
            </select>
          </label>
          <label>Body Scale Profile
            <select value={draft.bodyScale.profile}
              onChange={(e) => {
                const profile = e.target.value as BodyScaleProfile;
                patch({ bodyScale: profile === "custom" ? { ...draft.bodyScale, profile } : bodyScaleForProfile(profile) });
              }}>
              {BODY_SCALE_PROFILES.map((p) => <option key={p} value={p}>{BODY_SCALE_PROFILE_LABEL[p]}</option>)}
            </select>
          </label>
        </div>
        <div className="var-ranges">
          {SCALE_AXES.map(([key, label]) => (
            <div key={key} className="var-range">
              <span>{label}</span>
              <input type="number" step={0.01} value={draft.bodyScale[key].min}
                onChange={(e) => patch({
                  bodyScale: { ...draft.bodyScale, profile: "custom", [key]: { ...draft.bodyScale[key], min: clampVariationScale(Number(e.target.value)) } },
                })} />
              <em>-</em>
              <input type="number" step={0.01} value={draft.bodyScale[key].max}
                onChange={(e) => patch({
                  bodyScale: { ...draft.bodyScale, profile: "custom", [key]: { ...draft.bodyScale[key], max: clampVariationScale(Number(e.target.value)) } },
                })} />
            </div>
          ))}
        </div>
        <label>Shoulder Variation
          <select value={draft.shoulderMode} onChange={(e) => patch({ shoulderMode: e.target.value as ShoulderMode })}>
            {SHOULDER_MODES.map((m) => <option key={m} value={m}>{SHOULDER_MODE_LABEL[m]}</option>)}
          </select>
        </label>
        <p className="muted">生成される Scale は 0.85 - 1.15 にクランプされます（極端な体格は作りません）。</p>
      </section>

      <section className="var-block">
        <h3>Palette</h3>
        <label>Palette Set
          <select value={draft.palette.setId}
            onChange={(e) => patch({ palette: { ...draft.palette, setId: e.target.value } })}>
            {palettes.sets.map((s) => <option key={s.id} value={s.id}>{s.name} ({s.id})</option>)}
            {!palettes.sets.some((s) => s.id === draft.palette.setId) && <option value={draft.palette.setId}>{draft.palette.setId} (見つかりません)</option>}
          </select>
        </label>
        <div className="var-palette-rules">
          {PALETTE_SLOTS.map((slot: PaletteSlot) => {
            const rule = draft.palette.slots[slot];
            return (
              <div key={slot} className="var-palette-rule">
                <span>{slot}</span>
                <select value={rule.mode}
                  onChange={(e) => patch({
                    palette: { ...draft.palette, slots: { ...draft.palette.slots, [slot]: { ...rule, mode: e.target.value as typeof rule.mode } } },
                  })}>
                  <option value="set">Palette Set</option>
                  <option value="pool">Skin / Hair Pool</option>
                  <option value="fixed">Fixed</option>
                </select>
                {rule.mode === "fixed" && (
                  <input type="color" value={rule.fixed ?? "#888888"}
                    onChange={(e) => patch({
                      palette: { ...draft.palette, slots: { ...draft.palette.slots, [slot]: { ...rule, fixed: e.target.value } } },
                    })} />
                )}
              </div>
            );
          })}
        </div>
      </section>

      <section className="var-block">
        <h3>Allowed Assets / Rules</h3>
        {SLOT_ORDER.map((slot) => (
          <SlotRuleEditor
            key={slot}
            slot={slot}
            rule={draft.slots[slot]}
            assets={assets}
            libraryTags={libraryTags}
            bodyType={draft.bodyTypes[0] ?? "adult"}
            gender={draft.genderExpression}
            issues={issuesBySlot.get(slot) ?? []}
            onChange={(p) => patchSlot(slot, p)}
          />
        ))}
      </section>
    </div>
  );
}

function SlotRuleEditor({ slot, rule, assets, libraryTags, bodyType, gender, issues, onChange }: {
  slot: VariationSlot;
  rule: SlotRule;
  assets: readonly CandidateAsset[];
  libraryTags: readonly string[];
  bodyType: BodyType;
  gender: GenderExpression;
  issues: string[];
  onChange: (patch: Partial<SlotRule>) => void;
}) {
  const isWeaponSlot = slot === "mainHand" || slot === "offHand";
  const ctx = useMemo(() => emptyContext(bodyType, gender), [bodyType, gender]);

  // Candidates for the current rule, plus the unfiltered category list for the checkbox UI.
  const pool = useMemo(() => buildPool(assets, slot, rule, ctx), [assets, slot, rule, ctx]);
  const categoryAssets = useMemo(
    () => buildPool(assets, slot, { ...rule, tags: [], excludeTags: [], assetIds: [], weaponTypes: [] }, ctx).candidates,
    [assets, slot, rule, ctx],
  );

  const rejectSummary = Object.entries(pool.rejected)
    .map(([reason, n]) => `${REJECT_LABEL[reason as keyof typeof REJECT_LABEL]} ${n}`)
    .join(" / ");

  return (
    <details className={`var-slot ${rule.presence}`}>
      <summary>
        <strong>{SLOT_LABEL[slot]}</strong>
        <span className={`var-presence p-${rule.presence}`}>{rule.presence}</span>
        {rule.presence === "optional" && <span className="muted">{Math.round(rule.probability * 100)}%</span>}
        <span className={`var-count ${pool.candidates.length === 0 ? "zero" : ""}`}>{pool.candidates.length} candidates</span>
      </summary>

      <div className="var-slot-body">
        <div className="var-grid2">
          <label>Presence
            <select value={rule.presence} onChange={(e) => onChange({ presence: e.target.value as PresenceMode })}>
              {PRESENCE_MODES.map((m) => <option key={m} value={m}>{m}</option>)}
            </select>
          </label>
          <label>Probability {Math.round(rule.probability * 100)}%
            <input type="range" min={0} max={1} step={0.05} value={rule.probability}
              disabled={rule.presence !== "optional"}
              onChange={(e) => onChange({ probability: Number(e.target.value) })} />
          </label>
        </div>

        {isWeaponSlot && (
          <fieldset><legend>Weapon Types（未選択 = 制限なし）</legend>
            {WEAPON_TYPES.map((w: WeaponType) => (
              <label key={w} className="check">
                <input type="checkbox" checked={rule.weaponTypes.includes(w)}
                  onChange={() => onChange({
                    weaponTypes: rule.weaponTypes.includes(w)
                      ? rule.weaponTypes.filter((x) => x !== w)
                      : [...rule.weaponTypes, w],
                  })} />{w}
              </label>
            ))}
          </fieldset>
        )}

        <TagField label="Tags（いずれか一致）" value={rule.tags} options={libraryTags} onChange={(tags) => onChange({ tags })} />
        <TagField label="Exclude Tags" value={rule.excludeTags} options={libraryTags} onChange={(excludeTags) => onChange({ excludeTags })} />

        <div className="var-allowed">
          <div className="var-allowed-head">
            <span>Allowed Assets（未選択 = Tag 条件に合う全 Asset）</span>
            <button type="button" className="mini" onClick={() => onChange({ assetIds: [] })}>Clear</button>
          </div>
          {categoryAssets.length === 0 && <p className="muted">このカテゴリの Asset が Library にありません。</p>}
          <ul className="var-asset-list">
            {categoryAssets.map(({ asset }) => {
              const checked = rule.assetIds.length === 0 || rule.assetIds.includes(asset.id);
              const explicit = rule.assetIds.includes(asset.id);
              return (
                <li key={asset.id}>
                  <label className="check">
                    <input type="checkbox" checked={explicit}
                      onChange={() => onChange({
                        assetIds: explicit ? rule.assetIds.filter((x) => x !== asset.id) : [...rule.assetIds, asset.id],
                      })} />
                    <span className={checked ? "" : "muted"}>{asset.name}</span>
                    <small className="muted">{asset.id}{asset.tags.length ? ` · ${asset.tags.join(",")}` : ""}</small>
                  </label>
                  <input type="number" min={0} step={1} className="var-weight"
                    title="Weight（空欄で rarity / 既定値）"
                    value={rule.weights[asset.id] ?? resolveWeight(asset)}
                    onChange={(e) => {
                      const weights = { ...rule.weights };
                      const v = Number(e.target.value);
                      if (!Number.isFinite(v) || v < 0) delete weights[asset.id];
                      else weights[asset.id] = v;
                      onChange({ weights });
                    }} />
                </li>
              );
            })}
          </ul>
        </div>

        {rejectSummary && <p className="muted">除外: {rejectSummary}</p>}
        {issues.map((i, k) => <p key={k} className={i.startsWith("ERROR") ? "err" : "muted"}>{i}</p>)}
      </div>
    </details>
  );
}

function TagField({ label, value, options, onChange }: {
  label: string;
  value: readonly string[];
  options: readonly string[];
  onChange: (tags: string[]) => void;
}) {
  const [input, setInput] = useState("");
  const add = (raw: string) => {
    const tag = normalizeTag(raw);
    if (!tag || value.includes(tag)) return;
    onChange([...value, tag]);
  };
  return (
    <div className="var-tagfield">
      <span>{label}</span>
      <ul className="chip-list">
        {value.map((t) => (
          <li key={t}>{t} <button type="button" className="mini" onClick={() => onChange(value.filter((x) => x !== t))}>×</button></li>
        ))}
        {value.length === 0 && <li className="muted">なし</li>}
      </ul>
      <input value={input} placeholder="tag を入力して Enter"
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(input); setInput(""); } }} />
      {options.length > 0 && (
        <ul className="chip-list var-tag-options">
          {options.filter((t) => !value.includes(t)).slice(0, 24).map((t) => (
            <li key={t}><button type="button" className="mini" onClick={() => add(t)}>+ {t}</button></li>
          ))}
        </ul>
      )}
    </div>
  );
}
