"use client";

import { useEffect, useRef, useState } from "react";
import type { CharacterRecipe } from "@/domain/character-recipe";
import type { AssetLibrary } from "@/features/asset-library/library";
import { isValidCharacterId } from "@/domain/character-export";
import { validateExport, countIssues, hasBlockingErrors, type ExportIssue } from "./export-validation";
import { bakeCharacter, downloadBakeResult, BAKE_STEPS, BakeError, type BakeResult, type BakeStep } from "./bake";
import { ExportedGlbPreview } from "./exported-glb-preview";

interface Props {
  recipe: CharacterRecipe;
  onId: (id: string) => void;
  name: string;
  onName: (name: string) => void;
  library: AssetLibrary;
  activeAnimationSet: string;
  thumbnailDataUrl: string | null;
}

type StepState = "pending" | "active" | "done" | "failed";

export function ExportPanel({ recipe, onId, name, onName, library, activeAnimationSet, thumbnailDataUrl }: Props) {
  const [issues, setIssues] = useState<ExportIssue[] | null>(null);
  const [running, setRunning] = useState(false);
  const [stepStates, setStepStates] = useState<Record<BakeStep, StepState>>(() => blankSteps());
  const [progressNote, setProgressNote] = useState<string>("");
  const [error, setError] = useState<{ step: string; message: string } | null>(null);
  const [result, setResult] = useState<BakeResult | null>(null);
  const resultRef = useRef<BakeResult | null>(null);

  useEffect(() => () => { if (resultRef.current) URL.revokeObjectURL(resultRef.current.glbUrl); }, []);

  const idInvalid = !!recipe.id && !isValidCharacterId(recipe.id);

  function runValidate() {
    setIssues(validateExport({ recipe, name, library, activeAnimationSet }));
  }

  async function runExport() {
    setError(null);
    setRunning(true);
    setResult(null);
    if (resultRef.current) { URL.revokeObjectURL(resultRef.current.glbUrl); resultRef.current = null; }
    setStepStates(blankSteps());
    const states = blankSteps();
    try {
      const res = await bakeCharacter({
        recipe, name, activeAnimationSet, library, thumbnailDataUrl,
        onProgress: (step, index, note) => {
          for (let i = 0; i < index; i++) states[BAKE_STEPS[i]] = "done";
          states[step] = "active";
          setStepStates({ ...states });
          setProgressNote(note ?? "");
        },
      });
      for (const s of BAKE_STEPS) states[s] = "done";
      setStepStates({ ...states });
      setIssues(res.validation);
      resultRef.current = res;
      setResult(res);
    } catch (e) {
      const be = e instanceof BakeError ? e : null;
      const failedStep = be?.step ?? "Unknown";
      states[failedStep as BakeStep] = "failed";
      setStepStates({ ...states });
      if (be?.issues.length) setIssues(be.issues);
      setError({ step: failedStep, message: e instanceof Error ? e.message : String(e) });
    } finally {
      setRunning(false);
    }
  }

  const counts = issues ? countIssues(issues) : null;
  const blocked = issues ? hasBlockingErrors(issues) : false;

  return (
    <section className="panel export-panel">
      <div className="panel-heading"><h2>Export for Godot</h2><span className="badge">BAKED CHARACTER</span></div>

      <div className="export-body">
        <div className="export-fields">
          <label>Character ID
            <input value={recipe.id} onChange={(e) => onId(e.target.value)} aria-invalid={idInvalid} spellCheck={false} />
          </label>
          <label>Character Name
            <input value={name} onChange={(e) => onName(e.target.value)} placeholder={recipe.id} />
          </label>
          {idInvalid && <p className="err export-hint">Character ID は snake_case（先頭英小文字、a-z 0-9 _）にしてください。不正文字は Export エラーになります。</p>}
          <div className="export-actions">
            <button type="button" onClick={runValidate} disabled={running}>Validate</button>
            <button type="button" onClick={runExport} disabled={running || idInvalid || blocked}>{running ? "Exporting…" : "Export for Godot"}</button>
          </div>
          {blocked && <p className="err export-hint">重大なエラーがあるため Export を停止しました。Error を解消してください（Warning のみなら Export 可能）。</p>}
        </div>

        {issues && counts && (
          <div className="export-validation">
            <p className="val-counts">
              <span className="err">Error {counts.error}</span>
              <span className="warn">Warning {counts.warning}</span>
              <span className="info">Info {counts.info}</span>
            </p>
            <ul className="val-list">
              {issues.length === 0 && <li>問題は検出されませんでした。</li>}
              {issues.map((it, i) => (
                <li key={i} className={`val ${it.level}`}>
                  <span className="val-tag">{it.level.toUpperCase()}</span>
                  <span className="val-sec">{it.section}</span>
                  <span>{it.message}</span>
                </li>
              ))}
            </ul>
          </div>
        )}

        {(running || result || error) && (
          <ol className="export-steps">
            {BAKE_STEPS.map((s) => (
              <li key={s} className={`step ${stepStates[s]}`}>
                <span className="step-mark">{stepStates[s] === "done" ? "✓" : stepStates[s] === "failed" ? "✕" : stepStates[s] === "active" ? "…" : "·"}</span>
                <span>{s}{stepStates[s] === "active" && progressNote ? ` — ${progressNote}` : ""}</span>
              </li>
            ))}
          </ol>
        )}

        {error && (
          <div className="export-error" role="alert">
            <strong>Export failed at: {error.step}</strong>
            <p>{error.message}</p>
          </div>
        )}

        {result && (
          <div className="export-result">
            <h3>Export Complete</h3>
            <dl>
              <dt>Character</dt><dd>{result.metadata.name} ({result.id})</dd>
              <dt>Model</dt><dd>{result.metadata.model}</dd>
              <dt>Texture</dt><dd>{result.metadata.texture}</dd>
              <dt>Metadata</dt><dd>{result.id}.character.json</dd>
              <dt>Active Animation Set</dt><dd>{result.metadata.activeAnimationSet}</dd>
            </dl>
            <ul className="export-files">
              {result.files.map((f) => <li key={f.name}><code>{f.name}</code> <span className="muted">{formatBytes(f.bytes)}</span></li>)}
            </ul>
            <button type="button" onClick={() => downloadBakeResult(result)}>Download ZIP</button>

            <RoundTripSummary result={result} />

            {result.sceneWarnings.length > 0 && (
              <details className="export-warnings">
                <summary>Scene 警告 {result.sceneWarnings.length} 件</summary>
                <ul>{result.sceneWarnings.map((w, i) => <li key={i}>{w}</li>)}</ul>
              </details>
            )}

            <h4>Exported GLB Preview（再Import）</h4>
            <ExportedGlbPreview url={result.glbUrl} />
          </div>
        )}
      </div>
    </section>
  );
}

function RoundTripSummary({ result }: { result: BakeResult }) {
  const rt = result.roundTrip;
  const c = countIssues(rt.issues);
  return (
    <div className="round-trip">
      <p className="val-counts">
        <strong>Round-trip:</strong>
        <span className={rt.ok ? "info" : "err"}>{rt.ok ? "PASS" : "FAIL"}</span>
        <span className="err">Error {c.error}</span>
        <span className="warn">Warning {c.warning}</span>
        <span className="muted">Mesh {rt.stats.meshCount} · Material {rt.stats.materialCount} · Texture {rt.stats.textureCount} · Anim {rt.stats.animationNames.length}</span>
        <span className="muted">BBox {rt.stats.boundingBox.size.map((v) => v.toFixed(2)).join(" × ")} m</span>
      </p>
      {rt.issues.length > 0 && (
        <ul className="val-list">
          {rt.issues.map((it, i) => (
            <li key={i} className={`val ${it.level}`}>
              <span className="val-tag">{it.level.toUpperCase()}</span>
              <span className="val-sec">{it.section}</span>
              <span>{it.message}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function blankSteps(): Record<BakeStep, StepState> {
  return Object.fromEntries(BAKE_STEPS.map((s) => [s, "pending"])) as Record<BakeStep, StepState>;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}
