import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";

const source = readFileSync(new URL("../src/lib/site.ts", import.meta.url), "utf8")
  .replace('import type { Language } from "@/i18n/translations";\n', "");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext },
}).outputText;
const { localizedPathForLanguage } = await import(
  `data:text/javascript;base64,${Buffer.from(compiled).toString("base64")}`
);

test("preserves landing-page routes when changing language", () => {
  assert.equal(localizedPathForLanguage("pt", "/en/privacy"), "/pt-br/privacy");
  assert.equal(localizedPathForLanguage("es", "/pt-br/terms/"), "/es/terms/");
  assert.equal(localizedPathForLanguage("en", "/es/support"), "/en/support");
});

test("preserves unknown routes and handles home routes", () => {
  assert.equal(localizedPathForLanguage("es", "/pt-br/pagina-inexistente"), "/es/pagina-inexistente");
  assert.equal(localizedPathForLanguage("pt", "/en/"), "/pt-br/");
  assert.equal(localizedPathForLanguage("en", "/"), "/en/");
});
