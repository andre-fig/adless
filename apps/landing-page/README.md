# Landing page Adless

Fonte canônica para o site público. Leia também as [instruções deste escopo](AGENTS.md).
**Implemented** significa confirmado no código local; não comprova qual revisão
está publicada. Evidências remotas ficam no [relatório da auditoria](../../docs/REPOSITORY_AUDIT.md).

## Estrutura e execução

React 18, TypeScript, Vite com SWC, Tailwind e componentes shadcn/ui/Radix.
O único workspace npm da raiz é `@adless/landing-page`.

| Arquivo | Responsabilidade implementada |
| --- | --- |
| [src/main.tsx](src/main.tsx), [src/App.tsx](src/App.tsx) | Hidratação, providers de tema/idioma/Helmet/React Query, toasts e roteamento localizado |
| [src/entry-server.tsx](src/entry-server.tsx), [scripts/prerender.mjs](scripts/prerender.mjs) | Prerender das páginas públicas com HTML e metadados completos |
| [src/pages/Index.tsx](src/pages/Index.tsx) | Seções da home e metadados localizados com canonical absoluto |
| [src/pages/PrivacyPolicy.tsx](src/pages/PrivacyPolicy.tsx), [Terms.tsx](src/pages/Terms.tsx), [Support.tsx](src/pages/Support.tsx) | Conteúdo público legal e de suporte em EN/PT/ES; layout editorial compartilhado, índice responsivo e metadados localizados |
| [src/i18n/LanguageContext.tsx](src/i18n/LanguageContext.tsx), [translations.ts](src/i18n/translations.ts) | EN/PT/ES definidos pela URL; seleção persiste `adless-language` no navegador |
| [src/components/ThemeProvider.tsx](src/components/ThemeProvider.tsx), [ThemeToggle.tsx](src/components/ThemeToggle.tsx) | Tema do sistema/claro/escuro via next-themes |
| [src/components/ui](src/components/ui) | Primitivos reutilizáveis; presença no diretório não implica uso nas páginas |
| [src/index.css](src/index.css), [tailwind.config.ts](tailwind.config.ts) | Tokens visuais, animações e estilos; CSS importa Inter do Google Fonts |
| [vite.config.ts](vite.config.ts) | Base `/`, alias `@` para `src`, dev em porta 8080; tagger apenas no modo development |

Rotas em `App`: `/`, homes `/en/`, `/pt-br/`, `/es/`, páginas legais sob
cada prefixo de idioma, aliases legais sem prefixo e fallback `*`. O build gera
HTML para cada rota pública, além de `404.html`.
Não há endpoint backend, fluxo de login ou chamada à API de autorização/DNS
no código da landing. React Query está instalado e tem provider; isso não
comprova uma integração com dados remotos.

Execute da raiz, com dependências já instaladas:

```sh
npm run dev:landing
npm run lint
npm run typecheck
npm run build:landing
npm run preview:landing
```

Setup e efeitos de `npm ci`/hooks estão em [DEVELOPMENT.md](../../docs/DEVELOPMENT.md).
Dentro deste workspace existem `dev`, `build`, `build:dev`, `lint`, `typecheck`,
`typecheck:app`, `typecheck:node`, `preview` e `start`. `build` gera `dist/` e
o bundle temporário `dist-ssr/`; `start` usa `serve --listen $PORT dist` para
preservar páginas estáticas e respostas 404 reais. A landing tem testes de
integração das traduções legais, mas não possui suíte E2E. A validação manual deve cobrir navegação
direta/reload de cada rota, EN/PT/ES, temas, layout móvel, teclado e links.

O ESLint é flat e type-aware; os projetos TypeScript de app e ferramentas
usam `strict`. `react-refresh/only-export-components` é aviso, não uma dispensa
de revisão. Resultados e contagens de avisos pertencem ao relatório de validação.

## Hospedagem e arquivos públicos

**Implemented:** o serviço Railway de produção está conectado diretamente ao
repositório GitHub `andre-fig/adless`, branch `main`, usando
`apps/landing-page` como raiz do serviço. O Railway publica novas versões após
pushes nessa branch. O destino público referenciado pelo repositório é
[landing-production-9feb.up.railway.app](https://landing-production-9feb.up.railway.app/).
**Pending:** revisão publicada, configuração da hospedagem, retenção de logs,
cabeçalhos e permissões remotas precisam de evidência própria.

Os quatro artefatos em [public/blocklists](public/blocklists) são copiados à
build como arquivos estáticos: `manifest.json`, `blocklist.txt.gz`,
`blocklist.txt` e `blocklist.sha256`. O [pipeline](../../tools/blocklists/README.md)
é sua fonte canônica. O iOS atual não baixa essa lista: o Worker recebe a cópia
no bundle. Railway permanece fora do caminho das consultas DNS.
ETag, Last-Modified e cache do host precisam de verificação remota.

## Pendências verificáveis no conteúdo público

Estes problemas de conteúdo permanecem no código e exigem tarefa própria. Não
usar a copy pública como especificação técnica.

| Estado | Evidência local e ação necessária |
| --- | --- |
| **Pending** | [Comparison.tsx](src/components/Comparison.tsx) marca `oneTimePurchase` como verdadeiro em EN/PT/ES, mas `Terms` e o [SubscriptionManager iOS](../ios/Adless/Services/SubscriptionManager.swift) usam assinaturas mensal/anual. Alinhar os textos ao modelo real. |
| **Pending** | `PrivacyPolicy` diz que o serviço guarda somente total agregado. O [authorization.ts](../dns-worker/src/authorization.ts) também grava registros de autorização/assinatura no KV. Revisar descrição de dados, vínculo por hashes e retenção conforme a [segurança](../../docs/SECURITY.md). |
| **Pending** | `PrivacyPolicy` atribui ao app download de blocklists do Railway, ausente no iOS atual. Corrigir a responsabilidade descrita. |
| **Pending** | A política diz que nomes bloqueados nunca seguem ao resolver; o Worker faz pass-through sem bloqueio para instalação conhecida sem assinatura válida. Descrever esse estado. |
| **Pending** | `translations` promete funcionamento em todos os apps e sem quebra; `Comparison` afirma diferenças genéricas contra “Others” sem evidência no repositório. Compatibilizar com limitações reais de DNS e evitar garantia absoluta. |
| **Implemented / Pending** | Homes e páginas legais/suporte têm URLs, `html.lang` e conteúdo próprios em EN/PT-BR/ES. A página 404 e alguns rótulos ainda precisam de localização. |
| **Pending** | `index.css` usa Google Fonts. Revisar terceiros e descrição da privacidade do site; não inferir ausência de conexões externas. |
| **Pending** | `Support` usa “VPN & Network” e simplifica ativação; validar instruções contra o [tutorial iOS](../ios/README.md) e a versão/idioma do aparelho. |

Links para a App Store em `Hero` e `CTA` comprovam somente a URL configurada;
disponibilidade pública do app depende das etapas de [lançamento Apple](../../docs/ios-release.md).


## Validação da integração legal

Execute `node --test apps/landing-page/tests/legal-translations.test.mjs` da raiz:
12 testes verificam cobertura de seções, parágrafos, passos, controles e menções
dos terceiros nos três idiomas. O texto inglês foi preservado integralmente;
as pendências de revisão factual da política listadas acima não foram resolvidas
por esta alteração visual e de tradução.

Lint, TypeScript e build foram executados com sucesso nesta alteração; lint
apresentou oito avisos preexistentes de Fast Refresh, sem erros.
**Pending:** revisão visual completa em dispositivos reais, claro/escuro, teclado
e persistência de preferências. A navegação local, hidratação, rotas localizadas,
sitemap e resposta 404 foram verificadas no servidor de produção local.
