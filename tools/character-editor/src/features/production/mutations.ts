"use client";

// Phase 9 production operations. The queue screen and the Asset Creator panel both go through
// here, then call refreshLibrary() so the rest of the app sees the new state.
import type { AssetDraft } from "@/domain/asset-spec";
import { draftToAssetJson } from "@/domain/asset-spec";
import type { LibraryIndex } from "@/domain/library-index";
import {
  newProductionJob, nextRevisionNumber, unknownProductionValidation,
  type ProductionJob, type ProductionRevision, type ProductionStage,
} from "@/domain/production-job";
import { TYPE_ALPHA_POLICY, TYPE_BUDGET } from "@/domain/production-profile";
import { buildValidationSpec } from "@/domain/production-package";
import { validateProduction } from "@/domain/production-validation";
import { buildRevisionPrompt } from "@/domain/production-revision";
import type { ProductionStatus } from "@/domain/production-status";
import { inspectGlb, inspectImage } from "@/features/asset-creator/inspect";
import {
  deleteProductionFile, deleteProductionJob, moveProductionFile, productionFileUrl,
  putProductionFile, putProductionJob,
} from "@/features/library/api";
import { patchAsset, saveAsset } from "@/features/library/mutations";

const now = () => new Date().toISOString();

export async function persistJob(job: ProductionJob): Promise<ProductionJob> {
  const next: ProductionJob = { ...job, updatedAt: now() };
  await putProductionJob(next);
  return next;
}

/** Create the job on first "Generate Production Package", or refresh its Asset Definition. */
export async function upsertJobFromDraft(
  draft: AssetDraft,
  index: LibraryIndex,
  patch: Partial<Pick<ProductionJob, "budgetProfile" | "alphaPolicy" | "tags" | "note">> = {},
): Promise<ProductionJob> {
  const existing = index.productions.find((j) => j.id === draft.id);
  const base = existing
    ? { ...existing, draft: { ...draft }, name: draft.name || draft.id }
    : newProductionJob(draft, patch.tags ?? []);
  const job: ProductionJob = {
    ...base,
    budgetProfile: patch.budgetProfile ?? base.budgetProfile ?? TYPE_BUDGET[draft.type],
    alphaPolicy: patch.alphaPolicy ?? base.alphaPolicy ?? TYPE_ALPHA_POLICY[draft.type],
    tags: patch.tags ?? base.tags,
    note: patch.note ?? base.note,
    packageGeneratedAt: now(),
    // Keep a manually advanced status; only a fresh draft moves up to prompt_ready.
    status: base.status === "draft" ? "prompt_ready" : base.status,
  };
  return persistJob(job);
}

export async function deleteJob(id: string): Promise<void> {
  await deleteProductionJob(id);
}

export async function setJobStatus(job: ProductionJob, status: ProductionStatus): Promise<ProductionJob> {
  return persistJob({ ...job, status });
}

export async function patchJob(job: ProductionJob, patch: Partial<ProductionJob>): Promise<ProductionJob> {
  return persistJob({ ...job, ...patch });
}

// ---- Reference images (spec section 24-25) ------------------------------------------

export async function addReference(
  job: ProductionJob,
  file: File,
  role: ProductionJob["references"][number]["role"],
  view: ProductionJob["references"][number]["view"],
  note: string,
): Promise<ProductionJob> {
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, "_");
  await putProductionFile(job.id, "reference", safeName, file);
  const references = [
    ...job.references.filter((r) => r.file !== safeName),
    { id: `ref_${job.references.length + 1}_${Date.now()}`, file: safeName, role, view, note },
  ];
  return persistJob({ ...job, references });
}

export async function removeReference(job: ProductionJob, id: string): Promise<ProductionJob> {
  const target = job.references.find((r) => r.id === id);
  if (target?.file) await deleteProductionFile(job.id, "reference", target.file).catch(() => {});
  return persistJob({ ...job, references: job.references.filter((r) => r.id !== id) });
}

// ---- Import + Validation (spec section 37-39) ----------------------------------------

export interface DeliveryFiles {
  model?: File | null;
  texture?: File | null;
  source?: File | null;
}

/**
 * Import one AI delivery: the files land in incoming/, a new revision is opened, and Validation
 * runs immediately (spec section 39). The asset id is taken from the job, never re-typed by the
 * user (spec section 38).
 */
export async function importDelivery(job: ProductionJob, files: DeliveryFiles): Promise<ProductionJob> {
  const stage: ProductionStage = "incoming";
  const revision = nextRevisionNumber(job);
  const stored = { model: null as string | null, texture: null as string | null, source: null as string | null };

  if (files.model) {
    stored.model = `model_r${revision}.glb`;
    await putProductionFile(job.id, stage, stored.model, files.model);
  }
  if (files.texture) {
    stored.texture = `texture_r${revision}.png`;
    await putProductionFile(job.id, stage, stored.texture, files.texture);
  }
  if (files.source) {
    stored.source = `source_r${revision}.bbmodel`;
    await putProductionFile(job.id, stage, stored.source, files.source);
  }

  const validation = await runValidation(job, stored, stage);
  const entry: ProductionRevision = {
    revision,
    createdAt: now(),
    stage,
    files: stored,
    validation,
    decision: null,
    decidedAt: null,
    revisionPrompt: null,
    note: "",
    promptVersion: job.promptVersion,
  };
  const next: ProductionJob = {
    ...job,
    revisions: [...job.revisions, entry],
    status: validation.verdict === "fail" ? "validation_error" : "imported",
  };
  return persistJob(next);
}

/** Re-run Validation against the files already stored for a revision. */
export async function revalidate(job: ProductionJob, revision: number): Promise<ProductionJob> {
  const target = job.revisions.find((r) => r.revision === revision);
  if (!target) return job;
  const validation = await runValidation(job, target.files, target.stage);
  const revisions = job.revisions.map((r) => (r.revision === revision ? { ...r, validation } : r));
  const isLatest = revision === job.revisions[job.revisions.length - 1]?.revision;
  return persistJob({
    ...job,
    revisions,
    status: isLatest ? (validation.verdict === "fail" ? "validation_error" : "imported") : job.status,
  });
}

async function runValidation(
  job: ProductionJob,
  files: { model: string | null; texture: string | null; source: string | null },
  stage: ProductionStage,
) {
  const spec = buildValidationSpec(job);
  const model = files.model
    ? await inspectGlb(productionFileUrl(job.id, stage, files.model)).catch(() => null)
    : null;
  const texture = files.texture
    ? await inspectImage(productionFileUrl(job.id, stage, files.texture)).catch(() => null)
    : null;
  return validateProduction(spec, { model, texture, sourceFileName: files.source });
}

// ---- Approve / Reject / Needs Revision (spec section 45-46) --------------------------

async function moveRevisionFiles(job: ProductionJob, rev: ProductionRevision, to: ProductionStage) {
  for (const name of [rev.files.model, rev.files.texture, rev.files.source]) {
    if (name) await moveProductionFile(job.id, rev.stage, to, name).catch(() => {});
  }
}

export interface ApproveResult {
  job: ProductionJob;
  assetId: string;
}

/**
 * Approve a revision: promote its files to approved/, then register the asset in the Phase 7
 * Asset Library so the Character Builder and the Phase 8 Variation Generator can use it
 * (spec section 52-53). Only approved assets reach the Library (spec section 45).
 */
export async function approveRevision(
  job: ProductionJob,
  revision: number,
  index: LibraryIndex,
): Promise<ApproveResult> {
  const target = job.revisions.find((r) => r.revision === revision);
  if (!target) throw new Error(`Revision ${revision} が見つかりません。`);
  if (target.validation.verdict === "fail") {
    throw new Error("Validation Error がある Revision は Approve できません。");
  }
  if (!target.files.model) throw new Error("Model (.glb) が無い Revision は Approve できません。");

  await moveRevisionFiles(job, target, "approved");
  const files = { ...target.files };

  const fetchBlob = async (name: string | null) => {
    if (!name) return null;
    const res = await fetch(productionFileUrl(job.id, "approved", name), { cache: "no-store" });
    return res.ok ? await res.blob() : null;
  };
  const [modelBlob, textureBlob] = await Promise.all([fetchBlob(files.model), fetchBlob(files.texture)]);

  const metadata = draftToAssetJson({ ...job.draft, sourceFileName: files.source ?? job.draft.sourceFileName });
  metadata.description = job.draft.description || undefined;
  metadata.tags = [...job.tags];
  metadata.production = {
    method: "ai_assisted",
    revision: target.revision,
    status: "approved",
    promptVersion: target.promptVersion,
    producedAt: now(),
  };

  const existing = index.assets.find((a) => a.metadata.id === job.id) ?? null;
  const record = await saveAsset({
    metadata,
    modelBlob,
    textureBlob,
    existing,
    origin: existing ? existing.origin : "creator",
    versionNote: `AI production revision ${target.revision}`,
  });
  if (job.tags.length) {
    // saveAsset keeps the existing record tags; make sure the production tags are on the record
    // itself too, because the Phase 8 candidate pool reads record.tags.
    const merged = [...new Set([...record.tags, ...job.tags])].sort();
    if (merged.join("|") !== record.tags.join("|")) await patchAsset(record, { tags: merged });
  }

  const revisions = job.revisions.map((r) =>
    r.revision === revision
      ? { ...r, stage: "approved" as ProductionStage, files, decision: "approved" as const, decidedAt: now(), revisionPrompt: null }
      : r,
  );
  const next = await persistJob({ ...job, revisions, status: "registered" });
  return { job: next, assetId: record.metadata.id };
}

export async function rejectRevision(job: ProductionJob, revision: number, note: string): Promise<ProductionJob> {
  const target = job.revisions.find((r) => r.revision === revision);
  if (!target) return job;
  await moveRevisionFiles(job, target, "rejected");
  const revisions = job.revisions.map((r) =>
    r.revision === revision
      ? { ...r, stage: "rejected" as ProductionStage, decision: "rejected" as const, decidedAt: now(), note }
      : r,
  );
  return persistJob({ ...job, revisions, status: "rejected" });
}

/** Needs Revision keeps the files in incoming/ and attaches a generated Revision Prompt. */
export async function markNeedsRevision(
  job: ProductionJob,
  revision: number,
  opts: { includeWarnings?: boolean; note?: string } = {},
): Promise<ProductionJob> {
  const target = job.revisions.find((r) => r.revision === revision);
  if (!target) return job;
  const revisionPrompt = buildRevisionPrompt({
    job,
    spec: buildValidationSpec(job),
    validation: target.validation,
    includeWarnings: opts.includeWarnings ?? true,
  });
  const revisions = job.revisions.map((r) =>
    r.revision === revision
      ? { ...r, decision: "needs_revision" as const, decidedAt: now(), revisionPrompt, note: opts.note ?? r.note }
      : r,
  );
  return persistJob({ ...job, revisions, status: "needs_revision" });
}

/** Reset a job that has no delivery yet (used when the Asset Definition changes materially). */
export function freshValidation() {
  return unknownProductionValidation();
}
