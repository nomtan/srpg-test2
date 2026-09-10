"use client";

import {
  EXPORT_STATUS_LABEL, REGISTRY_STATUS_LABEL, VALIDATION_BADGE,
  type CharacterExportStatus, type RegistryStatus, type ValidationStatus,
} from "@/domain/library-index";

export function ValidationBadge({ status }: { status: ValidationStatus }) {
  return <span className={`lib-badge v-${status}`}>{VALIDATION_BADGE[status]}</span>;
}

export function ExportBadge({ status }: { status: CharacterExportStatus }) {
  return <span className={`lib-badge x-${status}`}>{EXPORT_STATUS_LABEL[status]}</span>;
}

export function RegistryBadge({ status }: { status: RegistryStatus }) {
  return <span className={`lib-badge r-${status}`}>{REGISTRY_STATUS_LABEL[status]}</span>;
}

/** Thumbnail from a stored PNG only — never loads a GLB (spec prompt 49). */
export function LibThumb({ src, symbol, label }: { src: string | null; symbol: string; label: string }) {
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img className="lib-thumb" src={src} alt={label} width={56} height={56} loading="lazy" />
  ) : (
    <span className="lib-thumb lib-thumb-fallback" aria-hidden="true">{symbol}</span>
  );
}
