import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { promises as fs } from 'node:fs';
import path from 'node:path';

const DATA_ROOT = path.resolve(__dirname, '../data/admin');
const ICON_ROOT = path.resolve(__dirname, 'public/skill-icons');
const CATEGORIES = new Set(['tasks', 'skills', 'characters', 'jobs', 'equipment', 'items', 'stories', 'stages']);
function localDataApi(): Plugin {
  return {
    name: 'local-data-api',
    configureServer(server) {
      server.middlewares.use('/api/skill-icons', async (req, res) => {
        const send = (status: number, data: unknown) => { res.statusCode = status; res.setHeader('Content-Type', 'application/json; charset=utf-8'); res.end(JSON.stringify(data)); };
        const id = decodeURIComponent((req.url || '').split('?')[0].replace(/^\\//, ''));
        if (!/^[a-zA-Z0-9_-]+$/.test(id) || req.method !== 'PUT') return send(400, { error: 'Invalid icon id or method' });
        try {
          let raw = '';
          for await (const chunk of req) { raw += chunk.toString(); if (raw.length > 400_000) return send(413, { error: 'Icon too large (max 256KB)' }); }
          const payload = JSON.parse(raw) as { dataUrl?: string };
          const match = /^data:image\\/(png|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(payload.dataUrl || '');
          if (!match) return send(400, { error: 'PNG or WebP only' });
          const bytes = Buffer.from(match[2], 'base64');
          if (bytes.length > 256 * 1024 || bytes.length === 0) return send(413, { error: 'Icon must be 1-256KB' });
          const png = match[1] === 'png';
          if (png ? bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' : bytes.subarray(0, 4).toString() !== 'RIFF' || bytes.subarray(8, 12).toString() !== 'WEBP') return send(400, { error: 'Invalid image data' });
          await fs.mkdir(ICON_ROOT, { recursive: true });
          const ext = png ? 'png' : 'webp';
          await fs.writeFile(path.join(ICON_ROOT, id + '.' + ext), bytes);
          await fs.rm(path.join(ICON_ROOT, id + '.' + (png ? 'webp' : 'png')), { force: true });
          return send(200, { iconPath: '/skill-icons/' + id + '.' + ext });
        } catch (error) { return send(500, { error: String(error) }); }
      });
      server.middlewares.use('/api/data', async (req, res) => {
        const send = (status: number, payload: unknown) => {
          res.statusCode = status;
          res.setHeader('Content-Type', 'application/json; charset=utf-8');
          res.end(JSON.stringify(payload));
        };
        try {
          const parts = (req.url || '/').split('?')[0].split('/').filter(Boolean).map(decodeURIComponent);
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
            let raw = '';
            for await (const chunk of req) {
              raw += chunk.toString();
              if (raw.length > 1_000_000) return send(413, { error: 'Payload too large' });
            }
            const value: unknown = JSON.parse(raw);
            if (!value || Array.isArray(value) || typeof value !== 'object' || (value as { id?: unknown }).id !== id) {
              return send(400, { error: 'Object id must match filename' });
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
          send(code === 'ENOENT' ? 404 : error instanceof SyntaxError ? 400 : 500, { error: String(error) });
        }
      });
    }
  };
}
export default defineConfig({ plugins: [react(), localDataApi()], server: { host: '127.0.0.1' } });
