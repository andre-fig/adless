# Desenvolvimento

## Requisitos

- macOS com Xcode e iPhone para validar o DNS efetivo;
- Node.js 20+ e npm;
- Python 3.12+ para o pipeline de blocklist;
- conta Cloudflare somente para deploy do Worker.

## iOS

O projeto `apps/ios/Adless.xcodeproj` tem os targets `Adless` e `AdlessTests`.
Os schemes são:

| Scheme | Configuração | Bundle ID | Endpoint | Nome |
| --- | --- | --- | --- | --- |
| `Adless Dev` | `Debug Dev` / `Release Dev` | `com.orbeworks.adless.dev` | `https://adless-dns.adless-production.workers.dev` | Adless Dev |
| `Adless` | `Debug` / `Release` | `com.orbeworks.adless` | `https://adless-dns.adless-production.workers.dev` | Adless |

O app requer a capability Network Extension `dns-settings`. Não há target
adicional, embedding, App Group ou perfil gerido. O App ID e os profiles de
ambos os ambientes devem ser atualizados no Apple Developer portal antes de um
archive assinado.

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/ios/Adless.xcodeproj -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

`NEDNSSettingsManager` persiste a configuração DoH e carrega o estado real.
`saveToPreferences` não força a ativação: o usuário precisa aprovar/habilitar
Adless em Ajustes. O app reflete `isEnabled`, trata remoção manual e atualiza ao
voltar ao primeiro plano. A proteção continua quando o app não está aberto,
pois é gerida pelo iOS.

## StoreKit

O código preserva os produtos `com.orbeworks.adless.pro.monthly` e
`com.orbeworks.adless.pro.yearly`, no mesmo Subscription Group. Trial de sete
dias e preços são configuração do App Store Connect. O arquivo
`Adless.storekit` serve apenas ao desenvolvimento; TestFlight usa Sandbox e a
versão publicada usa os produtos reais.

## Worker

```sh
npm ci
npm run build:dns-worker
npm run test:dns-worker
python3 tools/dns-worker/prepare_blocklist.py
npx --yes wrangler@4 deploy --config apps/dns-worker/wrangler.toml
```

O Worker exige token de instalação no caminho DoH e Bearer na API de stats. O
Worker usa apenas HTTPS para upstream e não é um proxy de tráfego. Existe
somente o Worker remoto de produção, publicado em `workers.dev`; os testes
locais usam mocks. Deployment, rollback, secrets, métricas, custo e incidentes
estão em [`dns-cloud.md`](dns-cloud.md).

## Blocklist

O pipeline usa apenas a biblioteca padrão Python. As fontes ficam em
`tools/blocklists/sources.json`, com allowlist em `allowlist.txt`. A saída
publicada é `apps/landing-page/public/blocklists/`; a saída para o Worker é
`apps/dns-worker/data/`.

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

Nunca edite artefatos gerados. Um aumento acima do limite precisa de revisão e
de `--allow-large-change`. O workflow gera em candidato, valida e permite
rollback para o deployment anterior.

## Hooks e higiene

Depois de clonar, execute `npm run setup:hooks`. O pre-commit permanece rápido;
o pre-push roda os checks direcionados: XCTest para alterações iOS, testes do
Worker e build para alterações de edge, testes de blocklist e lint, typecheck e
build da landing page quando aplicável. Não use segredos no código, não registre
domínio, pacote DNS, token ou IP e não faça alterações em produção sem revisão.
