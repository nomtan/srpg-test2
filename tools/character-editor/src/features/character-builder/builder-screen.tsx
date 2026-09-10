"use client";

import { useState } from "react";
import { AssetPreview } from "@/components/preview/asset-preview";
import { AssetBrowser } from "@/features/asset-library/asset-browser";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { modelUrl } from "@/features/asset-library/library";

export function BuilderScreen() {
  const library = useMergedLibrary();
  const [selectedId, setSelectedId] = useState("base_body");
  const selected = library.byId[selectedId] ?? library.byId["base_body"];
  const userCount = library.ids.filter((id) => library.byId[id].provenance === "user").length;

  return <>
    <div className="page-heading"><div><p className="eyebrow">CHARACTER WORKSPACE</p><h1>Character Builder</h1><p>既存base_1.bbmodelを基準に、素体の形状と構造を確認。Asset Creatorで保存したAssetもここに表示されます。</p></div><span className="badge">PHASE 2 · BASE MODEL{userCount ? ` · +${userCount} USER` : ""}</span></div>
    <div className="workspace"><AssetBrowser library={library} selectedId={selected.metadata.id} onSelect={(entry) => setSelectedId(entry.metadata.id)} />
      <section className="panel preview-panel"><div className="panel-heading"><h2>{selected.metadata.name}</h2><span className="muted">3D Preview</span></div><AssetPreview url={modelUrl(selected)} name={selected.metadata.name} /></section>
      <aside className="panel inspector"><h2>Asset Details</h2><dl><dt>ID</dt><dd>{selected.metadata.id}</dd><dt>Type</dt><dd>{selected.metadata.type}</dd><dt>Body Type</dt><dd>{selected.metadata.bodyTypes.join(" / ")}</dd><dt>Source</dt><dd>{selected.provenance ?? "static"}</dd><dt>Runtime</dt><dd>{selected.metadata.model}</dd><dt>Handling</dt><dd>{selected.metadata.equipment?.handling ?? "—"}</dd><dt>Animation Set</dt><dd>{selected.metadata.equipment?.animationSet ?? "—"}</dd><dt>Palette Slots</dt><dd>{selected.metadata.appearance.paletteSlots.join(", ") || "—"}</dd></dl><p className="muted">現在は単体Previewのみ。Recipeの保存・装備合成は後続フェーズです。</p></aside>
    </div>
    <section className="panel future-controls"><div><h2>Body Scale</h2><p>Height / Body Width / Head Scale</p></div><div><h2>Palette</h2><p>primary / secondary / metal / leather / hair / skin</p></div><div><h2>Animation</h2><p>Base / Weapon Animation Set</p></div><span className="badge">後続フェーズ</span></section>
  </>;
}
