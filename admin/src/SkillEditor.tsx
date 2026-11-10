import React from 'react';

type Json = Record<string, any>;
type Props = { value: Json; onChange: (value: Json) => void };
const TYPES = ['attack', 'heal', 'buff', 'debuff', 'passive'];
const EFFECTS = ['counter_attack', 'heal', 'stat_bonus', 'damage', 'buff', 'debuff'];
const ORIGINS = ['active', 'reaction'];
const RESULTS = ['hit', 'evade'];
const inputNumber = (v: unknown, fallback = 0) => Number.isFinite(Number(v)) ? Number(v) : fallback;

export function validateSkill(value: Json): string | null {
  if (!String(value.name || '').trim()) return 'スキル名が必要です';
  if (!TYPES.includes(String(value.type))) return 'スキル種別が不正です';
  if (value.type === 'passive') {
    if (value.activationMode !== 'equipped') return 'パッシブは装備時発動を指定してください';
    if (!Array.isArray(value.triggers)) return 'triggersは配列にしてください';
    for (const [index, trigger] of value.triggers.entries()) {
      if (trigger.event !== 'on_attacked') return `トリガー${index + 1}: 未対応イベントです`;
      if (!Array.isArray(trigger.attackOrigins) || !trigger.attackOrigins.length || trigger.attackOrigins.some((x: string) => !ORIGINS.includes(x))) return `トリガー${index + 1}: 攻撃種別が不正です`;
      if (!Array.isArray(trigger.hitResults) || !trigger.hitResults.length || trigger.hitResults.some((x: string) => !RESULTS.includes(x))) return `トリガー${index + 1}: 命中結果が不正です`;
      if (typeof trigger.chance !== 'number' || !Number.isFinite(trigger.chance) || trigger.chance < 0 || trigger.chance > 1) return `トリガー${index + 1}: 確率は0〜100%で指定してください`;
      if (!Array.isArray(trigger.effects) || !trigger.effects.length) return `トリガー${index + 1}: 効果を1つ以上指定してください`;
      for (const effect of trigger.effects) {
        if (!EFFECTS.includes(effect.type)) return '未対応の効果種別です';
        if (effect.type === 'counter_attack' && trigger.attackOrigins.includes('reaction')) return '反撃効果の攻撃種別にREACTIONは指定できません';
      }
    }
  } else {
    for (const key of ['apCost', 'power', 'minRange', 'maxRange']) {
      if (!Number.isFinite(value[key])) return `${key} は数値で指定してください`;
    }
    if (value.minRange < 0 || value.maxRange < value.minRange) return '射程が不正です';
  }
  return null;
}

export default function SkillEditor({ value, onChange }: Props) {
  const patch = (key: string, next: unknown) => onChange({ ...value, [key]: next });
  const triggers: Json[] = Array.isArray(value.triggers) ? value.triggers : [];
  const patchTrigger = (index: number, fields: Json) => patch('triggers', triggers.map((t, i) => i === index ? { ...t, ...fields } : t));
  const patchEffect = (ti: number, ei: number, fields: Json) => {
    const effects: Json[] = triggers[ti].effects || [];
    patchTrigger(ti, { effects: effects.map((e, i) => i === ei ? { ...e, ...fields } : e) });
  };
  return <div className="task-form skill-form">
    <label>スキル名<input value={value.name || ''} onChange={e => patch('name', e.target.value)} /></label>
    <label>説明<textarea className="task-lines" value={value.description || ''} onChange={e => patch('description', e.target.value)} /></label>
    <div className="form-grid">
      <label>種別<select value={value.type || 'attack'} onChange={e => patch('type', e.target.value)}>{TYPES.map(t => <option key={t} value={t}>{t}</option>)}</select></label>
      {value.type === 'passive' ? <label>有効化方式<select value={value.activationMode || 'equipped'} onChange={e => patch('activationMode', e.target.value)}><option value="equipped">装備中のみ</option></select></label> : <>
        <label>対象<select value={value.targetType || 'ENEMY'} onChange={e => patch('targetType', e.target.value)}>{['ENEMY','ALLY','SELF','ALL'].map(t => <option key={t}>{t}</option>)}</select></label>
        <label>AP消費<input type="number" value={value.apCost ?? 0} onChange={e => patch('apCost', inputNumber(e.target.value))} /></label>
        <label>威力<input type="number" value={value.power ?? 0} onChange={e => patch('power', inputNumber(e.target.value))} /></label>
        <label>最小射程<input type="number" value={value.minRange ?? 1} onChange={e => patch('minRange', inputNumber(e.target.value))} /></label>
        <label>最大射程<input type="number" value={value.maxRange ?? 1} onChange={e => patch('maxRange', inputNumber(e.target.value))} /></label>
        <label>命中補正<input type="number" value={value.accuracyModifier ?? 0} onChange={e => patch('accuracyModifier', inputNumber(e.target.value))} /></label>
        <label>属性<select value={value.element || 'NONE'} onChange={e => patch('element', e.target.value)}>{['NONE','FIRE','WATER','EARTH','WIND','THUNDER','ICE','DARK','LIGHT'].map(t => <option key={t}>{t}</option>)}</select></label>
      </>}
    </div>
    {value.type === 'passive' && <>
      <div className="section-head">発動条件 <button type="button" className="mode-toggle" onClick={() => patch('triggers', [...triggers, { event: 'on_attacked', attackOrigins: ['active'], hitResults: ['hit','evade'], chance: 0.5, effects: [{ type: 'counter_attack', target: 'attacker', powerMultiplier: 1 }] }])}>＋ 条件を追加</button></div>
      {triggers.map((t, ti) => <div className="trigger-card" key={ti}>
        <div className="section-head">条件 {ti + 1}<button className="danger" type="button" onClick={() => patch('triggers', triggers.filter((_, i) => i !== ti))}>削除</button></div>
        <div className="form-grid"><label>イベント<select value={t.event || 'on_attacked'} onChange={e => patchTrigger(ti, { event: e.target.value })}><option value="on_attacked">攻撃されたとき</option></select></label>
          <label>発動確率（%）<input type="number" min="0" max="100" step="1" value={Math.round((t.chance ?? 0.5) * 10000) / 100} onChange={e => patchTrigger(ti, { chance: inputNumber(e.target.value) / 100 })} /></label></div>
        <fieldset><legend>攻撃種別</legend>{ORIGINS.map(origin => <label className="inline-check" key={origin}><input type="checkbox" checked={(t.attackOrigins || []).includes(origin)} onChange={e => patchTrigger(ti, { attackOrigins: e.target.checked ? [...(t.attackOrigins || []), origin] : (t.attackOrigins || []).filter((x: string) => x !== origin) })} />{origin.toUpperCase()}</label>)}</fieldset>
        <fieldset><legend>命中結果</legend>{RESULTS.map(result => <label className="inline-check" key={result}><input type="checkbox" checked={(t.hitResults || []).includes(result)} onChange={e => patchTrigger(ti, { hitResults: e.target.checked ? [...(t.hitResults || []), result] : (t.hitResults || []).filter((x: string) => x !== result) })} />{result === 'hit' ? '命中' : '回避'}</label>)}</fieldset>
        {(t.effects || []).map((effect: Json, ei: number) => <div className="effect-card" key={ei}>
          <div className="form-grid"><label>効果<select value={effect.type || 'counter_attack'} onChange={e => patchEffect(ti, ei, { type: e.target.value })}>{EFFECTS.map(type => <option key={type} value={type}>{type}</option>)}</select></label>
            <label>対象<input value={effect.target || 'attacker'} onChange={e => patchEffect(ti, ei, { target: e.target.value })} /></label>
            <label>倍率<input type="number" step="0.1" value={effect.powerMultiplier ?? 1} onChange={e => patchEffect(ti, ei, { powerMultiplier: inputNumber(e.target.value) })} /></label></div>
          <button className="danger" type="button" onClick={() => patchTrigger(ti, { effects: (t.effects || []).filter((_: unknown, i: number) => i !== ei) })}>効果を削除</button>
        </div>)}
        <button className="mode-toggle" type="button" onClick={() => patchTrigger(ti, { effects: [...(t.effects || []), { type: 'heal', target: 'self', powerMultiplier: 1 }] })}>＋ 効果を追加</button>
      </div>)}
    </>}
  </div>;
}
