"use client";

// Phase 9 AI Production Queue (spec section 54-56). State management only: no background AI job
// runs here, and nothing is sent to a provider.
import Link from "next/link";
import { useMemo, useState } from "react";
import { ASSET_TYPE_LABELS } from "@/domain/asset-spec";
import { latestRevision, type ProductionJob } from "@/domain/production-job";
import {
  PRODUCTION_STATUS_BADGE, QUEUE_FILTERS, QUEUE_FILTER_LABEL, matchesQueueFilter,
  type QueueFilter,
} from "@/domain/production-status";
import { useLibraryIndex } from "@/features/library/use-library-index";
import { JobDetail } from "./job-detail";
import { exportProductionPackages } from "./package-export";

export function ProductionScreen() {
  const { index, loading, error, refresh } = useLibraryIndex();
  const [filter, setFilter] = useState<QueueFilter>("all");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);

  const jobs = index.productions;
  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return jobs.filter((job) => {
      if (!matchesQueueFilter(job.status, filter)) return false;
      if (!q) return true;
      return (
        job.id.toLowerCase().includes(q) ||
        job.name.toLowerCase().includes(q) ||
        job.draft.type.includes(q) ||
        job.tags.some((t) => t.includes(q))
      );
    });
  }, [jobs, filter, query]);

  const selected = jobs.find((j) => j.id === selectedId) ?? visible[0] ?? null;

  const counts = useMemo(() => {
    const map: Record<string, number> = {};
    for (const f of QUEUE_FILTERS) map[f] = jobs.filter((j) => matchesQueueFilter(j.status, f)).length;
    return map;
  }, [jobs]);

  const toggle = (id: string) =>
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });

  async function batchExport() {
    const targets = jobs.filter((j) => checked.has(j.id));
    if (!targets.length) return;
    setBusy(true);
    try {
      await exportProductionPackages(targets);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">AI PRODUCTION</p>
          <h1>Production Queue</h1>
          <p>
            Asset 定義から Production Package を作り、外部 AI の生成結果を Import・Validation・Approve します。
            Approve した Asset だけが Asset Library に登録されます。
          </p>
        </div>
        <span className="badge">PHASE 9</span>
      </div>

      {error && <p className="save-msg err">Library API エラー: {error}</p>}

      <div className="production-workspace">
        <section className="panel production-queue">
          <div className="panel-heading">
            <h2>Queue</h2>
            <span className="count">{visible.length} / {jobs.length}</span>
          </div>

          <div className="queue-filters">
            {QUEUE_FILTERS.map((f) => (
              <button
                key={f}
                type="button"
                className={filter === f ? "on" : ""}
                onClick={() => setFilter(f)}
              >
                {QUEUE_FILTER_LABEL[f]} <em>{counts[f] ?? 0}</em>
              </button>
            ))}
          </div>

          <label className="queue-search">検索
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="id / name / type / tag" />
          </label>

          <div className="queue-batch">
            <button type="button" disabled={busy || checked.size === 0} onClick={batchExport}>
              Export Prompt Packages ({checked.size})
            </button>
            {checked.size > 0 && (
              <button type="button" className="mini" onClick={() => setChecked(new Set())}>選択解除</button>
            )}
          </div>

          <ul className="queue-list">
            {loading && !jobs.length && <li className="muted">読み込み中…</li>}
            {!loading && !jobs.length && (
              <li className="muted">
                Production Job がありません。<Link href="/creator">Asset Creator</Link> で Asset を定義し、
                AI Production の「Generate Production Package」を実行してください。
              </li>
            )}
            {visible.map((job) => (
              <li key={job.id} className={selected?.id === job.id ? "selected" : undefined}>
                <input
                  type="checkbox"
                  aria-label={`${job.id} を Batch Export に含める`}
                  checked={checked.has(job.id)}
                  onChange={() => toggle(job.id)}
                />
                <button type="button" className="queue-entry" onClick={() => setSelectedId(job.id)}>
                  <strong>{job.name || job.id}</strong>
                  <small>{job.id} · {ASSET_TYPE_LABELS[job.draft.type]}</small>
                  <span className={`prod-badge ${job.status}`}>{PRODUCTION_STATUS_BADGE[job.status]}</span>
                  <small className="queue-sub">{summaryOf(job)}</small>
                </button>
              </li>
            ))}
          </ul>
        </section>

        {selected
          ? <JobDetail key={selected.id} job={selected} onChanged={refresh} />
          : (
            <section className="panel job-detail empty">
              <p className="muted">Job を選択してください。</p>
            </section>
          )}
      </div>
    </>
  );
}

function summaryOf(job: ProductionJob): string {
  const rev = latestRevision(job);
  const parts = [`promptVersion ${job.promptVersion}`];
  if (rev) parts.push(`Revision ${rev.revision}: ${rev.validation.verdict} ${rev.validation.score}/100`);
  else parts.push("未 Import");
  if (job.tags.length) parts.push(job.tags.join(" · "));
  return parts.join(" · ");
}
