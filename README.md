# Adless

Monorepo do Adless: aplicativo iOS em SwiftUI, serviço DNS Cloudflare Worker e
landing page estática.

## Estrutura

```text
apps/ios/              # app SwiftUI e configuração DNS nativa do iOS
apps/dns-worker/       # endpoint RFC 8484 e contadores Durable Object
apps/landing-page/     # landing page React + Vite
tools/blocklists/      # geração e validação determinística
```

O app usa `NEDNSSettingsManager` com `NEDNSOverHTTPSSettings`. Ao tocar em
Ativar, ele salva a configuração para `https://adless-dns.adless-production.workers.dev/<token>/dns-query`;
o iOS pode exigir que o usuário habilite a configuração em Ajustes. Somente DNS
passa pelo serviço Adless. Sites, vídeos, mensagens e downloads continuam indo
diretamente aos destinos. Não há conta, login, backend de usuários ou proxy de
tráfego.

A cobrança continua exclusivamente pela App Store com StoreKit 2. Os produtos
são mensal e anual, com trial de sete dias configurado no App Store Connect.

## Desenvolvimento

Requer Node.js 20+, npm, Python 3 e Xcode.

```sh
npm ci
npm run dev:landing
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
npm run test:dns-worker
python3 -m unittest discover -s tools/blocklists/tests -v
```

Para o iOS, abra `apps/ios/Adless.xcodeproj`. Os schemes `Adless Dev` e
`Adless` diferenciam somente o identificador e o nome exibido; o target de
produção é `Adless`, acompanhado de `AdlessTests`.

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## DNS Cloud

O endpoint de produção é:

```text
https://adless-dns.adless-production.workers.dev/<installation-token>/dns-query
```

Ele aceita POST `application/dns-message` e GET RFC 8484 com `dns` em Base64URL.
O Worker normaliza a lista em memória, bloqueia na edge e consulta
`https://cloudflare-dns.com/dns-query` como principal e
`https://dns.quad9.net/dns-query` como fallback sequencial. Nenhuma consulta é
enviada em DNS sem criptografia.

```sh
npm --prefix apps/dns-worker run test
npm --prefix apps/dns-worker run prepare:blocklist
npx --yes wrangler@4 deploy --config apps/dns-worker/wrangler.toml
```

O deploy precisa de `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID` no ambiente
ou nos secrets do GitHub. O endpoint de estatísticas é `GET /v1/stats` com
`Authorization: Bearer <installation-token>` e retorna somente o total agregado.
Detalhes de DNS, blocklist, custos, secrets, rollback e incidentes estão em
[`docs/dns-cloud.md`](docs/dns-cloud.md).

## Blocklist

A fonte habilitada no MVP é a OISD Small. Os artefatos públicos continuam em
`apps/landing-page/public/blocklists/`, e a cópia gerada para o Worker fica em
`apps/dns-worker/data/`. O workflow semanal baixa, normaliza, aplica a allowlist,
valida, gera o pacote edge e só publica uma alteração válida. Uma lista vazia,
inválida ou com variação inesperada não substitui a versão anterior.

```sh
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

O checksum é derivado do conteúdo e `generatedAt` permanece estável quando não
há mudança real. A atribuição está em
[`THIRD_PARTY_BLOCKLISTS.md`](THIRD_PARTY_BLOCKLISTS.md).

## Publicação

`deploy-pages.yml` publica a landing page. `deploy-dns-worker.yml` publica o
Worker quando os secrets Cloudflare estão configurados. `testflight-ios.yml` e
`release-ios.yml` usam os secrets do App Store Connect documentados em
[`docs/ios-release.md`](docs/ios-release.md). Nenhum workflow faz push para
branches sem a finalidade específica de atualizar artefatos.
