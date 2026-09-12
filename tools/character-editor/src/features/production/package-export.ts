"use client";

// Phase 9 Production Package export (spec section 4, 56). Reuses the Phase 4 store-only ZIP
// writer; a batch export is the same package layout repeated under one archive.
import { buildProductionPackage, packageDirName } from "@/domain/production-package";
import type { ProductionJob } from "@/domain/production-job";
import { createZip, downloadBlob, type ZipEntry } from "@/features/asset-creator/zip";
import { productionFileUrl } from "@/features/library/api";

const encoder = new TextEncoder();

async function referenceEntries(job: ProductionJob, prefix: string): Promise<ZipEntry[]> {
  const entries: ZipEntry[] = [];
  for (const ref of job.references) {
    if (!ref.file) continue;
    try {
      const res = await fetch(productionFileUrl(job.id, "reference", ref.file), { cache: "no-store" });
      if (!res.ok) continue;
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length) entries.push({ name: `${prefix}reference/${ref.file}`, data: bytes });
    } catch {
      // A missing reference image must not block the package export.
    }
  }
  return entries;
}

export async function packageEntries(job: ProductionJob, prefix = ""): Promise<ZipEntry[]> {
  const text = buildProductionPackage(job).map((file) => ({
    name: `${prefix}${file.name}`,
    data: encoder.encode(file.content),
  }));
  return [...text, ...(await referenceEntries(job, prefix))];
}

export async function exportProductionPackage(job: ProductionJob): Promise<void> {
  const entries = await packageEntries(job, `${packageDirName(job)}/`);
  downloadBlob(createZip(entries), `${packageDirName(job)}.zip`);
}

/** Spec section 56: several assets in one archive, one directory per asset. */
export async function exportProductionPackages(jobs: readonly ProductionJob[]): Promise<void> {
  if (jobs.length === 1) return exportProductionPackage(jobs[0]);
  const entries: ZipEntry[] = [];
  for (const job of jobs) entries.push(...(await packageEntries(job, `${packageDirName(job)}/`)));
  entries.push({
    name: "README.md",
    data: encoder.encode(
      [
        "# AI Production Packages",
        "",
        `Exported ${new Date().toISOString()} from the SRPG Character Workshop (Phase 9).`,
        "",
        "Each directory is one self-contained Production Package:",
        "",
        ...jobs.map((job) => `- \`${packageDirName(job)}/\` — ${job.name || job.id} (${job.draft.type}, promptVersion ${job.promptVersion})`),
        "",
        "Produce each asset separately. Do not modify the base character.",
        "",
      ].join("\n"),
    ),
  });
  downloadBlob(createZip(entries), `ai-packages-${jobs.length}.zip`);
}
