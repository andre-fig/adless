# Contribuindo com o Adless

## Escopo

O Adless é um app iOS de filtragem DNS com StoreKit 2 e um Cloudflare Worker
DoH. Somente consultas DNS passam pelo serviço; não transforme o projeto em
proxy HTTP, serviço de conta ou encaminhador de tráfego.

Antes de editar, confira:

```sh
git status --short --branch
```

Preserve trabalho não relacionado. Não use `git reset --hard`, não apague
arquivos não versionados e não faça commit/push sem autorização.

## iOS

Abra `apps/ios/Adless.xcodeproj`. Os únicos targets são `Adless` e
`AdlessTests`. O app usa `NEDNSSettingsManager` e
`NEDNSOverHTTPSSettings`; a aprovação final é do usuário em Ajustes. O único
entitlement de Network Extension é `dns-settings`. A capability e os profiles
precisam estar autorizados no Apple Developer portal para archive de
distribuição.

O simulador valida compilação, UI e XCTest. A configuração DNS efetiva,
reinício, tela bloqueada e mudanças de rede exigem iPhone.

## Worker

O código está em `apps/dns-worker/`. Use mocks nos testes; a suíte nunca deve
depender de Cloudflare DNS ou Quad9 disponíveis. Não registre QNAME, pacote
DNS, token ou IP. O endpoint deve preservar wire format, transaction ID, tipo,
classe, EDNS0 e flags relevantes. Fallback só ocorre após falha de transporte,
HTTP inválido, corpo vazio ou DNS inválido.

```sh
npm run build:dns-worker
npm run test:dns-worker
```

## Blocklist

Edite fontes declarativas, allowlist ou gerador; não edite os arquivos gerados.
Depois execute:

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

Alterações grandes exigem revisão explícita e `--allow-large-change`. O
workflow publica somente a saída esperada.

## Antes do PR

```sh
git diff --check
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
npm run test:dns-worker
python3 -m unittest discover -s tools/blocklists/tests -v
```

Para mudanças iOS, adicione build/teste Xcode. Para distribuição, verifique o
archive e o IPA com `tools/ios/verify_archive.sh` e `tools/ios/verify_ipa.sh`.
