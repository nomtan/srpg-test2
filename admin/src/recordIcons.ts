const iconFolders = { skills: 'skill-icons', jobs: 'job-icons', equipment: 'equipment-icons', items: 'item-icons' };

export type IconCategory = keyof typeof iconFolders;
export const iconSizeLimit = 256 * 1024;

export function isIconCategory(category: string): category is IconCategory {
  return Object.prototype.hasOwnProperty.call(iconFolders, category);
}

export function recordIconPath(category: IconCategory, id: string, extension: string): string {
  return `/${iconFolders[category]}/${id}.${extension}`;
}

export function isRecordIconPath(category: IconCategory, value: unknown): value is string {
  const prefix = `/${iconFolders[category]}/`;
  return typeof value === 'string' && value.startsWith(prefix) && /^[a-zA-Z0-9_-]+\.(png|webp)$/.test(value.slice(prefix.length));
}
