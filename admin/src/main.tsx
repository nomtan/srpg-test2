import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

type RecordData = { id: string; name?: string; title?: string; status?: string; priority?: string; area?: string; godotFiles?: string[]; description?: string; [key: string]: unknown };
const categories = ['tasks', 'skills', 'characters', 'jobs', 'equipment', 'items', 'stories', 'stages'] as const;
type Category = typeof categories[number];
const labels: Record<Category, string> = { tasks: '実装タスク', skills: 'スキル', characters: 'キャラクター', jobs: 'ジョブ', equipment: '装備', items: 'アイテム', stories: 'ストーリー', stages: 'ステージ' };
const statuses = ['todo', 'in_progress', 'blocked', 'done'];
const statusLabels: Record<string, string> = { todo: '未着手', in_progress: '対応中', blocked: '保留', done: '完了' };
const template = (category: Category, id: string): RecordData => category === 'tasks'
  ? { id, title: '新規タスク', status: 'todo', priority: 'medium', area: 'godot', description: '', godotFiles: [], relatedDataIds: [] }
  : category === 'skills'
  ? { id, name: '新規スキル', type: 'passive', activationMode: 'equipped', effects: [], triggers: [], description: '' }
  : { id, name: '新規データ', description: '' };

async function request<T>(category: Category, id?: string, method = 'GET', body?: unknown): Promise<T> {
  const res = await fetch('/api/data/' + category + (id ? '/' + encodeURIComponent(id) : ''), {
    method, headers: { 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body)
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error || 'Request failed');
  return json as T;
}
function App() {
  const [category, setCategory] = useState<Category>('tasks');
  const [rows, setRows] = useState<RecordData[]>([]);
  const [selected, setSelected] = useState('');
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [filter, setFilter] = useState('all');
  const [loading, setLoading] = useState(false);
  const counts = useMemo(() => Object.fromEntries(statuses.map(s => [s, rows.filter(r => r.status === s).length])), [rows]);
  const visible = category === 'tasks' && filter !== 'all' ? rows.filter(r => r.status === filter) : rows;
  async function refresh(cat: Category = category) {
    setLoading(true); setError('');
    try {
      const records = await request<RecordData[]>(cat);
      setRows(records.sort((a, b) => a.id.localeCompare(b.id)));
    } catch (e) { setError(String(e)); } finally { setLoading(false); }
  }
  useEffect(() => { setSelected(''); setDraft(''); setNotice(''); setFilter('all'); void refresh(category); }, [category]);
  function open(record: RecordData) { setSelected(record.id); setDraft(JSON.stringify(record, null, 2)); setNotice(''); setError(''); }
  function add() {
    const id = prompt('新規ID（英数字、_、-）');
    if (!id) return;
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) { setError('IDは英数字、_、-のみ使用できます'); return; }
    if (rows.some(r => r.id === id)) { setError('同じIDが存在します'); return; }
    open(template(category, id));
  }
  async function save() {
    try {
      const value = JSON.parse(draft) as RecordData;
      if (!value || Array.isArray(value) || value.id !== selected) throw new Error('IDは変更できません');
      if (category === 'tasks' && (!value.title || !statuses.includes(String(value.status)))) throw new Error('タスク名と有効なステータスが必要です');
      await request(category, selected, 'PUT', value);
      setNotice('保存しました（ローカルJSONに反映）');
      await refresh();
    } catch (e) { setError(String(e)); }
  }
  async function remove() {
    if (!selected || !rows.some(r => r.id === selected)) return;
    if (!confirm(selected + ' を削除しますか？')) return;
    try { await request(category, selected, 'DELETE'); setSelected(''); setDraft(''); await refresh(); } catch (e) { setError(String(e)); }
  }
  return <div className="layout">
    <aside><h1>SRPG <span>ADMIN</span></h1><p className="sub">Local Data Studio · Phase 1</p>
      <nav>{categories.map(cat => <button key={cat} className={cat === category ? 'active' : ''} onClick={() => setCategory(cat)}>{labels[cat]}</button>)}</nav>
      <small>Git操作は行いません。変更はリポジトリ内のJSONファイルに保存されます。</small>
    </aside>
    <main><header><div><p className="eyebrow">PROJECT / SRPG-TEST2</p><h2>{labels[category]}</h2></div><button className="primary" onClick={add}>＋ 新規作成</button></header>
      {category === 'tasks' && <div className="stats">{statuses.map(s => <button key={s} className={filter === s ? 'chosen' : ''} onClick={() => setFilter(filter === s ? 'all' : s)}><strong>{counts[s] || 0}</strong><span>{statusLabels[s]}</span></button>)}</div>}
      <section className="workspace"><div className="records"><div className="section-head">レコード <span>{visible.length}件</span></div>{loading && <p>読み込み中...</p>}{visible.map(r => <button className={selected === r.id ? 'record selected' : 'record'} key={r.id} onClick={() => open(r)}><b>{r.title || r.name || r.id}</b><small>{r.id}</small>{category === 'tasks' && <em>{statusLabels[String(r.status)] || r.status}</em>}</button>)}{!loading && visible.length === 0 && <p className="empty">レコードがありません</p>}</div>
        <div className="editor"><div className="section-head">JSONエディタ <span>{selected || '未選択'}</span></div>{selected ? <><p className="hint">保存時に構文とIDを検証します。Godotへの自動反映は未実装です。</p><textarea spellCheck={false} value={draft} onChange={e => { setDraft(e.target.value); setNotice(''); }} /><div className="actions"><button className="primary" onClick={() => void save()}>保存</button><button className="danger" onClick={() => void remove()}>削除</button></div></> : <p className="empty">左側からレコードを選択してください</p>}</div></section>
      {error && <p role="alert" className="error">{error}</p>}{notice && <p role="status" className="notice">{notice}</p>}
      <footer>管理画面のJSONは設計・管理用です。Godot側のローダーとリアクション処理は実装タスクで追跡します。</footer>
    </main>
  </div>;
}
createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
