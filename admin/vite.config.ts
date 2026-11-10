import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { promises as fs } from 'node:fs';
import path from 'node:path';

const DATA_ROOT = path.resolve(__dirname, '../data/admin');
const CATEGORIES = new Set(['tasks', 'skills', 'characters', 'jobs', 'equipment', 'items', 'stories', 'stages']);
function localDataApi(): Plugin {
  return {
    name: 'local-data-api',
    configureServer(server) {
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
