// Resolver hook so the headless verify scripts can import the app's TypeScript domain modules
// directly: maps the "@/..." path alias onto src/ and fills in the omitted .ts extension.
// Node's built-in type stripping handles the TypeScript itself.
const SRC = new URL("../src/", import.meta.url).href;

export async function resolve(specifier, context, nextResolve) {
  let spec = specifier;
  if (spec.startsWith("@/")) spec = SRC + spec.slice(2);
  if ((spec.startsWith(".") || spec.startsWith("file:")) && !/\.[a-z]+$/i.test(spec)) {
    try { return await nextResolve(`${spec}.ts`, context); } catch { /* fall through */ }
    // Bundler-style directory import ("@/prompt/templates" -> templates/index.ts).
    try { return await nextResolve(`${spec}/index.ts`, context); } catch { /* fall through */ }
  }
  // The app imports generated JSON the bundler way (no import attribute); Node's ESM loader
  // requires one, so supply it here instead of littering the source with bundler-specific syntax.
  if (spec.endsWith(".json")) {
    const resolved = await nextResolve(spec, { ...context, importAttributes: { type: "json" } });
    return { ...resolved, importAttributes: { type: "json" } };
  }
  return nextResolve(spec, context);
}
