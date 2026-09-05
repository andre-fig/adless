# Desenvolvimento e automação

Fonte canônica de setup, scripts e efeitos das ferramentas. Para arquitetura,
leia [ARCHITECTURE.md](ARCHITECTURE.md); a ordem completa de validação e cobertura
está em [TESTING.md](TESTING.md). Resultados datados ficam em
[REPOSITORY_AUDIT.md](REPOSITORY_AUDIT.md), sem transformar o estado local em remoto.

## Requisitos e instalação

- Node.js 20+ conforme [package.json](../package.json); npm declarado em
  `packageManager`. O lockfile da raiz é a referência para JavaScript.
- Python 3.12 é a versão declarada pelos workflows; o pipeline usa biblioteca
  padrão e não tem instalação pip.
- macOS/Xcode para build e XCTest do iOS; iPhone para DNS real. Schemes,
  configurações, assinatura e diferenças StoreKit pertencem ao
  [README iOS](../apps/ios/README.md).
- Credenciais Cloudflare, Railway e Apple não são requisito para lint,
  typecheck, testes mockados e build de simulador sem assinatura.

Em setup autorizado de uma cópia de trabalho:

```sh
npm ci
```

Esse comando instala dependências e executa `prepare`, que chama
[install-git-hooks.sh](../tools/dev/install-git-hooks.sh) e escreve
`core.hooksPath=.githooks` na configuração Git local. O script pula essa escrita
se `CI=true`. `npm run setup:hooks` faz a mesma configuração explicitamente.
Não executar instalação ou configuração de hooks numa tarefa restrita a
Markdown. `npm install` pode modificar o lockfile; não usá-lo como substituto
silencioso do setup reproduzível.

A raiz declara somente `apps/landing-page` como workspace. Os scripts do Worker
usam `npm --prefix apps/dns-worker` e compilador de `node_modules` da raiz; o
Worker não é um segundo workspace. As dependências JWS/X.509 também estão no
`package.json` da raiz. Não deduzir que o pacote do Worker se instala sozinho.

## Comandos e efeitos locais

Comandos abaixo partem da raiz. **Implemented:** nomes e encaminhamentos
confirmados nos arquivos `package.json`.

| Comando | Escopo e efeito |
| --- | --- |
| `npm run dev:landing` | Servidor Vite local da landing |
| `npm run lint` | ESLint somente da landing, sem `--fix` |
| `npm run typecheck` | TypeScript app e ferramentas da landing, `--noEmit` |
| `npm run build` / `npm run build:landing` | Build Vite da landing; gera `apps/landing-page/dist/` |
| `npm run preview:landing` | Serve a build existente da landing |
| `npm run build:dns-worker` | TypeScript do Worker com `noEmit`; não cria bundle de deploy nem publica |
| `npm run test:dns-worker` | Compila testes em `apps/dns-worker/dist-test/` e usa `node --test` |
| `npm run prepare:dns-blocklist` | Regrava texto/metadata da blocklist no Worker |
| `python3 -B -m unittest discover -s tools/blocklists/tests -v` | Testes Python, temporários fora do repositório; `-B` evita bytecode |
| `python3 -B tools/blocklists/validate_blocklist.py` | Lê e valida artefatos existentes, sem regenerar |

Não há `npm test` na raiz, suíte automatizada da landing nem comando npm para
XCTest. Não usar `npm run build` como prova de compilação de todo o monorepo.
O gerador de blocklist acessa a rede e altera artefatos; comandos e limites
estão no [pipeline](../tools/blocklists/README.md). Build/archive/export Xcode
produzem arquivos e podem acessar a rede; `-allowProvisioningUpdates` também
pode alterar profiles remotos, exigindo autorização para essa operação.

## Hooks existentes

[common.sh](../.githooks/common.sh) contém os checks chamados pelos hooks.
Eles ajudam o desenvolvimento local, mas não constituem a CI inteira.

| Hook | O que realmente executa |
| --- | --- |
| [pre-commit](../.githooks/pre-commit) | `git diff --cached --check`; actionlint ao tocar workflows; sintaxe Python em blocklists/appstore/dns-worker; lint quando landing ou pacote/lock da raiz entra no stage |
| [pre-push](../.githooks/pre-push) | Testes Python blocklists; testes/build Worker; typecheck/build landing; XCTest para iOS; testes offline de distribuição/allowlist e actionlint para workflows/scripts/exports/hooks; lockfile seleciona Worker e landing |

O pre-push escolhe o primeiro simulador iPhone disponível e usa DerivedData
em diretório temporário. Num ref remoto novo, inspeciona todos os caminhos da
árvore. Alterações de Markdown dentro de aplicações podem selecionar checks
pelo caminho mesmo sem mudança de código. Os checks leem o working tree,
não uma cópia isolada do conteúdo staged: preserve e relate alterações locais.

**Pending:** pre-commit não cobre sintaxe de todos os scripts Python/shell;
pre-push não inclui lint da landing nem verifica IPA/archive, e
mudanças só em `tools/blocklists` não selecionam automaticamente a suíte Worker.
Seguir [TESTING.md](TESTING.md) para dependências entre áreas. Não rodar hooks
via commit/push apenas para validar: chamar os comandos relevantes diretamente.

## Workflows declarados e limites

**Implemented:** todos os cinco workflows têm `concurrency`,
`cancel-in-progress`, timeout e permissões de conteúdo explícitas. Quatro usam
`contents: read`; atualização de blocklist usa `contents: write`.
Não há `pull_request` nem job de testes geral nesses arquivos. Os YAMLs não
referenciam GitHub Environments com aprovação; proteções e secrets remotos
permanecem **Pending** até inspeção autorizada do estado remoto.

| Workflow | Gatilho declarado | Ação e lacuna observável |
| --- | --- | --- |
| [deploy-dns-worker.yml](../.github/workflows/deploy-dns-worker.yml) | `main` com filtros de caminho; manual | Prepara/valida lista, compila e publica Worker. Não executa suíte Worker nem smoke após deploy. Filtros não incluem pacote/lock da raiz. Runbook: [dns-cloud.md](dns-cloud.md). |
| [deploy-landing.yml](../.github/workflows/deploy-landing.yml) | `main` com filtros de caminho; manual | Build e envio Railway, sem lint/typecheck/smoke. Filtros não incluem pacote da raiz, Tailwind, PostCSS nem todos os assets públicos. CLI recebe `apps/landing-page --path-as-root`; confirmar ambiente de instalação remoto separadamente. |
| [update-blocklist.yml](../.github/workflows/update-blocklist.yml) | Domingo 03:17 UTC; manual | Testa/gera/valida e faz commit/push de seis artefatos; não publica Worker ou Railway diretamente. |
| Xcode Cloud | `develop`, `beta` e `main`, configurados no App Store Connect | `develop`: TestFlight interno. `beta`: TestFlight externo com beta review. `main`: App Store com liberação após aprovação. |

Os dois workflows iOS usam o scheme `Adless`, não `Adless Dev`; detalhes,
comandos App Store Connect e diferenças entre upload/revisão/disponibilidade
estão em [ios-release.md](ios-release.md). `tools/appstore/appstore_connect.py`
possui comandos que escrevem no App Store Connect; `tools/sentry/upload-dsyms.sh`
envia dados remotamente. Não chamar esses scripts como smoke local genérico.

**Pending:** o workflow da blocklist usa checkout sem token alternativo e não
faz dispatch dos deploys. Com `GITHUB_TOKEN`, o push do workflow não dispara
novos workflows de `push`; portanto commit gerado não comprova atualização da
edge/site. Confirmar execução e deployment separadamente, conforme a
[documentação oficial de gatilhos GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

Não disparar workflows, deploy, upload, submissão, commit ou push sem
explicitamente autorizar seus efeitos. Um futuro push autorizado a `main` ou
`develop` pode acionar publicação conforme os filtros acima; revisar isso antes
da operação. Datas de execução, IDs de deployment e verificações de secrets
não devem ser inferidos da existência do YAML.
