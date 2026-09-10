// Phase 7 Library persistence API. One catch-all handler over library-data/ on the local disk.
// Dev-only internal tool: no auth, runs on the machine that owns the repo.
import { NextRequest } from "next/server";
import {
  buildBackup, deleteAssetDir, deleteCharacterDir, readBinary, readIndex, readRegistry,
  writeAssetRecord, writeBinary, writeCharacterRecord, writeRegistry,
} from "@/features/library/server/store";
import { buildDependencyGraph, usageCount } from "@/domain/library-dependency";
import type { AssetRecord, CharacterRecord, RegistryFile } from "@/domain/library-index";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
const err = (message: string, status = 400) => json({ error: message }, status);

const FILE_TYPE: Record<string, string> = {
  "model.glb": "model/gltf-binary",
  "texture.png": "image/png",
  "thumbnail.png": "image/png",
};

async function segments(ctx: { params: Promise<{ path?: string[] }> }): Promise<string[]> {
  return (await ctx.params).path ?? [];
}

export async function GET(_req: NextRequest, ctx: { params: Promise<{ path?: string[] }> }) {
  const p = await segments(ctx);
  try {
    if (p.length === 0) return json(await readIndex());
    if (p.length === 1 && p[0] === "backup") return json(await buildBackup());
    if (p.length === 1 && p[0] === "registry") return json(await readRegistry());
    if (p.length === 4 && (p[0] === "asset" || p[0] === "character") && p[2] === "file") {
      const bytes = await readBinary(p[0], p[1], p[3]);
      if (!bytes) return err("Not found", 404);
      return new Response(new Uint8Array(bytes), {
        headers: { "content-type": FILE_TYPE[p[3]] ?? "application/octet-stream", "cache-control": "no-store" },
      });
    }
    return err("Unknown route", 404);
  } catch (e) {
    return err(e instanceof Error ? e.message : String(e), 500);
  }
}

export async function PUT(req: NextRequest, ctx: { params: Promise<{ path?: string[] }> }) {
  const p = await segments(ctx);
  try {
    if (p.length === 1 && p[0] === "registry") {
      const file = (await req.json()) as RegistryFile;
      await writeRegistry({ ...file, specVersion: 1, updatedAt: new Date().toISOString() });
      return json({ ok: true });
    }
    if (p.length === 4 && (p[0] === "asset" || p[0] === "character") && p[2] === "file") {
      const buf = Buffer.from(await req.arrayBuffer());
      if (buf.length === 0) return err("Empty body");
      await writeBinary(p[0], p[1], p[3], buf);
      return json({ ok: true, bytes: buf.length });
    }
    if (p.length === 2 && p[0] === "asset") {
      const rec = (await req.json()) as AssetRecord;
      if (rec.metadata?.id !== p[1]) return err("id mismatch");
      await writeAssetRecord(rec);
      return json({ ok: true });
    }
    if (p.length === 2 && p[0] === "character") {
      const rec = (await req.json()) as CharacterRecord;
      if (rec.recipe?.id !== p[1]) return err("id mismatch");
      await writeCharacterRecord(rec);
      return json({ ok: true });
    }
    return err("Unknown route", 404);
  } catch (e) {
    return err(e instanceof Error ? e.message : String(e), 500);
  }
}

export async function DELETE(req: NextRequest, ctx: { params: Promise<{ path?: string[] }> }) {
  const p = await segments(ctx);
  const force = req.nextUrl.searchParams.get("force") === "1";
  try {
    if (p.length === 2 && p[0] === "asset") {
      const index = await readIndex();
      const graph = buildDependencyGraph(index.characters, index.assets);
      const count = usageCount(graph, p[1]);
      if (count > 0 && !force) {
        return json({ error: "in_use", usedByCount: count, usedBy: graph.usedBy[p[1]] ?? [] }, 409);
      }
      await deleteAssetDir(p[1]);
      return json({ ok: true, forced: force && count > 0 });
    }
    if (p.length === 2 && p[0] === "character") {
      const index = await readIndex();
      const record = index.characters.find((c) => c.recipe.id === p[1]);
      if (record?.registry.status === "registered" && !force) {
        return json({ error: "registered", message: "Registry 登録中の Character です。" }, 409);
      }
      await deleteCharacterDir(p[1]);
      return json({ ok: true });
    }
    return err("Unknown route", 404);
  } catch (e) {
    return err(e instanceof Error ? e.message : String(e), 500);
  }
}
