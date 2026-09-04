# Testes

## Suite local

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run test:dns-worker
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
```

Os testes do Worker usam mocks e cobrem:

- POST e GET RFC 8484, content type, tamanho, método e Base64URL;
- uma pergunta, contagens, nomes comprimidos, EDNS0 e transaction ID;
- A, AAAA, HTTPS, SVCB, CNAME, TXT, MX, NS, PTR, SOA e SRV;
- bloqueio exato e por subdomínio, nome semelhante e allowlist;
- ausência de upstream para bloqueados;
- NXDOMAIN válido sem fallback;
- timeout/falha de transporte, HTTP inválido, corpo vazio ou DNS inválido com
  fallback Cloudflare→Quad9;
- SERVFAIL quando os dois falham;
- cache limitado ao TTL, concorrência, rate limiting e integridade da lista;
- ausência de resolver em texto puro, domínio e IP em logs de aplicação.

A suíte Python testa download HTTPS, normalização IDN, allowlist, ordenação,
deduplicação, gzip determinístico, checksum, contagem e rejeição de alteração
grande.

## XCTest e build

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/adless-ios-test-derived-data \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/adless-ios-build \
  CODE_SIGNING_ALLOWED=NO build
```

Os testes iOS verificam regras de domínio, StoreKit/política de acesso,
persistência local do último total, não diminuição do contador e configuração
de ambiente. A configuração nativa DoH usa `NEDNSSettingsManager`; sua
ativação efetiva não pode ser simulada completamente no Simulator.

## Matriz manual em iPhone

Depois de uma assinatura Sandbox ativa:

1. toque em Ativar;
2. aprove o Adless em Ajustes → Geral → VPN e Rede → DNS, quando o iOS solicitar;
3. volte ao app e confirme que o estado só fica protegido quando
   `isEnabled == true`;
4. toque em Desativar e confirme que o estado real volta a desligado;
5. remova a configuração manualmente em Ajustes e confirme que o app não diz
   estar protegido;
6. reinicie o iPhone e bloqueie a tela por várias horas;
7. alterne Wi‑Fi, 5G e modo avião;
8. teste IPv4/IPv6, Safari e outro navegador, além de apps que usam DNS;
9. entre e saia do paywall, compre mensal/anual, restaure a compra, cancele e
   deixe expirar;
10. confirme que a API de stats atualiza ao entrar em primeiro plano e que a
    falha da API preserva o último número sem erro invasivo;
11. confira layouts de iPhone e iPad, tamanhos de texto e localizações.

| Cenário | Resultado esperado |
| --- | --- |
| Assinatura válida + configuração habilitada | UI protegida e DNS usa o endpoint salvo |
| Configuração salva, mas não habilitada | UI desligada e instrução para Ajustes |
| Configuração removida manualmente | UI desligada; Ativar pode recriar a configuração |
| Assinatura expirada | configuração removida e UI não afirma proteção |
| API de stats indisponível | último total permanece; DNS não é desligado |
| Rede alterada/tela bloqueada | iOS decide a disponibilidade; app não precisa ficar aberto |
| Modo avião/captive portal/DoH bloqueado | resolução pode falhar; sem fallback para DNS sem criptografia |

## Interferências conhecidas

Teste com iCloud Private Relay, “Limitar Rastreamento de Endereço IP”, outro
perfil DNS, outra VPN, DNS da rede e captive portal. O sistema pode selecionar
outra configuração, bloquear DoH ou exigir novo consentimento. O Adless não
promete prevalência, anonimato, ocultação de IP nem que o provedor não possa
inferir destinos.

## Archive, entitlements e IPA

O archive de distribuição requer Team, App ID e profile com
`com.apple.developer.networking.networkextension = dns-settings`. Não é possível
provar a assinatura de distribuição sem credenciais da equipe Apple. Quando
disponível:

```sh
xcodebuild archive -project apps/ios/Adless.xcodeproj -scheme Adless \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/Adless.xcarchive -allowProvisioningUpdates
sh tools/ios/verify_archive.sh /tmp/Adless.xcarchive
xcodebuild -exportArchive -archivePath /tmp/Adless.xcarchive \
  -exportOptionsPlist docs/app-store/ExportOptions.plist \
  -exportPath /tmp/Adless-export
sh tools/ios/verify_ipa.sh /tmp/Adless-export/Adless.ipa
```

Os verificadores falham se o archive/IPA não tiver `Adless.app`, se houver
qualquer `.appex`, se faltar `dns-settings` no bundle assinado ou se existir
entitlement legado. A inspeção do IPA deve ser feita antes do upload.
Também confira no Apple Developer que o profile usado não é um profile gerenciado
antigo que ainda autoriza App Groups ou providers removidos; o profile precisa
ser regenerado depois da limpeza do App ID.

## Smoke real opcional

Após o deploy de produção, use um token descartável:

```sh
ADLESS_DNS_TOKEN='...' ADLESS_STATS_TOKEN='...' \
  python3 tools/dns/smoke_worker.py --url https://adless-dns.adless-production.workers.dev
```

O token não deve aparecer em logs ou shell history. O smoke test valida TLS do
sistema, POST, GET, wire response e stats; não registra o domínio sintético,
token ou IP. Não faça testes com `curl -k`.
