# Instruções da landing page

Este escopo cobre `apps/landing-page/`; herda o [AGENTS.md da raiz](../../AGENTS.md).
O [README](README.md) é a fonte canônica de estrutura, rotas, comandos e
pendências de copy pública.

- A SPA React/Vite publica conteúdo e artefatos estáticos. Railway fica fora
  do caminho DNS; não acrescentar autenticação, pagamentos ou proxy na landing.
- Confira afirmações de produto contra iOS/Worker e as decisões de lançamento.
  Não prometer compra única, proteção de todos os apps, internet sem falhas,
  anonimato ou ausência de metadados sem evidência correspondente.
- Ao alterar conteúdo traduzido, manter EN/PT/ES em `src/i18n/translations.ts`.
  Revisar também rótulos acessíveis, páginas legais e metadados; não presumir
  que a tradução da home cobre esses textos.
- `public/` e valores `VITE_*` incorporados ao bundle são públicos. Nunca
  incluir tokens DNS/stats, JWS, credenciais Cloudflare/Railway/Apple ou secrets.
- Não editar `public/blocklists/` manualmente; seguir o
  [pipeline canônico](../../tools/blocklists/README.md). Reutilizar componentes,
  tokens de `src/index.css` e alias `@` antes de criar abstrações.
- Após mudanças funcionais, executar na raiz `npm run lint`, `npm run typecheck`
  e `npm run build:landing`, além da revisão manual das rotas/idiomas/temas.
  A landing não possui suíte unitária/E2E própria.
- Antes de mudar privacidade ou terceiros, revisar [SECURITY.md](../../docs/SECURITY.md).
  Publicação e mudanças Railway/domínio exigem autorização explícita.
