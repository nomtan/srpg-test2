// Phase 9 production state machine (spec section 3 / 45 / 55).
//
// Phase 9 deliberately does NOT talk to an AI provider, so every transition is either performed
// by the tool (import, validation, approve) or driven by hand from the queue. The states that a
// user must be able to step through manually are prompt_ready / generated / imported.

export const PRODUCTION_STATUSES = [
  "draft",
  "prompt_ready",
  "generating",
  "generated",
  "imported",
  "validation_error",
  "needs_revision",
  "ready",
  "rejected",
  "registered",
] as const;
export type ProductionStatus = typeof PRODUCTION_STATUSES[number];

export const PRODUCTION_STATUS_LABEL: Record<ProductionStatus, string> = {
  draft: "Draft",
  prompt_ready: "Prompt Ready",
  generating: "Generating",
  generated: "Generated",
  imported: "Imported",
  validation_error: "Validation Error",
  needs_revision: "Needs Revision",
  ready: "Approved",
  rejected: "Rejected",
  registered: "Registered",
};

export const PRODUCTION_STATUS_BADGE: Record<ProductionStatus, string> = {
  draft: "· Draft",
  prompt_ready: "▸ Prompt Ready",
  generating: "◌ Generating",
  generated: "◆ Generated",
  imported: "▣ Imported",
  validation_error: "✕ Validation Error",
  needs_revision: "⟲ Needs Revision",
  ready: "✓ Approved",
  rejected: "✕ Rejected",
  registered: "★ Registered",
};

/** Statuses a user may set by hand from the queue, no AI integration required (spec section 3). */
export const MANUAL_STATUSES: readonly ProductionStatus[] = [
  "draft",
  "prompt_ready",
  "generating",
  "generated",
  "imported",
];

/** Queue filter buckets (spec section 55). */
export const QUEUE_FILTERS = [
  "all",
  "draft",
  "prompt_ready",
  "generated",
  "needs_revision",
  "approved",
  "rejected",
] as const;
export type QueueFilter = typeof QUEUE_FILTERS[number];

export const QUEUE_FILTER_LABEL: Record<QueueFilter, string> = {
  all: "All",
  draft: "Draft",
  prompt_ready: "Prompt Ready",
  generated: "Generated",
  needs_revision: "Needs Revision",
  approved: "Approved",
  rejected: "Rejected",
};

const FILTER_STATUSES: Record<QueueFilter, readonly ProductionStatus[]> = {
  all: PRODUCTION_STATUSES,
  draft: ["draft"],
  prompt_ready: ["prompt_ready", "generating"],
  generated: ["generated", "imported", "validation_error"],
  needs_revision: ["needs_revision"],
  approved: ["ready", "registered"],
  rejected: ["rejected"],
};

export const matchesQueueFilter = (status: ProductionStatus, filter: QueueFilter) =>
  FILTER_STATUSES[filter].includes(status);

export const isApproved = (status: ProductionStatus) => status === "ready" || status === "registered";
