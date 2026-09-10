"use client";

// Bridge from Character Builder (Phase 5) to the Phase 7 Character Library (spec prompt 30, 37).
import { useMemo, useState } from "react";
import type { CharacterRecipe } from "@/domain/character-recipe";
import { useLibraryIndex, refreshLibrary } from "./use-library-index";
import { saveCharacter } from "./mutations";

export function BuilderLibrarySave({ recipe, name, thumbnail }: {
  recipe: CharacterRecipe;
  name: string;
  thumbnail: string | null;
}) {
  const { index } = useLibraryIndex();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const existing = useMemo(
    () => index.characters.find((c) => c.recipe.id === recipe.id) ?? null,
    [index.characters, recipe.id],
  );

  async function save() {
    if (!recipe.id) { setMsg("Character ID を入力してください。"); return; }
    setBusy(true); setMsg(null);
    try {
      const rec = await saveCharacter(recipe, name, index, "builder", thumbnail);
      await refreshLibrary();
      setMsg(existing
        ? `Update Existing: ${rec.recipe.id} を Character Library に保存しました（v${rec.recipe.characterVersion}）。`
        : `Create New: ${rec.recipe.id} を Character Library に登録しました。`);
    } catch (e) {
      setMsg(`保存失敗: ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(false); }
  }

  return (
    <div className="control-block recipe-actions">
      <h2>Character Library</h2>
      <button type="button" disabled={busy} onClick={save}>
        {existing ? "Update in Character Library" : "Save to Character Library"}
      </button>
      {msg && <p className="save-msg">{msg}</p>}
      <p className="muted">
        Recipe を <code>library-data/characters/&lt;id&gt;/</code> に保存します。Re-export / Registry 登録は Character Library で行います。
      </p>
    </div>
  );
}
