import { useEffect, useState } from 'react';
import { iconSizeLimit, isRecordIconPath, type IconCategory } from './recordIcons';

export type PendingIcon = { file: File; extension: 'png' | 'webp' };

export default function RecordIconPicker({ category, label, path, pending, revision, onChange }: {
  category: IconCategory;
  label: string;
  path: unknown;
  pending: PendingIcon | null;
  revision: number;
  onChange: (icon: PendingIcon) => void;
}) {
  const [error, setError] = useState('');
  const [failedPreview, setFailedPreview] = useState('');
  const [localPreview, setLocalPreview] = useState('');
  useEffect(() => {
    if (!pending) return;
    const url = URL.createObjectURL(pending.file);
    setLocalPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [pending]);

  function select(file: File) {
    const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : null;
    if (!extension) { setError('PNGまたはWebPを選択してください'); return; }
    if (!file.size || file.size > iconSizeLimit) { setError('画像は空でなく、256KB以下にしてください'); return; }
    setError('');
    onChange({ file, extension });
  }

  const savedPath = isRecordIconPath(category, path) ? path : '';
  const preview = pending ? localPreview : savedPath ? `${savedPath}?v=${revision}` : '';
  const title = `${label}アイコン`;
  return <div className="skill-icon-picker">
    <div className="skill-icon-preview">
      {preview && preview !== failedPreview
        ? <img key={preview} src={preview} alt={title} onError={() => setFailedPreview(preview)} />
        : <span>{preview ? '表示できません' : '未登録'}</span>}
    </div>
    <div>
      <strong>{title}{category === 'skills' && '（必須）'}</strong>
      <p className="hint">PNG / WebP、256KB以下。選択後に「保存」で登録します。</p>
      <input aria-label={`${title}を選択`} type="file" accept="image/png,image/webp" onChange={e => {
        const file = e.currentTarget.files?.[0];
        if (file) select(file);
        e.currentTarget.value = '';
      }} />
      {error && <p role="alert" className="error">{error}</p>}
      <small>{pending ? '選択済み・未保存' : savedPath || '画像を選択してください'}</small>
    </div>
  </div>;
}
