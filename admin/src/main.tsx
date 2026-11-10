import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';
import SkillEditor, { validateSkill } from './SkillEditor';
import JobEditor from './JobEditor';
import { newJob, objectFields, validateJob } from './jobData';

type RecordData = { id: string; name?: string; title?: string; status?: string; priority?: string; area?: string; godotFiles?: string[]; description?: string; body?: string; assignee?: string; relatedDataIds?: string[]; [key: string]: unknown };
const categories = ['tasks', 'skills', 'characters', 'jobs', 'equipment', 'items', 'stories', 'stages'] as const;
type Category = typeof categories[number];
const labels: Record<Category, string> = { tasks: '実装タスク', skills: 'スキル', characters: 'キャラクター', jobs: 'ジョブ', equipment: '装備', items: 'アイテム', stories: 'ストーリー', stages: 'ステージ' };
const statuses = ['todo', 'in_progress', 'blocked', 'done'];
const statusLabels: Record<string, string> = { todo: '未着手', in_progress: '対応中', blocked: '保留', done: '完了' };
const template = (category: Category, id: string): RecordData => category === 'tasks'
  ? { id, title: '新規タスク', status: 'todo', priority: 'medium', area: 'godot', description: '', body: '', assignee: '', godotFiles: [], relatedDataIds: [] }
  : category === 'skills'
  ? { id, name: '新規スキル', type: 'passive', activationMode: 'equipped', effects: [], triggers: [], description: '' }
  : category === 'jobs' ? newJob(id)
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
  const [search, setSearch] = useState('');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [areaFilter, setAreaFilter] = useState('all');
  const [jsonMode, setJsonMode] = useState(false);
  const [jobSkills, setJobSkills] = useState<RecordData[]>([]);
  const [jobSkillsError, setJobSkillsError] = useState('');
  const requestVersion = useRef(0);
  const hasForm = category === 'tasks' || category === 'skills' || category === 'jobs';
  const counts = useMemo(() => Object.fromEntries(statuses.map(s => [s, rows.filter(r => r.status === s).length])), [rows]);
  const visible = rows.filter(r => (category !== 'tasks' || ((filter === 'all' || r.status === filter) && (priorityFilter === 'all' || r.priority === priorityFilter) && (areaFilter === 'all' || r.area === areaFilter))) && [r.id, r.title, r.name, r.body, r.description].some(v => String(v || '').toLowerCase().includes(search.toLowerCase())));
  async function refresh(cat: Category = category) {
    const version = ++requestVersion.current;
    setLoading(true); setError('');
    try {
      const records = await request<RecordData[]>(cat);
      if (version === requestVersion.current) setRows(records.sort((a, b) => a.id.localeCompare(b.id)));
    } catch (e) { if (version === requestVersion.current) setError(String(e)); }
    finally { if (version === requestVersion.current) setLoading(false); }
  }
  useEffect(() => { setRows([]); setSelected(''); setDraft(''); setNotice(''); setFilter('all'); setPriorityFilter('all'); setAreaFilter('all'); setSearch(''); setJsonMode(false); void refresh(category); }, [category]);
  useEffect(() => {
    if (category !== 'jobs') return;
    let current = true;
    setJobSkillsError('');
    void request<RecordData[]>('skills').then(records => {
      if (current) setJobSkills(records);
    }).catch(() => {
      if (current) setJobSkillsError('スキル候補を読み込めませんでした。スキルIDは手入力できます。');
    });
    return () => { current = false; };
  }, [category]);
  function open(record: RecordData) { setSelected(record.id); setJsonMode(false); setDraft(JSON.stringify(record, null, 2)); setNotice(''); setError(''); }
  function add() {
    const id = prompt('新規ID（英数字、_、-）');
    if (!id) return;
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) { setError('IDは英数字、_、-のみ使用できます'); return; }
    if (rows.some(r => r.id === id)) { setError('同じIDが存在します'); return; }
    open(template(category, id));
  }
  function patchTask(key: string, value: unknown) { try { const data = JSON.parse(draft); setDraft(JSON.stringify({ ...data, [key]: value }, null, 2)); setError(''); setNotice(''); } catch { setError('JSONを修正してからフォーム編集してください'); } }
  const formRecord: RecordData | null = hasForm && selected ? (() => {
    try {
      const value = JSON.parse(draft);
      return objectFields(value) === value ? value as RecordData : null;
    } catch { return null; }
  })() : null;
  const task = category === 'tasks' ? formRecord : null;
  function updateDraft(value: Record<string, unknown>) {
    setDraft(JSON.stringify(value, null, 2));
    setNotice('');
    setError('');
  }
  async function save() {
    try {
      const value = JSON.parse(draft) as RecordData;
      if (!value || Array.isArray(value) || value.id !== selected) throw new Error('IDは変更できません');
      if (category === 'tasks') {
        if (!String(value.title || '').trim() || !statuses.includes(String(value.status))) throw new Error('タイトルと有効なステータスが必要です');
        if (!['low','medium','high','critical'].includes(String(value.priority))) throw new Error('優先度が不正です');
        if (!['godot','admin','design','other'].includes(String(value.area))) throw new Error('分類が不正です');
        if (typeof value.body !== 'string' || !value.body.trim()) throw new Error('AIエージェント向けの本文を入力してください');
        if (!Array.isArray(value.godotFiles) || !value.godotFiles.every(x => typeof x === 'string')) throw new Error('対象ファイルの形式が不正です');
        if (!Array.isArray(value.relatedDataIds) || !value.relatedDataIds.every(x => typeof x === 'string')) throw new Error('関連IDの形式が不正です');
        value.description = value.body;
      }
      if (category === 'skills') { const validationError = validateSkill(value); if (validationError) throw new Error(validationError); }
      if (category === 'jobs') { const validationError = validateJob(value); if (validationError) throw new Error(validationError); }
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
      <div className="filters"><input aria-label="検索" placeholder="ID・タイトル・本文を検索" value={search} onChange={e => setSearch(e.target.value)} />{category === 'tasks' && <><select aria-label="優先度フィルター" value={priorityFilter} onChange={e => setPriorityFilter(e.target.value)}><option value="all">すべての優先度</option>{['critical','high','medium','low'].map(v => <option key={v} value={v}>{v}</option>)}</select><select aria-label="分類フィルター" value={areaFilter} onChange={e => setAreaFilter(e.target.value)}><option value="all">すべての分類</option>{['godot','admin','design','other'].map(v => <option key={v} value={v}>{v}</option>)}</select></>}</div>
      <section className="workspace"><div className="records"><div className="section-head">レコード <span>{visible.length}件</span></div>{loading && <p>読み込み中...</p>}{visible.map(r => <button className={selected === r.id ? 'record selected' : 'record'} key={r.id} onClick={() => open(r)}><b>{r.title || r.name || r.id}</b><small>{r.id}</small>{category === 'tasks' && <em>{statusLabels[String(r.status)] || r.status}</em>}</button>)}{!loading && visible.length === 0 && <p className="empty">レコードがありません</p>}</div>
        <div className="editor"><div className="section-head">{category === 'tasks' ? 'タスク詳細' : category === 'skills' ? 'スキル詳細' : category === 'jobs' ? 'ジョブ詳細' : 'JSONエディタ'} <span>{selected || '未選択'}</span></div>{selected ? <><p className="hint">ローカルJSONに保存します。Godot本体には変更を加えません。</p>{hasForm && <button className="mode-toggle" onClick={() => setJsonMode(!jsonMode)}>{jsonMode ? 'フォーム編集に戻る' : 'JSONを直接編集'}</button>}{category === 'tasks' && !jsonMode && task ? <div className="task-form"><label>タイトル<input value={task.title || ''} onChange={e => patchTask('title', e.target.value)} /></label><div className="form-grid"><label>ステータス<select value={task.status || 'todo'} onChange={e => patchTask('status', e.target.value)}>{statuses.map(v => <option key={v} value={v}>{statusLabels[v]}</option>)}</select></label><label>優先度<select value={task.priority || 'medium'} onChange={e => patchTask('priority', e.target.value)}>{['critical','high','medium','low'].map(v => <option key={v} value={v}>{v}</option>)}</select></label><label>分類<select value={task.area || 'godot'} onChange={e => patchTask('area', e.target.value)}>{['godot','admin','design','other'].map(v => <option key={v} value={v}>{v}</option>)}</select></label><label>担当<input value={task.assignee || ''} onChange={e => patchTask('assignee', e.target.value)} placeholder="任意" /></label></div><label>本文（AIエージェント向け実装指示）<textarea className="task-body" value={task.body ?? task.description ?? ''} onChange={e => patchTask('body', e.target.value)} placeholder="目的、実装内容、完了条件、注意事項を記載" /></label><label>対象ファイル（1行に1件）<textarea className="task-lines" value={(task.godotFiles || []).join('\n')} onChange={e => patchTask('godotFiles', e.target.value.split('\n').map(x => x.trim()).filter(Boolean))} /></label><label>関連データID（1行に1件）<textarea className="task-lines" value={(task.relatedDataIds || []).join('\n')} onChange={e => patchTask('relatedDataIds', e.target.value.split('\n').map(x => x.trim()).filter(Boolean))} /></label></div> : category === 'skills' && !jsonMode && formRecord ? <SkillEditor value={formRecord} onChange={updateDraft} /> : category === 'jobs' && !jsonMode && formRecord ? <>{jobSkillsError && <p className="hint">{jobSkillsError}</p>}<JobEditor value={formRecord} jobs={rows} skills={jobSkills} onChange={updateDraft} /></> : <textarea spellCheck={false} value={draft} onChange={e => { setDraft(e.target.value); setNotice(''); }} />}<div className="actions"><button className="primary" onClick={() => void save()}>保存</button><button className="danger" onClick={() => void remove()}>削除</button></div></> : <p className="empty">左側からレコードを選択してください</p>}</div></section>
      {error && <p role="alert" className="error">{error}</p>}{notice && <p role="status" className="notice">{notice}</p>}
      <footer>管理画面のJSONは設計・管理用です。Godot側のローダーとリアクション処理は実装タスクで追跡します。</footer>
    </main>
  </div>;
}
createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
