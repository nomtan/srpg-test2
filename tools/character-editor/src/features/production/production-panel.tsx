"use client";

// Phase 9 AI Production panel, embedded in the Asset Creator (spec section 2).
import Link from "next/link";
import { useState } from "react";
import type { AssetDraft } from "@/domain/asset-spec";
import { isSnakeCase } from "@/domain/asset-spec";
import {
  ALPHA_POLICIES, ALPHA_POLICY_LABEL, BUDGET_DEFINITION, BUDGET_PROFILES, TYPE_ALPHA_POLICY,
  TYPE_BUDGET, type AlphaPolicy, type BudgetProfile,
} from "@/domain/production-profile";
import { buildProductionPackage, packageDirName } from "@/domain/production-package";
import {
  PROMPT_VERSION, REFERENCE_ROLES, REFERENCE_ROLE_LABEL, REFERENCE_VIEWS, newProductionJob,
  type ProductionJob, type ReferenceRole, type ReferenceView,
} from "@/domain/production-job";
import { PRODUCTION_STATUS_BADGE } from "@/domain/production-status";
import { useLibraryIndex } from "@/features/library/use-library-index";
import { addReference, removeReference, upsertJobFromDraft } from "./mutations";
import { exportProductionPackage } from "./package-export";

const PREVIEWS = [
  { key: "model-prompt.md", label: "Model Prompt" },
  { key: "texture-prompt.md", label: "Texture Prompt" },
  { key: "technical-spec.md", label: "Technical Spec" },
  { key: "validation-spec.json", label: "Validation Requirements" },
  { key: "asset-definition.json", label: "Asset Definition" },
  { key: "README.md", label: "README" },
] as const;

export function ProductionPanel({ draft }: { draft: AssetDraft }) {
  const { index, refresh } = useLibraryIndex();
  const stored = index.productions.find((j) => j.id === draft.id) ?? null;

  const [budgetProfile, setBudgetProfile] = useState<BudgetProfile | null>(null);
  const [alphaPolicy, setAlphaPolicy] = useState<AlphaPolicy | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [refRole, setRefRole] = useState<ReferenceRole>("shape");
  // Whole-character concept art is the common case, so it is the default view.
  const [refView, setRefView] = useState<ReferenceView>("full_body");
  const [refNote, setRefNote] = useState("");

  const effectiveBudget = budgetProfile ?? stored?.budgetProfile ?? TYPE_BUDGET[draft.type];
  const effectiveAlpha = alphaPolicy ?? stored?.alphaPolicy ?? TYPE_ALPHA_POLICY[draft.type];
  const tags = stored?.tags ?? [];

  /** Preview job: the saved job if there is one, otherwise a throwaway built from the draft. */
  const previewJob: ProductionJob = {
    ...(stored ?? newProductionJob(draft)),
    draft: { ...draft },
    name: draft.name || draft.id,
    budgetProfile: effectiveBudget,
    alphaPolicy: effectiveAlpha,
    promptVersion: PROMPT_VERSION,
  };

  const files = buildProductionPackage(previewJob);
  const fileByName = new Map(files.map((f) => [f.name, f.content]));
  const idValid = !!draft.id && isSnakeCase(draft.id);

  async function generate() {
    if (!idValid) { setMessage("ID が未入力か snake_case ではありません。"); return; }
    setBusy(true);
    try {
      await upsertJobFromDraft(draft, index, { budgetProfile: effectiveBudget, alphaPolicy: effectiveAlpha });
      await refresh();
      setMessage(`Production Package を生成しました: ${packageDirName(previewJob)}/`);
      setOpen((current) => current ?? "model-prompt.md");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function copyAll() {
    const text = files.map((f) => `===== ${f.name} =====\n\n${f.content}`).join("\n\n");
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setMessage("クリップボードにコピーできませんでした。");
    }
  }

  async function exportZip() {
    setBusy(true);
    try {
      await exportProductionPackage(previewJob);
    } finally {
      setBusy(false);
    }
  }

  async function addTag() {
    const tag = tagInput.trim().toLowerCase();
    if (!tag || !stored) return;
    setTagInput("");
    await upsertJobFromDraft(draft, index, {
      budgetProfile: effectiveBudget,
      alphaPolicy: effectiveAlpha,
      tags: [...new Set([...tags, tag])].sort(),
    });
    await refresh();
  }

  async function onReference(file: File | undefined) {
    if (!file || !stored) return;
    setBusy(true);
    try {
      await addReference(stored, file, refRole, refView, refNote.trim());
      setRefNote("");
      await refresh();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="panel production-panel">
      <div className="panel-heading">
        <h2>AI Production</h2>
        <Link className="mini-link" href="/production">Production Queue →</Link>
      </div>

      <div className="production-head">
        <dl>
          <dt>Asset</dt>
          <dd>{draft.name || "(unnamed)"} <code>{draft.id || "(no id)"}</code></dd>
          <dt>Status</dt>
          <dd>{PRODUCTION_STATUS_BADGE[stored?.status ?? "draft"]}</dd>
          <dt>Prompt Version</dt>
          <dd>{previewJob.promptVersion}</dd>
          <dt>Revisions</dt>
          <dd>{stored?.revisions.length ?? 0}</dd>
        </dl>
        <div className="production-settings">
          <label>Geometry Budget
            <select value={effectiveBudget} onChange={(e) => setBudgetProfile(e.target.value as BudgetProfile)}>
              {BUDGET_PROFILES.map((p) => (
                <option key={p} value={p}>{p} · ~{BUDGET_DEFINITION[p].targetTriangles} tris (max {BUDGET_DEFINITION[p].maxTriangles})</option>
              ))}
            </select>
          </label>
          <label>Transparency
            <select value={effectiveAlpha} onChange={(e) => setAlphaPolicy(e.target.value as AlphaPolicy)}>
              {ALPHA_POLICIES.map((p) => <option key={p} value={p}>{ALPHA_POLICY_LABEL[p]}</option>)}
            </select>
          </label>
        </div>
      </div>

      <div className="production-actions">
        <button type="button" onClick={generate} disabled={busy || !idValid}>Generate Production Package</button>
        <button type="button" onClick={copyAll} disabled={busy}>{copied ? "Copied" : "Copy All"}</button>
        <button type="button" onClick={exportZip} disabled={busy}>Export Package (.zip)</button>
      </div>
      {!idValid && <p className="muted production-note">ID を snake_case で入力すると Production Package を保存できます。</p>}
      {message && <p className="save-msg">{message}</p>}

      <div className="production-previews">
        {PREVIEWS.map(({ key, label }) => (
          <div key={key} className="production-preview">
            <div className="production-preview-head">
              <strong>{label}</strong>
              <button type="button" className="mini" onClick={() => setOpen(open === key ? null : key)}>
                {open === key ? "Hide" : "Preview"}
              </button>
            </div>
            {open === key && (
              <textarea readOnly rows={18} value={fileByName.get(key) ?? ""} spellCheck={false} />
            )}
          </div>
        ))}
      </div>

      <div className="production-references">
        <h3>Reference Information</h3>
        {!stored && <p className="muted">Generate Production Package 後に Reference を登録できます。</p>}
        {stored && (
          <>
            <div className="reference-form">
              <label>Role
                <select value={refRole} onChange={(e) => setRefRole(e.target.value as ReferenceRole)}>
                  {REFERENCE_ROLES.map((r) => <option key={r} value={r}>{REFERENCE_ROLE_LABEL[r]}</option>)}
                </select>
              </label>
              <label>View
                <select value={refView} onChange={(e) => setRefView(e.target.value as ReferenceView)}>
                  {REFERENCE_VIEWS.map((v) => <option key={v} value={v}>{v}</option>)}
                </select>
              </label>
              <label>Note
                <input value={refNote} onChange={(e) => setRefNote(e.target.value)} placeholder="任意のメモ" />
              </label>
              <label className="file-label">Image
                <input type="file" accept="image/png,image/jpeg,image/webp" onChange={(e) => { onReference(e.target.files?.[0]); e.target.value = ""; }} />
              </label>
            </div>
            <ul className="reference-list">
              {stored.references.length === 0 && <li className="muted">未登録</li>}
              {stored.references.map((ref) => (
                <li key={ref.id}>
                  <span className="ref-role">{REFERENCE_ROLE_LABEL[ref.role]}</span>
                  <span className="ref-view">{ref.view}</span>
                  <code>{ref.file ?? "(note)"}</code>
                  {ref.note && <em>{ref.note}</em>}
                  <button type="button" className="mini" onClick={async () => { await removeReference(stored, ref.id); await refresh(); }}>削除</button>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>

      <div className="production-tags">
        <h3>Asset Tags</h3>
        <p className="muted">Approve 後、この Tag が Asset Library に引き継がれ、Variation Generator の候補条件に使われます。</p>
        <div className="tag-row">
          {tags.map((tag) => <span key={tag} className="tag-chip">{tag}</span>)}
          {!tags.length && <span className="muted">未設定</span>}
        </div>
        <div className="tag-input">
          <input
            value={tagInput}
            disabled={!stored}
            placeholder={stored ? "例: kingdom" : "Package 生成後に入力できます"}
            onChange={(e) => setTagInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void addTag(); } }}
          />
          <button type="button" className="mini" disabled={!stored || !tagInput.trim()} onClick={addTag}>Add Tag</button>
        </div>
      </div>

      <p className="muted production-note">
        Phase 9 は特定の AI API へ送信しません。Production Package が Provider 非依存の Source of Truth です
        （<code>{packageDirName(previewJob)}/</code>）。生成物の Import・Validation・Approve は Production Queue で行います。
      </p>
    </section>
  );
}
