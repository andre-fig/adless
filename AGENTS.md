# Instruções do monorepo Adless

Preserve alterações existentes, mantenha o escopo e não introduza serviços,
contas, login ou banco fora da arquitetura descrita aqui. Antes de editar,
execute `git status --short --branch`; nunca use comandos destrutivos e nunca
faça commit ou push sem autorização explícita.

## Arquitetura

```text
apps/
├── ios/           # app SwiftUI com DNS nativo da Apple
├── dns-worker/    # Cloudflare Worker RFC 8484 e Durable Object de métricas
└── landing-page/  # React + Vite

tools/blocklists/  # fontes, gerador, validador, fixtures e testes Python
tools/dns-worker/  # preparação determinística da lista para a edge
```

O iOS usa somente `NEDNSSettingsManager` e
`NEDNSOverHTTPSSettings`. O Xcode contém apenas `Adless` e `AdlessTests`; não
há extensão, interface de rede, rota, App Group ou configuração gerida. O
endpoint DoH de produção é
`https://adless-dns.adless-production.workers.dev/<installation-token>/dns-query`.

O Worker bloqueia na edge e envia nomes permitidos para Cloudflare DoH, com
Quad9 como fallback sequencial. Somente DNS passa por essa infraestrutura;
tráfego geral segue diretamente do iPhone.

## Comandos principais

```sh
npm ci
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
npm run test:dns-worker
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

Build de simulador sem assinatura:

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

A interceptação real do DNS deve ser validada em iPhone. O simulador serve para
build, UI e testes unitários.

## Blocklist

A fonte habilitada no MVP é OISD Small, declarada em
`tools/blocklists/sources.json`. A allowlist é aplicada pelo gerador. Os
artefatos públicos ficam em `apps/landing-page/public/blocklists/`; a cópia
embutida no Worker fica em `apps/dns-worker/data/`. O gerador é a única fonte
autorizada para atualizar esses arquivos.

O manifesto publicado é
`https://landing-production-9feb.up.railway.app/blocklists/manifest.json`. Rejeite lista
vazia, inválida ou alteração acima do limite sem revisão explícita. Preserve a
versão anterior para rollback e registre somente versão, contagem e checksum.

## iOS, assinatura e privacidade

O App ID de produção é `com.orbeworks.adless`; o de desenvolvimento é
`com.orbeworks.adless.dev`. A capability necessária é
`com.apple.developer.networking.networkextension = dns-settings`. Profiles de
desenvolvimento/distribuição devem ser regenerados no Apple Developer portal.

`isEnabled` é somente leitura: salvar a configuração não substitui a aprovação
do usuário em Ajustes. O app lê o estado real ao voltar ao primeiro plano, trata
remoção manual e desativa a configuração quando a assinatura StoreKit expira.

O token por instalação tem 256 bits aleatórios, fica no Keychain
`ThisDeviceOnly` e não é derivado de IDFA, IDFV, Apple Account ou hardware. Não
registre token, QNAME, payload DNS, IP ou URL completa. Stats registram apenas
incrementos numéricos por token no Durable Object; a UI mantém o último total
conhecido quando a API falhar.

## Workflows

Todos os workflows devem manter `concurrency`, timeout, permissões mínimas,
actions atuais e secrets mínimos. O workflow de blocklist só publica arquivos
gerados esperados. O deploy do Worker exige os secrets
`CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID`. iOS usa apenas
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` e, opcionalmente, os secrets
do Sentry já documentados. Nunca coloque secrets no app ou no repositório.

## Checklist de entrega

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run test:dns-worker
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
git status --short --branch
```

Para iOS, acrescente XCTest, build/archive e
`sh tools/ios/verify_archive.sh <archive>`. Após exportar, execute
`sh tools/ios/verify_ipa.sh <ipa>` e confirme que há somente `Adless.app`, o
entitlement `dns-settings` e nenhuma extensão embutida. Consulte
`docs/ARCHITECTURE.md`, `docs/dns-cloud.md`, `docs/TESTING.md` e
`docs/ios-release.md` antes de alterar o caminho de rede ou publicação.
