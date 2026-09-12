"use client";

// Phase 8 Palette Set editor (spec section 18-19). Colours are always drawn from curated lists,
// so this is where the user curates them: per-faction sets plus the shared Skin / Hair pools.
import { useState } from "react";
import { PALETTE_SLOTS, type PaletteSlot } from "@/domain/constants";
import { isHexColor } from "@/domain/phase3";
import { normalizeTag } from "@/domain/library-ids";
import { defaultPaletteLibrary, type PaletteLibrary, type PaletteSet } from "@/domain/variation-palette";

export function PaletteSetEditor({ library, onSave, busy }: {
  library: PaletteLibrary;
  onSave: (next: PaletteLibrary) => void;
  busy: boolean;
}) {
  const [draft, setDraft] = useState<PaletteLibrary>(library);
  const [newSetId, setNewSetId] = useState("");

  const patchSet = (id: string, patch: Partial<PaletteSet>) =>
    setDraft({ ...draft, sets: draft.sets.map((s) => (s.id === id ? { ...s, ...patch } : s)) });

  const setColor = (id: string, slot: PaletteSlot, i: number, value: string) => {
    const set = draft.sets.find((s) => s.id === id);
    if (!set) return;
    const colors = [...set.colors[slot]];
    colors[i] = value.toLowerCase();
    patchSet(id, { colors: { ...set.colors, [slot]: colors } });
  };
  const addColor = (id: string, slot: PaletteSlot) => {
    const set = draft.sets.find((s) => s.id === id);
    if (!set) return;
    patchSet(id, { colors: { ...set.colors, [slot]: [...set.colors[slot], "#888888"] } });
  };
  const removeColor = (id: string, slot: PaletteSlot, i: number) => {
    const set = draft.sets.find((s) => s.id === id);
    if (!set) return;
    patchSet(id, { colors: { ...set.colors, [slot]: set.colors[slot].filter((_, k) => k !== i) } });
  };

  const patchPool = (key: "skinPool" | "hairPool", i: number, value: string) => {
    const pool = [...draft[key]];
    pool[i] = value.toLowerCase();
    setDraft({ ...draft, [key]: pool });
  };

  function addSet() {
    const id = normalizeTag(newSetId);
    if (!id || draft.sets.some((s) => s.id === id)) return;
    const colors = Object.fromEntries(PALETTE_SLOTS.map((s) => [s, [] as string[]])) as PaletteSet["colors"];
    setDraft({ ...draft, sets: [...draft.sets, { id, name: id, colors }] });
    setNewSetId("");
  }

  const invalid = draft.sets.some((s) => PALETTE_SLOTS.some((slot) => s.colors[slot].some((c) => !isHexColor(c))))
    || draft.skinPool.some((c) => !isHexColor(c)) || draft.hairPool.some((c) => !isHexColor(c));

  return (
    <div className="var-editor">
      <section className="var-block">
        <h3>Palette Sets</h3>
        {draft.sets.map((set) => (
          <details key={set.id} className="var-slot">
            <summary><strong>{set.name}</strong><span className="muted">{set.id}</span></summary>
            <div className="var-slot-body">
              <label>Name<input value={set.name} onChange={(e) => patchSet(set.id, { name: e.target.value })} /></label>
              {PALETTE_SLOTS.map((slot) => (
                <div key={slot} className="var-pal-slot">
                  <span>{slot}</span>
                  <div className="var-pal-colors">
                    {set.colors[slot].map((c, i) => (
                      <span key={i} className="var-pal-chip">
                        <input type="color" value={isHexColor(c) ? c : "#888888"} onChange={(e) => setColor(set.id, slot, i, e.target.value)} />
                        <button type="button" className="mini" onClick={() => removeColor(set.id, slot, i)}>×</button>
                      </span>
                    ))}
                    <button type="button" className="mini" onClick={() => addColor(set.id, slot)}>+</button>
                  </div>
                  {set.colors[slot].length === 0 && (
                    <small className="muted">{slot === "skin" || slot === "hair" ? "共通 Pool を使用" : "Recipe 既定色を使用"}</small>
                  )}
                </div>
              ))}
              <button type="button" className="danger mini"
                onClick={() => setDraft({ ...draft, sets: draft.sets.filter((s) => s.id !== set.id) })}>Delete Set</button>
            </div>
          </details>
        ))}
        <div className="var-inline">
          <input value={newSetId} placeholder="新しい Palette Set ID" onChange={(e) => setNewSetId(e.target.value)} />
          <button type="button" onClick={addSet}>Add Palette Set</button>
        </div>
      </section>

      {(["skinPool", "hairPool"] as const).map((key) => (
        <section key={key} className="var-block">
          <h3>{key === "skinPool" ? "Skin Palette Pool" : "Hair Palette Pool"}</h3>
          <div className="var-pal-colors">
            {draft[key].map((c, i) => (
              <span key={i} className="var-pal-chip">
                <input type="color" value={isHexColor(c) ? c : "#888888"} onChange={(e) => patchPool(key, i, e.target.value)} />
                <button type="button" className="mini" onClick={() => setDraft({ ...draft, [key]: draft[key].filter((_, k) => k !== i) })}>×</button>
              </span>
            ))}
            <button type="button" className="mini" onClick={() => setDraft({ ...draft, [key]: [...draft[key], "#888888"] })}>+</button>
          </div>
          <p className="muted">完全な RGB Random は行いません。ここにある候補からのみ選択されます。</p>
        </section>
      ))}

      <div className="lib-actions">
        <button type="button" disabled={busy || invalid} onClick={() => onSave(draft)}>Save Palette Sets</button>
        <button type="button" disabled={busy} onClick={() => setDraft(library)}>Revert</button>
        <button type="button" disabled={busy} onClick={() => setDraft(defaultPaletteLibrary())}>Load Defaults</button>
      </div>
    </div>
  );
}
