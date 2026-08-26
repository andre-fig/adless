# Adless

Monorepo do Adless, com o aplicativo iOS e sua landing page no mesmo repositório.

## Estrutura

```text
apps/
├── ios/            # Aplicativo iOS em SwiftUI + NetworkExtension
└── landing-page/   # Landing page em React + Vite
```

## Landing page

Requer Node.js 20+ e npm.

```sh
npm install
npm run dev:landing
```

Outros comandos úteis:

```sh
npm run build:landing
npm run lint
npm run typecheck
npm run preview:landing
npm run setup:hooks
```

`npm install` e `npm ci` ativam automaticamente os hooks locais versionados em
`.githooks/`; `npm run setup:hooks` continua disponível para reativá-los
manualmente. O
`pre-commit` executa somente verificações rápidas nos arquivos staged. O
`pre-push` roda apenas os testes relacionados aos caminhos que serão enviados:
blocklist, lint/typecheck/build da landing ou XCTest do iOS. Isso antecipa
falhas antes de consumir um runner do GitHub; os workflows continuam sendo a
validação final.

## Aplicativo iOS

Abra `apps/ios/Adless.xcodeproj` no Xcode. Para desenvolvimento local, execute
o scheme `Adless Dev`, que usa os IDs e o App Group de desenvolvimento e pode
coexistir com o app oficial. Para TestFlight/App Store, execute o scheme
`Adless`, que usa exclusivamente o App Group
`group.com.orbeworks.adless` para os targets `Adless` e `AdlessDNSProxy`. O
target `AdlessDNSProxy` precisa da capability
Network Extension (DNS Proxy) no App ID correspondente.

A cobrança é feita exclusivamente pela App Store com StoreKit 2, sem backend,
login ou banco próprio. O app oferece assinaturas mensal e anual com trial de
7 dias configurado no App Store Connect.

### DNS criptografado

O bloqueio continua local: consultas bloqueadas recebem uma resposta local e
não saem do aparelho. Consultas permitidas são encaminhadas pela extensão por
DNS-over-HTTPS (DoH), usando HTTPS/TLS válido, para o Cloudflare DNS como
principal (`https://cloudflare-dns.com/dns-query`) e Quad9 como fallback
(`https://dns.quad9.net/dns-query`). O app não possui servidor próprio, não
envia métricas ou logs e nunca faz fallback silencioso para DNS UDP em texto
puro. Uma única sessão HTTPS é reutilizada durante a vida do provider; após
falhas consecutivas do primário, um circuit breaker usa temporariamente o
fallback e é resetado quando a rede muda. A política e os testes estão detalhados em
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) e
[`docs/TESTING.md`](docs/TESTING.md).

## Blocklist

A blocklist é gerada sem backend pelo workflow diário
`.github/workflows/update-blocklist.yml`. A fonte habilitada no MVP é somente a
OISD Small; atribuição e licença estão em
[THIRD_PARTY_BLOCKLISTS.md](THIRD_PARTY_BLOCKLISTS.md).

Os artefatos públicos ficam em `apps/landing-page/public/blocklists/` e são
servidos pela mesma build estática da landing. A URL esperada do manifesto é
`https://andre-fig.github.io/adless/blocklists/manifest.json`. O app consulta o manifesto no
máximo uma vez a cada 24 horas, valida uma nova versão em arquivo temporário e
mantém a lista local anterior ou a lista embutida quando está offline ou quando
uma atualização falha.

Para gerar manualmente e atualizar também o fallback embutido:

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
```

Detalhes operacionais estão em
[`tools/blocklists/README.md`](tools/blocklists/README.md).

O workflow `deploy-pages.yml` publica a build da landing no GitHub Pages após
alterações relevantes da landing ou dos artefatos públicos da blocklist. É
necessário selecionar `GitHub Actions` como fonte de publicação em Settings →
Pages no repositório. Cada workflow usa `concurrency` e cancela a execução
anterior do mesmo grupo quando uma nova é disparada.

O desenvolvimento acontece na branch `develop`; cada alteração de produção do
iOS enviada para `develop` gera automaticamente um build Release no TestFlight
por meio de `.github/workflows/testflight-ios.yml`. Esse workflow usa os
produtos reais do App Store Connect/Sandbox e não usa o arquivo local
`.storekit`. O `pre-push` local executa os testes do iOS antes do envio e o
workflow roda novamente no PR. Um merge para `main` inicia o workflow de release quando há
alteração de produção no app. Se a versão correspondente estiver preparada no
App Store Connect, o workflow `release-ios.yml` também testa, cria o build,
envia o IPA e submete a versão para revisão automaticamente. Ele não cria
metadata ou preços e ignora com sucesso versões que já estão em revisão. Os
secrets necessários e o procedimento estão em
[`docs/ios-release.md`](docs/ios-release.md).

Consulte os READMEs de [apps/ios](apps/ios/README.md) e [apps/landing-page](apps/landing-page/README.md) para detalhes específicos de cada projeto.
