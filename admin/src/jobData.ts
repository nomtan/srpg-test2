export const jobRanks = { BASIC: '下位', ADVANCED: '上位', MASTER: '最上位' };

export const growthFields = {
  max_hp: '最大HP', max_ap: '最大AP', attack_power: '攻撃力', defense: '防御力', accuracy: '命中', evasion: '回避'
};

export const statFields = { str: 'STR', dex: 'DEX', vit: 'VIT', mnd: 'MND', int: 'INT', agi: 'AGI' };

// Values match WeaponData.WeaponType in Godot (0 denotes no weapon).
export const weaponTypes = [
  [1, '剣'], [2, '斧'], [3, '槍'], [4, '弓'], [5, '短剣'], [6, '双剣'], [7, '杖'], [8, 'メイス'], [9, '拳武器']
] as const;

export function objectFields(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

export function newJob(id: string) {
  return {
    id, name: '新規ジョブ', rank: 'BASIC',
    growth: { max_hp: 5, max_ap: 1, attack_power: 1, defense: 1, accuracy: 1, evasion: 1 },
    statBonus: { str: 0, dex: 0, vit: 0, mnd: 0, int: 0, agi: 0 },
    hpBonus: 0, baseMoveRange: 4, baseJumpHeight: 1, speedModifier: 1,
    requiredJobLevels: {}, learnableSkills: [], allowedWeaponTypes: [], playerSelectable: true, bodyScenePath: ''
  };
}

function isId(value: unknown): value is string {
  return typeof value === 'string' && /^[a-zA-Z0-9_-]+$/.test(value);
}

function isInteger(value: unknown, min = Number.MIN_SAFE_INTEGER): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min;
}

export function validateJob(job: Record<string, unknown>): string | undefined {
  if (typeof job.name !== 'string' || !job.name.trim()) return 'ジョブ名を入力してください';
  if (typeof job.rank !== 'string' || !Object.prototype.hasOwnProperty.call(jobRanks, job.rank)) return '階級が不正です';

  for (const [key, fields] of [['growth', growthFields], ['statBonus', statFields]] as const) {
    const values = objectFields(job[key]);
    for (const [field, label] of Object.entries(fields)) {
      if (!isInteger(values[field])) return `${key === 'growth' ? '成長率' : 'ステータス補正'}の${label}は整数で入力してください`;
    }
  }
  if (!isInteger(job.hpBonus) || !isInteger(job.baseMoveRange, 0) || !isInteger(job.baseJumpHeight, 0)) {
    return 'HP補正は整数、移動範囲とジャンプ力は0以上の整数で入力してください';
  }
  if (typeof job.speedModifier !== 'number' || !Number.isFinite(job.speedModifier) || job.speedModifier <= 0) {
    return '速度倍率は0より大きい数で入力してください';
  }
  if (typeof job.playerSelectable !== 'boolean' || typeof job.bodyScenePath !== 'string') return '選択可否または外見パスが不正です';
  if (job.unlockPending !== undefined && typeof job.unlockPending !== 'boolean') return '転職条件の確定待ち設定が不正です';

  const requirements = objectFields(job.requiredJobLevels);
  if (requirements !== job.requiredJobLevels || Object.entries(requirements).some(([id, level]) => !isId(id) || id === job.id || !isInteger(level, 1))) {
    return '転職条件には、このジョブ以外の有効なジョブIDと1以上の必要レベルを指定してください';
  }

  if (!Array.isArray(job.learnableSkills)) return '習得スキルの形式が不正です';
  const skillIds = new Set<string>();
  for (const row of job.learnableSkills) {
    const { skill_id, job_level } = objectFields(row);
    if (!isId(skill_id) || !isInteger(job_level, 1)) return '習得スキルには有効なスキルIDと1以上の習得レベルを指定してください';
    if (skillIds.has(skill_id)) return `習得スキルが重複しています（${skill_id}）`;
    skillIds.add(skill_id);
  }

  const weapons = job.allowedWeaponTypes;
  if (!Array.isArray(weapons) || weapons.some(type => !weaponTypes.some(([id]) => type === id)) || new Set(weapons).size !== weapons.length) {
    return '装備可能武器に不正または重複した種類があります';
  }
}
