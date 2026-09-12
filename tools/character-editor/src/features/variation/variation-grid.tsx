"use client";

// Phase 8 preview list (spec section 24). Thumbnail-centric on purpose: a batch of 100 variations
// renders from stored asset PNGs + palette swatches only. No GLB is loaded until a single
// character is opened in the detail panel.
import { PALETTE_SLOTS } from "@/domain/constants";
import type { CandidateAsset } from "@/domain/variation-candidates";
import type { GeneratedVariation } from "@/domain/variation-generator";

/** Slots shown on the card, most visually distinctive first. */
const CARD_SLOTS = ["mainHand", "chestArmor", "headgear", "hair"] as const;

export function VariationGrid({ variations, assetsById, selectedId, onSelect }: {
  variations: readonly GeneratedVariation[];
  assetsById: Map<string, CandidateAsset>;
  selectedId: string | null;
  onSelect: (id: string) => void;
}) {
  if (variations.length === 0) {
    return <p className="empty-list">まだ Preview がありません。[ Preview Variations ] を実行してください。</p>;
  }
  return (
    <ul className="var-grid">
      {variations.map((v) => {
        const thumbs = CARD_SLOTS
          .map((slot) => v.recipe.assets[slot])
          .filter((id): id is string => !!id)
          .map((id) => assetsById.get(id))
          .filter((a): a is CandidateAsset => !!a);
        const weaponId = v.recipe.assets.mainHand;
        const weapon = weaponId ? assetsById.get(weaponId) : null;
        return (
          <li key={v.id}>
            <button
              type="button"
              className={`var-card ${selectedId === v.id ? "sel" : ""} ${v.duplicate ? "dup" : ""}`}
              onClick={() => onSelect(v.id)}
            >
              <span className="var-card-head">
                <strong>[{String(v.index + 1).padStart(2, "0")}] {v.name}</strong>
                {v.duplicate && <em className="var-dup">Duplicate</em>}
              </span>
              <span className="var-card-thumbs">
                {thumbs.map((a) => (
                  a.thumbnailUrl
                    // eslint-disable-next-line @next/next/no-img-element
                    ? <img key={a.id} src={a.thumbnailUrl} alt={a.name} width={34} height={34} loading="lazy" />
                    : <span key={a.id} className="var-thumb-fallback" title={a.name} aria-hidden="true">◆</span>
                ))}
                {thumbs.length === 0 && <span className="var-thumb-fallback" aria-hidden="true">☗</span>}
              </span>
              <span className="pal-row">
                {PALETTE_SLOTS.map((s) => <span key={s} style={{ background: v.recipe.palette[s] }} title={`${s} ${v.recipe.palette[s]}`} />)}
              </span>
              <span className="var-card-meta">
                <small>{v.id}</small>
                <small>{weapon ? weapon.name : "武器なし"}</small>
                <small>H {v.recipe.body.scale.height} / W {v.recipe.body.scale.bodyWidth}</small>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
