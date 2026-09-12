// Phase 9 defines the AI adapter *shape* only (spec section 58). Nothing implements it yet, and
// nothing in the app depends on one existing: the Production Package is the source of truth and is
// deliberately provider-independent (spec section 57).
//
// Security (spec section 59): a future implementation must never receive an API key through the
// browser bundle. Any provider that needs credentials has to run behind a server route that reads
// them from the environment, the same way the Library API already runs server-side.
import type { ProductionJob } from "./production-job";
import type { PackageTextFile } from "./production-package";

export interface ProductionRequest {
  job: ProductionJob;
  /** The generated package, exactly as it would be exported as a ZIP. */
  files: PackageTextFile[];
  /** Revision Prompt, when asking for a fix rather than a first generation. */
  revisionPrompt?: string;
}

export interface ProductionArtifact {
  /** Suggested file name, e.g. model.glb / texture.png / source.bbmodel. */
  name: string;
  contentType: string;
  bytes: ArrayBuffer;
}

export interface ProductionResult {
  ok: boolean;
  artifacts: ProductionArtifact[];
  /** Provider-specific note surfaced in the queue; never a credential. */
  message?: string;
}

/**
 * Adapter an AI provider would implement in Phase 10+. Implementations run server-side.
 */
export interface AIProductionProvider {
  readonly id: string;
  readonly label: string;
  generateModel(request: ProductionRequest): Promise<ProductionResult>;
  generateTexture(request: ProductionRequest): Promise<ProductionResult>;
  reviseModel(request: ProductionRequest): Promise<ProductionResult>;
}

/** No provider is registered in Phase 9; the UI stays fully manual. */
export const PRODUCTION_PROVIDERS: readonly AIProductionProvider[] = [];
