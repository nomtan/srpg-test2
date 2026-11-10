import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { validateJob } from './src/jobData';
import { iconSizeLimit, isIconCategory, isRecordIconPath, recordIconPath } from './src/recordIcons';

const DATA_ROOT = path.resolve(__dirname, '../data/admin');
const PUBLIC_ROOT = path.resolve(__dirname, 'public');
const CATEGORIES = new Set(['tasks', 'skills', 'characters', 'jobs', 'equipment', 'items', 'stories', 'stages']);
function decodeIcon(value: unknown): { status: number; error: string } | { extension: 'png' | 'webp'; bytes: Buffer } {
  const match = typeof value === 'string' && /^data:image\/(png|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(value);
  if (!match) return { status: 400, error: 'PNGまたはWebPを選択してください' } as const;
  const bytes = Buffer.from(match[2], 'base64');
  if (!bytes.length || bytes.length > iconSizeLimit) return { status: 413, error: '画像は空でなく、256KB以下にしてください' } as const;
  const extension = match[1] === 'png' ? 'png' : 'webp';
  const valid = extension === 'png'
    ? bytes.subarray(0, 8).toString('hex') === '89504e470d0a1a0a'
    : bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP';
  if (!valid) return { status: 400, error: '画像データが無効です' } as const;
  return { extension, bytes } as const;
}

async function writeIcon(iconPath: string, bytes: Buffer) {
  const filename = path.join(PUBLIC_ROOT, iconPath);
  await fs.mkdir(path.dirname(filename), { recursive: true });
  await fs.writeFile(filename, bytes);
}

function localDataApi(): Plugin {
  return {
    name: 'local-data-api',
    configureServer(server) {
      server.middlewares.use('/api/skill-icons', async (req, res) => {
        const send = (status: number, data: unknown) => { res.statusCode = status; res.setHeader('Content-Type', 'application/json; charset=utf-8'); res.end(JSON.stringify(data)); };
        try {
          const id = decodeURIComponent((req.url || '').split('?')[0].replace(/^\//, ''));
          if (!/^[a-zA-Z0-9_-]+$/.test(id) || req.method !== 'PUT') return send(400, { error: 'Invalid icon id or method' });
          let raw = '';
          for await (const chunk of req) { raw += chunk.toString(); if (raw.length > 400_000) return send(413, { error: 'Icon too large (max 256KB)' }); }
          const icon = decodeIcon(JSON.parse(raw)?.dataUrl);
          if ('error' in icon) return send(icon.status, { error: icon.error });
          const iconPath = recordIconPath('skills', id, icon.extension);
          await writeIcon(iconPath, icon.bytes);
          await fs.rm(path.join(PUBLIC_ROOT, recordIconPath('skills', id, icon.extension === 'png' ? 'webp' : 'png')), { force: true });
          return send(200, { iconPath });
        } catch (error) {
          return send(error instanceof SyntaxError || error instanceof URIError ? 400 : 500, { error: String(error) });
        }
      });
      server.middlewares.use('/api/data', async (req, res) => {
        const send = (status: number, payload: unknown) => {
          res.statusCode = status;
          res.setHeader('Content-Type', 'application/json; charset=utf-8');
          res.end(JSON.stringify(payload));
        };
        try {
          const [pathname, query] = (req.url || '/').split('?');
          const withIcon = new URLSearchParams(query).get('withIcon') === '1';
          const parts = pathname.split('/').filter(Boolean).map(decodeURIComponent);
          const [category, id, ...rest] = parts;
          if (!category || !CATEGORIES.has(category) || rest.length || (id && !/^[a-zA-Z0-9_-]+$/.test(id))) {
            return send(400, { error: 'Invalid category or id' });
          }
          const dir = path.join(DATA_ROOT, category);
          if (req.method === 'GET' && !id) {
            await fs.mkdir(dir, { recursive: true });
            const names = (await fs.readdir(dir)).filter(name => /^[a-zA-Z0-9_-]+\.json$/.test(name));
            const records = await Promise.all(names.map(async name => JSON.parse(await fs.readFile(path.join(dir, name), 'utf8'))));
            return send(200, records);
          }
          if (!id) return send(400, { error: 'Record id required' });
          const filename = path.join(dir, id + '.json');
          if (req.method === 'GET') return send(200, JSON.parse(await fs.readFile(filename, 'utf8')));
          if (req.method === 'PUT') {
            if (withIcon && !isIconCategory(category)) return send(400, { error: 'このカテゴリには画像を登録できません' });
            let raw = '';
            const limit = withIcon ? 1_400_000 : 1_000_000;
            for await (const chunk of req) {
              raw += chunk.toString();
              if (raw.length > limit) return send(413, { error: 'Payload too large' });
            }
            const payload = JSON.parse(raw);
            const value: Record<string, unknown> = withIcon ? payload?.record : payload;
            if (!value || Array.isArray(value) || typeof value !== 'object' || value.id !== id) {
              return send(400, { error: 'Object id must match filename' });
            }
            if (category === 'jobs') {
              const error = validateJob(value as Record<string, unknown>);
              if (error) return send(400, { error });
            }
            if (isIconCategory(category)) {
              if (withIcon) {
                const icon = decodeIcon(payload.iconDataUrl);
                if ('error' in icon) return send(icon.status, { error: icon.error });
                const iconPath = recordIconPath(category, id, icon.extension);
                await writeIcon(iconPath, icon.bytes);
                value.iconPath = iconPath;
              } else if (value.iconPath !== undefined && value.iconPath !== '' && !isRecordIconPath(category, value.iconPath)) {
                return send(400, { error: 'アイコンのパスが不正です' });
              }
            }
            await fs.mkdir(dir, { recursive: true });
            await fs.writeFile(filename, JSON.stringify(value, null, 2) + '\n');
            return send(200, value);
          }
          if (req.method === 'DELETE') {
            await fs.unlink(filename);
            return send(200, { ok: true });
          }
          send(405, { error: 'Method not allowed' });
        } catch (error) {
          const code = (error as NodeJS.ErrnoException).code;
          send(code === 'ENOENT' ? 404 : error instanceof SyntaxError || error instanceof URIError ? 400 : 500, { error: String(error) });
        }
      });
    }
  };
}
export default defineConfig({ plugins: [react(), localDataApi()], server: { host: '127.0.0.1' } });
