import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

const source = readFileSync(new URL('../src/i18n/translations.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.ESNext}}).outputText;
const {legalDocuments, legalUi} = await import('data:text/javascript;base64,' + Buffer.from(compiled).toString('base64'));

for (const lang of ['en', 'pt', 'es']) {
  for (const page of ['privacy', 'terms', 'support']) {
    test(`${lang}/${page}: complete translated document`, () => {
      const document = legalDocuments[lang][page];
      const original = legalDocuments.en[page];
      assert.ok(document.title && document.intro);
      assert.equal(document.sections.length, original.sections.length);
      document.sections.forEach((section, index) => {
        assert.ok(section.title);
        assert.equal(section.paragraphs.length, original.sections[index].paragraphs.length);
        assert.equal(section.steps.length, original.sections[index].steps.length);
        for (const text of [...section.paragraphs, ...section.steps]) {
          assert.ok(text.trim().length > 0);
        }
        if (lang !== 'en') assert.notEqual(section.title, original.sections[index].title);
      });
      assert.ok(JSON.stringify(document).includes('a_figueiredo@icloud.com'));
    });
  }
  test(`${lang}: localized controls and preserved privacy disclosures`, () => {
    assert.deepEqual(Object.keys(legalUi[lang]).sort(), Object.keys(legalUi.en).sort());
    for (const value of Object.values(legalUi[lang])) assert.ok(value.length > 0);
    const privacy = JSON.stringify(legalDocuments[lang].privacy);
    for (const disclosure of ['Cloudflare', 'Quad9', 'Sentry', 'Keychain', 'Railway', 'DNS', 'token']) {
      assert.ok(privacy.includes(disclosure));
    }
    assert.ok(JSON.stringify(legalDocuments[lang].terms).includes('24'));
  });
}
