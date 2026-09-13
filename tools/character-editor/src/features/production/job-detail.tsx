"use client";

// Phase 9 job detail: Import -> Validation -> Preview -> Approve / Reject / Needs Revision
// (spec section 37-48).
import { useMemo, useRef, useState } from "react";
import { ASSET_TYPE_LABELS } from "@/domain/asset-spec";
import { DEFAULT_PALETTE } from "@/domain/phase3";
import { gripAlignmentFor } from "@/viewer/equipment/gripAlignment";
import { buildValidationSpec } from "@/domain/production-package";
import { countIssues } from "@/domain/production-validation";
import { buildRevisionPrompt } from "@/domain/production-revision";
import { TYPE_ANIMATION_TEST } from "@/domain/production-profile";
import {
  PRODUCTION_STATUS_BADGE, MANUAL_STATUSES, PRODUCTION_STATUS_LABEL, type ProductionStatus,
} from "@/domain/production-status";
import { latestRevision, type ProductionIssue, type ProductionJob, type ProductionRevision } from "@/domain/production-job";
import { BAKED_BASE_CLIPS, resolveAnimation } from "@/viewer/animation/animationMapping";
import { CreatorPreview } from "@/features/asset-creator/creator-preview";
import { productionFileUrl } from "@/features/library/api";
import { useLibraryIndex } from "@/features/library/use-library-index";
import {
  approveRevision, deleteJob, importDelivery, markNeedsRevision, rejectRevision, revalidate,
  setJobStatus, type DeliveryFiles,
} from "./mutations";
import { exportProductionPackage } from "./package-export";

const LEVEL_MARK: Record<ProductionIssue["level"], string> = { error: "✕", warning: "⚠", info: "✓" };

export function JobDetail({ job, onChanged }: { job: ProductionJob; onChanged: () => void }) {
  const { index, refresh } = useLibraryIndex();
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [mode, setMode] = useState<"asset" | "base">("asset");
  const [animIndex, setAnimIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [copied, setCopied] = useState(false);

  const modelInput = useRef<HTMLInputElement>(null);
  const textureInput = useRef<HTMLInputElement>(null);
  const sourceInput = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState<DeliveryFiles>({});

  const revision = useMemo(() => {
    if (selected != null) return job.revisions.find((r) => r.revision === selected) ?? latestRevision(job);
    return latestRevision(job);
  }, [job, selected]);

  const spec = useMemo(() => buildValidationSpec(job), [job]);
  const animationRoles = TYPE_ANIMATION_TEST[job.draft.type].roles;
  const animationSet = spec.animation.set;
  const role = animationRoles[Math.min(animIndex, animationRoles.length - 1)] ?? "idle";
  const anim = useMemo(() => resolveAnimation(animationSet, role, BAKED_BASE_CLIPS), [animationSet, role]);

  const modelUrl = revision?.files.model ? productionFileUrl(job.id, revision.stage, revision.files.model) : null;
  const textureUrl = revision?.files.texture ? productionFileUrl(job.id, revision.stage, revision.files.texture) : null;

  const counts = revision ? countIssues(revision.validation.issues) : null;

  async function run(label: string, fn: () => Promise<unknown>) {
    setBusy(label);
    setMessage(null);
    try {
      await fn();
      await refresh();
      onChanged();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  }

  function pick(kind: keyof DeliveryFiles, file: File | undefined) {
    if (!file) return;
    setPending((p) => ({ ...p, [kind]: file }));
  }

  const hasPending = !!(pending.model || pending.texture || pending.source);

  async function doImport() {
    await run("import", async () => {
      await importDelivery(job, pending);
      setPending({});
      setSelected(null);
      setMessage("Import して Validation を実行しました。");
    });
  }

  const revisionPrompt = revision
    ? revision.revisionPrompt ??
      buildRevisionPrompt({ job, spec, validation: revision.validation, includeWarnings: true })
    : "";

  return (
    <section className="panel job-detail">
      <div className="panel-heading">
        <h2>{job.name || job.id}</h2>
        <span className={`prod-badge ${job.status}`}>{PRODUCTION_STATUS_BADGE[job.status]}</span>
      </div>

      <div className="job-meta">
        <dl>
          <dt>Asset ID</dt><dd><code>{job.id}</code></dd>
          <dt>Type</dt><dd>{ASSET_TYPE_LABELS[job.draft.type]}</dd>
          <dt>Socket</dt><dd>{job.draft.socket}</dd>
          <dt>Grip</dt><dd>{spec.model.requiredNodes.join(", ") || "—"}</dd>
          <dt>Budget</dt><dd>{job.budgetProfile} (max {spec.model.maxTriangles} tris)</dd>
          <dt>Texture</dt><dd>{spec.texture.width} × {spec.texture.height}</dd>
          <dt>Palette</dt><dd>{spec.palette.slots.join(", ") || "—"}</dd>
          <dt>Prompt Version</dt><dd>{job.promptVersion}</dd>
          <dt>Tags</dt><dd>{job.tags.join(", ") || "—"}</dd>
        </dl>
        <div className="job-status-actions">
          <label>Status を手動で進める
            <select
              value={MANUAL_STATUSES.includes(job.status) ? job.status : ""}
              onChange={(e) => e.target.value && run("status", () => setJobStatus(job, e.target.value as ProductionStatus))}
            >
              <option value="">（自動 / 現在: {PRODUCTION_STATUS_LABEL[job.status]}）</option>
              {MANUAL_STATUSES.map((s) => <option key={s} value={s}>{PRODUCTION_STATUS_LABEL[s]}</option>)}
            </select>
          </label>
          <button type="button" onClick={() => run("export", () => exportProductionPackage(job))} disabled={!!busy}>
            Export Package
          </button>
          <button
            type="button"
            className="danger"
            disabled={!!busy}
            onClick={() => {
              if (confirm(`Production Job ${job.id} を削除しますか？ Asset Library の Asset は削除されません。`)) {
                run("delete", () => deleteJob(job.id));
              }
            }}
          >
            Delete Job
          </button>
        </div>
      </div>
      {message && <p className="save-msg">{message}</p>}

      {/* ---- Import ---- */}
      <div className="job-block">
        <h3>Import AI Output</h3>
        <p className="muted">
          Asset ID は <code>{job.id}</code> に固定されます。ファイル名は自動で
          <code> model_r&lt;n&gt;.glb / texture_r&lt;n&gt;.png / source_r&lt;n&gt;.bbmodel</code> に正規化され、
          <code> asset-production/{job.id}/incoming/</code> へ保存されます。
        </p>
        <p className="muted">
          <code>.bbmodel</code> は保管と Validation の対象ですが、ブラウザでは解析しないため Preview は
          GLB を表示します（Preview が変わらないのは正常です）。Texture は GLB の UV に従って貼られます。
        </p>
        <div className="imports">
          <input ref={modelInput} type="file" accept=".glb" hidden onChange={(e) => pick("model", e.target.files?.[0])} />
          <input ref={textureInput} type="file" accept=".png" hidden onChange={(e) => pick("texture", e.target.files?.[0])} />
          <input ref={sourceInput} type="file" accept=".bbmodel" hidden onChange={(e) => pick("source", e.target.files?.[0])} />
          <button type="button" onClick={() => modelInput.current?.click()}>Model (.glb)</button>
          <button type="button" onClick={() => textureInput.current?.click()}>Texture (.png)</button>
          <button type="button" onClick={() => sourceInput.current?.click()}>Source (.bbmodel)</button>
          <ul className="import-status">
            <li>Model: {pending.model?.name ?? "—"}</li>
            <li>Texture: {pending.texture?.name ?? "—"}</li>
            <li>Source: {pending.source?.name ?? "—"}</li>
          </ul>
          <button type="button" onClick={doImport} disabled={!hasPending || !!busy}>
            {busy === "import" ? "Importing…" : "Import + Validate"}
          </button>
        </div>
      </div>

      {/* ---- Validation ---- */}
      <div className="job-block">
        <h3>AI Asset Validation</h3>
        {!revision && <p className="muted">まだ Import された Revision がありません。</p>}
        {revision && (
          <>
            <p className="val-counts">
              <span className={`verdict ${revision.validation.verdict}`}>{revision.validation.verdict.toUpperCase()}</span>
              <span>Asset Quality {revision.validation.score} / 100</span>
              <span className="err">Error {counts!.error}</span>
              <span className="warn">Warning {counts!.warning}</span>
              <span className="info">Pass {counts!.info}</span>
              <button type="button" className="mini" disabled={!!busy} onClick={() => run("revalidate", () => revalidate(job, revision.revision))}>
                Re-validate
              </button>
            </p>
            <ul className="val-list">
              {revision.validation.issues.map((issue, i) => (
                <li key={i} className={`val ${issue.level}`}>
                  <span className="val-tag">{LEVEL_MARK[issue.level]}</span>
                  <span className="val-sec">{issue.check}</span>
                  <span>{issue.message}</span>
                </li>
              ))}
            </ul>
            <p className="muted">
              Score は参考値です。Error がある場合は Score に関わらず Fail として扱い、Approve できません（spec section 40）。
            </p>
          </>
        )}
      </div>

      {/* ---- Preview ---- */}
      <div className="job-block">
        <h3>Preview</h3>
        <div className="anim-bar">
          <div className="seg">
            <button type="button" className={mode === "asset" ? "on" : ""} onClick={() => setMode("asset")}>Asset Only</button>
            <button type="button" className={mode === "base" ? "on" : ""} onClick={() => setMode("base")}>Base + Asset</button>
          </div>
          <label className="inline">Animation Test
            <select value={animIndex} disabled={mode !== "base"} onChange={(e) => setAnimIndex(Number(e.target.value))}>
              {animationRoles.map((r, i) => <option key={r} value={i}>{animationSet} · {r}</option>)}
            </select>
          </label>
          <button type="button" disabled={mode !== "base"} onClick={() => setPlaying((p) => !p)}>{playing ? "⏸ Pause" : "▶ Play"}</button>
        </div>
        {mode === "base" && anim.warnings.length > 0 && <p className="muted anim-warn">{anim.warnings.join(" / ")}</p>}
        {!modelUrl && <p className="muted">Model が無い Revision は Preview できません。</p>}
        {modelUrl && (
          <CreatorPreview
            key={`${job.id}:${revision?.revision}:${mode}:${modelUrl}`}
            assetModelUrl={modelUrl}
            assetTextureUrl={textureUrl}
            mode={mode}
            socket={job.draft.socket}
            paletteColor={job.draft.paletteSlots[0] ? DEFAULT_PALETTE[job.draft.paletteSlots[0]] : null}
            hideParts={job.draft.hideParts}
            animationClip={anim.name}
            animationPlaying={playing}
            animationSpeed={1}
            animationLoop
            referenceHair="none"
            gripAlignment={gripAlignmentFor(job.draft.type)}
            captureSignal={-1}
          />
        )}
      </div>

      {/* ---- Decision ---- */}
      <div className="job-block">
        <h3>Approve / Reject</h3>
        <div className="save-actions">
          <button
            type="button"
            disabled={!revision || !!busy || revision.validation.verdict === "fail" || !revision.files.model}
            onClick={() => revision && run("approve", async () => {
              const result = await approveRevision(job, revision.revision, index);
              setMessage(`Approve しました。Asset Library に登録: ${result.assetId}`);
            })}
          >
            Approve
          </button>
          <button
            type="button"
            disabled={!revision || !!busy}
            onClick={() => revision && run("needs", () => markNeedsRevision(job, revision.revision, { includeWarnings: true }))}
          >
            Needs Revision
          </button>
          <button
            type="button"
            className="danger"
            disabled={!revision || !!busy}
            onClick={() => revision && run("reject", () => rejectRevision(job, revision.revision, "rejected from the production queue"))}
          >
            Reject
          </button>
        </div>
        {revision?.validation.verdict === "fail" && (
          <p className="muted">Validation Error があるため Approve できません。Needs Revision で修正 Prompt を生成してください。</p>
        )}
      </div>

      {/* ---- Revision prompt ---- */}
      {revision && (
        <div className="job-block">
          <h3>Revision Prompt</h3>
          <div className="prompt-col-head">
            <span className="muted">Validation の Error / Warning から自動生成されます。</span>
            <button
              type="button"
              className="mini"
              onClick={async () => {
                try { await navigator.clipboard.writeText(revisionPrompt); setCopied(true); setTimeout(() => setCopied(false), 1500); }
                catch { setMessage("コピーできませんでした。"); }
              }}
            >
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
          <textarea readOnly rows={16} value={revisionPrompt} spellCheck={false} />
        </div>
      )}

      {/* ---- Revision history ---- */}
      <div className="job-block">
        <h3>Revision History</h3>
        {!job.revisions.length && <p className="muted">履歴はまだありません。</p>}
        {!!job.revisions.length && (
          <div className="table-scroll">
            <table>
              <thead>
                <tr><th>Revision</th><th>Result</th><th>Score</th><th>Decision</th><th>Stage</th><th>Prompt v</th><th>Created</th><th /></tr>
              </thead>
              <tbody>
                {[...job.revisions].reverse().map((r: ProductionRevision) => (
                  <tr key={r.revision} className={r.revision === revision?.revision ? "selected" : undefined}>
                    <td>Revision {r.revision}</td>
                    <td className={`verdict ${r.validation.verdict}`}>{r.validation.verdict}</td>
                    <td>{r.validation.score}</td>
                    <td>{r.decision ?? "—"}</td>
                    <td>{r.stage}</td>
                    <td>{r.promptVersion}</td>
                    <td>{r.createdAt.slice(0, 19).replace("T", " ")}</td>
                    <td><button type="button" className="mini" onClick={() => setSelected(r.revision)}>表示</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  );
}
