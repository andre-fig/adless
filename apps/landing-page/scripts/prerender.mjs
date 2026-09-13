import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { renderPage } from "../dist-ssr/entry-server.js";

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const distDir = path.join(projectDir, "dist");
const template = await readFile(path.join(distDir, "index.html"), "utf8");

const pages = [
  { url: "/", language: "en", output: "index.html" },
  { url: "/en/", language: "en", output: "en/index.html" },
  { url: "/pt-br/", language: "pt", output: "pt-br/index.html" },
  { url: "/es/", language: "es", output: "es/index.html" },
  { url: "/en/privacy", language: "en", output: "en/privacy/index.html" },
  { url: "/en/terms", language: "en", output: "en/terms/index.html" },
  { url: "/en/support", language: "en", output: "en/support/index.html" },
  { url: "/pt-br/privacy", language: "pt", output: "pt-br/privacy/index.html" },
  { url: "/pt-br/terms", language: "pt", output: "pt-br/terms/index.html" },
  { url: "/pt-br/support", language: "pt", output: "pt-br/support/index.html" },
  { url: "/es/privacy", language: "es", output: "es/privacy/index.html" },
  { url: "/es/terms", language: "es", output: "es/terms/index.html" },
  { url: "/es/support", language: "es", output: "es/support/index.html" },
  { url: "/privacy", language: "en", output: "privacy/index.html" },
  { url: "/terms", language: "en", output: "terms/index.html" },
  { url: "/support", language: "en", output: "support/index.html" },
  { url: "/not-found", language: "en", output: "404.html" },
];

for (const page of pages) {
  const { appHtml, headHtml, htmlAttributes } = renderPage(page.url, page.language);
  const html = template
    .replace(/<html[^>]*>/, `<html ${htmlAttributes}>`)
    .replace("<!--app-head-->", headHtml)
    .replace('<div id="root"></div>', `<div id="root">${appHtml}</div>`);
  const outputPath = path.join(distDir, page.output);

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, html);
}
