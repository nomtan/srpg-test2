// Phase 9 AI Production record. One job = one asset being produced with AI assistance.
//
// The job is the durable side of the flow: Asset Definition -> Production Package -> (external AI)
// -> Import -> Validation -> Approve -> Asset Library. It is stored per asset under
// library-data/asset-production/<id>/ together with its incoming / approved / rejected staging
// files (spec section 36) so a revision history survives a reload (spec section 48).
import type { AssetDraft } from "./asset-spec";
import { emptyDraft } from "./asset-spec";
import type { BudgetProfile, AlphaPolicy } from "./production-profile";
import { TYPE_ALPHA_POLICY, TYPE_BUDGET } from "./production-profile";
import type { ProductionStatus } from "./production-status";
import { PRODUCTION_STATUSES } from "./production-status";

/**
 * Prompt Template version (spec section 50). Bump when a template's content changes.
 * 1: initial Phase 9 templates.
 * 2: `.bbmodel` source made a required deliverable, plus the fixed delivery folder structure
 *    (`<id>/source/<id>.bbmodel`, `model.glb`, `texture.png`, `asset.json`) and a verbatim
 *    asset.json block.
 * 3: corrected handedness (the character's left is -Z, not +Z) and the grip rotation the
 *    Character Builder applies at the hand sockets.
 * 4: the Model Prompt states a target asset size, not just the body region it fits. Shoulder
 *    pauldrons carry a 1.5x coverage factor after 1x output read as too small.
 * 5: REFERENCE INFORMATION states how to work from an attached whole-character illustration —
 *    which part to crop to, what to take from it, and what the document still overrides.
 * 6: STYLE quotes the measured head proportion instead of a fixed "2.5-3 heads" band, which had
 *    started contradicting the measurements shipped in the same prompt.
 * 7: sockets are calibrated to their body region instead of sitting on the parent group's rotation
 *    pivot, so the quoted socket position is the real attachment point.
 */
export const PROMPT_VERSION = 7;
export const PRODUCTION_SPEC_VERSION = 1;

export const REFERENCE_ROLES = ["shape", "style", "color", "concept"] as const;
export type ReferenceRole = typeof REFERENCE_ROLES[number];

export const REFERENCE_ROLE_LABEL: Record<ReferenceRole, string> = {
  shape: "Shape Reference",
  style: "Style Reference",
  color: "Color Reference",
  concept: "Concept",
};

/** `full_body` marks whole-character art: the prompt tells the agent which part to crop to. */
export const REFERENCE_VIEWS = ["full_body", "front", "back", "side", "three_quarter", "concept", "other"] as const;
export type ReferenceView = typeof REFERENCE_VIEWS[number];

export interface ProductionReference {
  id: string;
  /** File name inside the job's reference/ staging folder; null for a note-only reference. */
  file: string | null;
  role: ReferenceRole;
  view: ReferenceView;
  note: string;
}

export type ProductionIssueLevel = "error" | "warning" | "info";

export interface ProductionIssue {
  level: ProductionIssueLevel;
  /** Stable machine code; revision prompts are generated from this (spec section 47). */
  code: string;
  check: string;
  message: string;
  /** Extra numbers for the revision prompt, e.g. { actual: 1.8, expected: 1 }. */
  detail?: Record<string, string | number>;
}

export type ProductionVerdict = "pass" | "warning" | "fail" | "unknown";

export interface ProductionValidation {
  verdict: ProductionVerdict;
  /** Advisory 0-100 quality score (spec section 40). An error always means fail regardless. */
  score: number;
  checkedAt: string | null;
  issues: ProductionIssue[];
}

export function unknownProductionValidation(): ProductionValidation {
  return { verdict: "unknown", score: 0, checkedAt: null, issues: [] };
}

export interface ProductionFiles {
  /** File names inside the staging folder of the revision's stage. */
  model: string | null;
  texture: string | null;
  /** Editable Blockbench source, kept as-is and never parsed in the browser (spec section 37). */
  source: string | null;
}

export const emptyProductionFiles = (): ProductionFiles => ({ model: null, texture: null, source: null });

export type ProductionStage = "incoming" | "approved" | "rejected" | "reference";

export interface ProductionRevision {
  revision: number;
  createdAt: string;
  stage: ProductionStage;
  files: ProductionFiles;
  validation: ProductionValidation;
  /** approve / reject / needs_revision decision, once taken (spec section 45). */
  decision: "approved" | "rejected" | "needs_revision" | null;
  decidedAt: string | null;
  /** Revision Prompt generated from this revision's validation errors (spec section 46). */
  revisionPrompt: string | null;
  note: string;
  promptVersion: number;
}

export interface ProductionJob {
  kind: "production";
  specVersion: typeof PRODUCTION_SPEC_VERSION;
  /** Same id as the asset it produces; no second identifier to keep in sync (spec section 38). */
  id: string;
  name: string;
  status: ProductionStatus;
  /** The Asset Definition captured from the Asset Creator. */
  draft: AssetDraft;
  budgetProfile: BudgetProfile;
  alphaPolicy: AlphaPolicy;
  /** Asset tags carried into the Asset Library on approve; feeds the Phase 8 generator. */
  tags: string[];
  references: ProductionReference[];
  revisions: ProductionRevision[];
  promptVersion: number;
  packageGeneratedAt: string | null;
  /** Free-text note shown in the queue. */
  note: string;
  createdAt: string;
  updatedAt: string;
}

export function newProductionJob(draft: AssetDraft, tags: string[] = []): ProductionJob {
  const now = new Date().toISOString();
  return {
    kind: "production",
    specVersion: PRODUCTION_SPEC_VERSION,
    id: draft.id,
    name: draft.name || draft.id,
    status: "draft",
    draft: { ...draft },
    budgetProfile: TYPE_BUDGET[draft.type],
    alphaPolicy: TYPE_ALPHA_POLICY[draft.type],
    tags: [...tags],
    references: [],
    revisions: [],
    promptVersion: PROMPT_VERSION,
    packageGeneratedAt: null,
    note: "",
    createdAt: now,
    updatedAt: now,
  };
}

export const latestRevision = (job: ProductionJob): ProductionRevision | null =>
  job.revisions.length ? job.revisions[job.revisions.length - 1] : null;

export const nextRevisionNumber = (job: ProductionJob): number =>
  job.revisions.reduce((max, r) => Math.max(max, r.revision), 0) + 1;

/** The revision whose files were approved, if any. */
export const approvedRevision = (job: ProductionJob): ProductionRevision | null =>
  [...job.revisions].reverse().find((r) => r.decision === "approved") ?? null;

/** Production block written onto the asset metadata on approve (spec section 49). */
export interface AssetProductionMeta {
  method: "ai_assisted";
  revision: number;
  status: "approved";
  promptVersion: number;
  producedAt: string;
}

// ---- tolerant parse -------------------------------------------------------------------
// Jobs are plain JSON on disk and may be hand-edited; unknown shapes fall back to defaults
// instead of breaking the queue.

const str = (v: unknown, fallback = "") => (typeof v === "string" ? v : fallback);
const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? v : fallback);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

function parseFiles(input: unknown): ProductionFiles {
  const f = (input ?? {}) as Record<string, unknown>;
  return {
    model: typeof f.model === "string" ? f.model : null,
    texture: typeof f.texture === "string" ? f.texture : null,
    source: typeof f.source === "string" ? f.source : null,
  };
}

function parseValidation(input: unknown): ProductionValidation {
  const v = (input ?? {}) as Record<string, unknown>;
  const verdict = ["pass", "warning", "fail", "unknown"].includes(str(v.verdict))
    ? (v.verdict as ProductionVerdict)
    : "unknown";
  return {
    verdict,
    score: Math.max(0, Math.min(100, Math.round(num(v.score, 0)))),
    checkedAt: typeof v.checkedAt === "string" ? v.checkedAt : null,
    issues: arr(v.issues).map((raw) => {
      const i = raw as Record<string, unknown>;
      return {
        level: (["error", "warning", "info"].includes(str(i.level)) ? i.level : "info") as ProductionIssueLevel,
        code: str(i.code, "unknown"),
        check: str(i.check, "unknown"),
        message: str(i.message),
        ...(i.detail && typeof i.detail === "object" ? { detail: i.detail as Record<string, string | number> } : {}),
      };
    }),
  };
}

export function parseProductionJob(input: unknown): ProductionJob {
  const j = (input ?? {}) as Record<string, unknown>;
  const draft = { ...emptyDraft(), ...(j.draft && typeof j.draft === "object" ? (j.draft as AssetDraft) : {}) };
  const base = newProductionJob(draft, arr(j.tags).filter((t): t is string => typeof t === "string"));
  const status = PRODUCTION_STATUSES.includes(str(j.status) as ProductionStatus)
    ? (j.status as ProductionStatus)
    : "draft";
  return {
    ...base,
    id: str(j.id, draft.id),
    name: str(j.name, draft.name || draft.id),
    status,
    budgetProfile: (["low", "medium", "high"].includes(str(j.budgetProfile)) ? j.budgetProfile : base.budgetProfile) as BudgetProfile,
    alphaPolicy: (["alpha_required", "alpha_allowed", "alpha_forbidden"].includes(str(j.alphaPolicy)) ? j.alphaPolicy : base.alphaPolicy) as AlphaPolicy,
    references: arr(j.references).map((raw, i) => {
      const r = raw as Record<string, unknown>;
      return {
        id: str(r.id, `ref_${i + 1}`),
        file: typeof r.file === "string" ? r.file : null,
        role: (REFERENCE_ROLES.includes(str(r.role) as ReferenceRole) ? r.role : "shape") as ReferenceRole,
        view: (REFERENCE_VIEWS.includes(str(r.view) as ReferenceView) ? r.view : "other") as ReferenceView,
        note: str(r.note),
      };
    }),
    revisions: arr(j.revisions).map((raw, i) => {
      const r = raw as Record<string, unknown>;
      const decision = ["approved", "rejected", "needs_revision"].includes(str(r.decision))
        ? (r.decision as ProductionRevision["decision"])
        : null;
      return {
        revision: Math.floor(num(r.revision, i + 1)),
        createdAt: str(r.createdAt, base.createdAt),
        stage: (["incoming", "approved", "rejected", "reference"].includes(str(r.stage)) ? r.stage : "incoming") as ProductionStage,
        files: parseFiles(r.files),
        validation: parseValidation(r.validation),
        decision,
        decidedAt: typeof r.decidedAt === "string" ? r.decidedAt : null,
        revisionPrompt: typeof r.revisionPrompt === "string" ? r.revisionPrompt : null,
        note: str(r.note),
        promptVersion: Math.floor(num(r.promptVersion, PROMPT_VERSION)),
      };
    }),
    promptVersion: Math.floor(num(j.promptVersion, PROMPT_VERSION)),
    packageGeneratedAt: typeof j.packageGeneratedAt === "string" ? j.packageGeneratedAt : null,
    note: str(j.note),
    createdAt: str(j.createdAt, base.createdAt),
    updatedAt: str(j.updatedAt, base.updatedAt),
  };
}
