"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useLibraryIndex } from "./use-library-index";
import { deriveLibrary } from "./derive";
import { fetchBackup } from "./api";
import { downloadBlob } from "@/features/asset-creator/zip";
import { ValidationBadge } from "./components/badges";

export function DashboardScreen() {
  const { index, loading, error, refresh } = useLibraryIndex();
  const derived = useMemo(() => deriveLibrary(index), [index]);
  const d = derived.dashboard;

  async function exportIndex() {
    const backup = await fetchBackup();
    downloadBlob(
      new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" }),
      `library-index-${new Date().toISOString().slice(0, 10)}.json`,
    );
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">CHARACTER ASSET DASHBOARD</p>
          <h1>Library Dashboard</h1>
          <p>Asset / Character の一覧・検証・Export・Registry 状態を集約します。数字をクリックすると該当一覧へ移動します。</p>
        </div>
        <span className="badge">PHASE 7 · MANAGEMENT</span>
      </div>

      {error && <p className="err">Library API エラー: {error} <button className="mini" onClick={() => refresh()}>再試行</button></p>}

      <div className="dash-grid">
        <Link href="/assets" className="dash-card"><span className="dash-num">{d.assets}</span><span>Assets</span></Link>
        <Link href="/characters" className="dash-card"><span className="dash-num">{d.characters}</span><span>Characters</span></Link>
        <Link href="/validation" className={`dash-card ${d.validationErrors ? "danger" : ""}`}><span className="dash-num">{d.validationErrors}</span><span>Validation Errors</span></Link>
        <Link href="/characters?filter=reexport" className={`dash-card ${d.reexportRequired ? "warnc" : ""}`}><span className="dash-num">{d.reexportRequired}</span><span>Re-export Required</span></Link>
        <Link href="/characters?filter=registry" className={`dash-card ${d.registryIssues ? "warnc" : ""}`}><span className="dash-num">{d.registryIssues}</span><span>Registry Issues</span></Link>
        <Link href="/characters?filter=missing" className={`dash-card ${d.missingDependencies ? "danger" : ""}`}><span className="dash-num">{d.missingDependencies}</span><span>Missing Dependencies</span></Link>
      </div>

      <div className="dash-lower">
        <section className="panel">
          <div className="panel-heading"><h2>Recently Updated · Assets</h2></div>
          <ul className="recent-list">
            {derived.recentAssets.map((a) => (
              <li key={a.metadata.id}>
                <Link href={`/assets?id=${a.metadata.id}`}>{a.metadata.id}</Link>
                <ValidationBadge status={a.validation.status} />
                <span className="muted">v{a.metadata.assetVersion} · {new Date(a.updatedAt).toLocaleString()}</span>
              </li>
            ))}
            {derived.recentAssets.length === 0 && <li className="muted">まだ Asset がありません。</li>}
          </ul>
        </section>

        <section className="panel">
          <div className="panel-heading"><h2>Recently Updated · Characters</h2></div>
          <ul className="recent-list">
            {derived.recentCharacters.map((c) => (
              <li key={c.recipe.id}>
                <Link href={`/characters?id=${c.recipe.id}`}>{c.recipe.id}</Link>
                <ValidationBadge status={c.validation.status} />
                <span className="muted">v{c.recipe.characterVersion ?? 1} · {new Date(c.updatedAt).toLocaleString()}</span>
              </li>
            ))}
            {derived.recentCharacters.length === 0 && <li className="muted">まだ Character がありません。</li>}
          </ul>
        </section>

        <section className="panel">
          <div className="panel-heading"><h2>Registry Sync</h2></div>
          <div className="reg-sync">
            <p><strong>Not registered:</strong> {derived.registrySync.missingInRegistry.join(", ") || "—"}</p>
            <p><strong>Unknown in registry:</strong> {derived.registrySync.unknownInRegistry.join(", ") || "—"}</p>
            <p><strong>Version mismatch:</strong> {derived.registrySync.versionMismatch.map((m) => `${m.id} (lib v${m.libraryVersion} / reg v${m.registryVersion})`).join(", ") || "—"}</p>
          </div>
        </section>

        <section className="panel">
          <div className="panel-heading"><h2>Backup</h2></div>
          <div className="reg-sync">
            <p className="muted">Asset index / Character index / Versions / Tags / Dependencies を 1 つの JSON に書き出します（バイナリは含みません）。</p>
            <button type="button" onClick={exportIndex}>Export Library Index</button>
          </div>
        </section>
      </div>

      {loading && <p className="muted">Loading…</p>}
    </>
  );
}
