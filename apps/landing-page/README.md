# Adless landing page

Landing page do Adless, construída com Vite, React, TypeScript, shadcn/ui e Tailwind CSS.

Os comandos devem ser executados preferencialmente a partir da raiz do monorepo:

```sh
npm install
npm run dev:landing
```

Comandos disponíveis na raiz:

- `npm run dev:landing`: inicia o servidor de desenvolvimento.
- `npm run build:landing`: gera a build de produção.
- `npm run lint`: executa o ESLint.
- `npm run preview:landing`: serve a build localmente.

Também é possível executar os comandos diretamente neste workspace com `npm run dev`, `npm run build`, `npm run lint` e `npm run preview`.

## Arquivos públicos da blocklist

O diretório público real desta landing é `public/`. Por isso os artefatos da
blocklist ficam em `public/blocklists/` e entram na build estática sem serem
incluídos no bundle JavaScript. O workflow de GitHub Pages publica a pasta
`apps/landing-page/dist` em `https://andre-fig.github.io/adless/`.

URLs esperadas:

- `/blocklists/manifest.json` — manifesto curto, sujeito a revalidação;
- `/blocklists/blocklist.txt.gz` — payload utilizado pelo app;
- `/blocklists/blocklist.txt` — versão legível para inspeção.

ETag e Last-Modified ficam a cargo da hospedagem estática quando disponíveis.
