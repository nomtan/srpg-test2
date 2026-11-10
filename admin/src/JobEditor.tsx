import { growthFields, jobRanks, objectFields, statFields, weaponTypes } from './jobData';

type JobRecord = { id: string; name?: string; [key: string]: unknown };

function NumberField({ label, value, onChange, min, step = 1 }: {
  label: string;
  value: unknown;
  onChange: (value: number | null) => void;
  min?: number;
  step?: number | 'any';
}) {
  return <label>{label}<input type="number" value={typeof value === 'number' ? value : ''} min={min} step={step}
    onChange={e => onChange(Number.isNaN(e.currentTarget.valueAsNumber) ? null : e.currentTarget.valueAsNumber)} /></label>;
}

function recordLabel(record: JobRecord) {
  return record.name ? `${record.name}（${record.id}）` : record.id;
}

export default function JobEditor({ value, jobs, skills, onChange }: {
  value: JobRecord;
  jobs: JobRecord[];
  skills: JobRecord[];
  onChange: (value: JobRecord) => void;
}) {
  const patch = (key: string, next: unknown) => onChange({ ...value, [key]: next });
  const requirements = objectFields(value.requiredJobLevels);
  const jobOptions = new Map(jobs.map(job => [job.id, recordLabel(job)]));
  for (const job of [...jobs, value]) {
    for (const id of Object.keys(objectFields(job.requiredJobLevels))) {
      if (!jobOptions.has(id)) jobOptions.set(id, `${id}（ジョブJSON未登録）`);
    }
  }
  const learnableSkills = Array.isArray(value.learnableSkills) ? value.learnableSkills.map(objectFields) : [];
  const weapons: unknown[] = Array.isArray(value.allowedWeaponTypes) ? value.allowedWeaponTypes : [];
  const updateSkill = (index: number, key: string, next: unknown) => patch('learnableSkills',
    learnableSkills.map((skill, i) => i === index ? { ...skill, [key]: next } : skill));

  return <div className="task-form job-form">
    <fieldset>
      <legend>基本情報</legend>
      <div className="form-grid">
        <label>ジョブ名<input value={value.name ?? ''} onChange={e => patch('name', e.target.value)} /></label>
        <label>階級<select value={String(value.rank ?? '')} onChange={e => patch('rank', e.target.value)}>
          <option value="" disabled>選択してください</option>
          {Object.entries(jobRanks).map(([id, label]) => <option value={id} key={id}>{label}</option>)}
        </select></label>
      </div>
      <label>外見シーンのパス<input value={String(value.bodyScenePath ?? '')} onChange={e => patch('bodyScenePath', e.target.value)} placeholder="res://scenes/…" /></label>
      <label className="inline-check"><input type="checkbox" checked={value.playerSelectable === true} onChange={e => patch('playerSelectable', e.target.checked)} />プレイヤーが選択可能</label>
    </fieldset>

    {([['growth', '成長率', growthFields], ['statBonus', 'ステータス補正', statFields]] as const).map(([key, title, fields]) => {
      const values = objectFields(value[key]);
      return <fieldset key={key}>
        <legend>{title}</legend>
        <div className="form-grid">{Object.entries(fields).map(([id, label]) => <NumberField key={id} label={label} value={values[id]}
          onChange={next => patch(key, { ...values, [id]: next })} />)}</div>
      </fieldset>;
    })}

    <fieldset>
      <legend>HP・移動・速度</legend>
      <div className="form-grid">
        <NumberField label="HP補正" value={value.hpBonus} onChange={next => patch('hpBonus', next)} />
        <NumberField label="移動範囲" value={value.baseMoveRange} min={0} onChange={next => patch('baseMoveRange', next)} />
        <NumberField label="ジャンプ力" value={value.baseJumpHeight} min={0} onChange={next => patch('baseJumpHeight', next)} />
        <NumberField label="速度倍率" value={value.speedModifier} step="any" onChange={next => patch('speedModifier', next)} />
      </div>
    </fieldset>

    <fieldset>
      <legend>転職条件</legend>
      <label className="inline-check"><input type="checkbox" checked={value.unlockPending === true} onChange={e => patch('unlockPending', e.target.checked)} />新規解放を保留</label>
      {Object.entries(requirements).map(([id, level]) => <div className="job-entry" key={id}>
        <span>{jobOptions.get(id) ?? id}</span>
        <NumberField label="必要レベル" value={level} min={1} onChange={next => patch('requiredJobLevels', { ...requirements, [id]: next })} />
        <button type="button" className="danger" aria-label={`${id}の転職条件を削除`} onClick={() => {
          const next = { ...requirements };
          delete next[id];
          patch('requiredJobLevels', next);
        }}>削除</button>
      </div>)}
      <label>転職条件を追加<select value="" onChange={e => patch('requiredJobLevels', { ...requirements, [e.target.value]: 1 })}>
        <option value="" disabled>ジョブを選択</option>
        {[...jobOptions].filter(([id]) => id !== value.id && !Object.prototype.hasOwnProperty.call(requirements, id))
          .map(([id, label]) => <option value={id} key={id}>{label}</option>)}
      </select></label>
    </fieldset>

    <fieldset>
      <legend>習得スキル</legend>
      <datalist id="job-skill-options">{skills.map(skill => <option key={skill.id} value={skill.id}>{skill.name}</option>)}</datalist>
      {learnableSkills.map((skill, index) => <div className="job-entry" key={index}>
        <label>スキルID<input list="job-skill-options" value={String(skill.skill_id ?? '')} onChange={e => updateSkill(index, 'skill_id', e.target.value)} /></label>
        <NumberField label="習得レベル" value={skill.job_level} min={1} onChange={next => updateSkill(index, 'job_level', next)} />
        <button type="button" className="danger" aria-label={`${index + 1}行目の習得スキルを削除`}
          onClick={() => patch('learnableSkills', learnableSkills.filter((_, i) => i !== index))}>削除</button>
      </div>)}
      <button type="button" className="mode-toggle" onClick={() => patch('learnableSkills', [...learnableSkills, { skill_id: '', job_level: 1 }])}>＋ 習得スキルを追加</button>
    </fieldset>

    <fieldset>
      <legend>装備可能武器</legend>
      <div className="job-weapons">{weaponTypes.map(([id, label]) => <label className="inline-check" key={id}>
        <input type="checkbox" checked={weapons.includes(id)} onChange={e => patch('allowedWeaponTypes', e.target.checked ? [...weapons, id] : weapons.filter(type => type !== id))} />{label}
      </label>)}</div>
    </fieldset>
  </div>;
}
