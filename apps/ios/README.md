# Adless iOS app

Adless é um app SwiftUI de proteção DNS. Ele configura o DNS-over-HTTPS nativo
do iOS com `NEDNSSettingsManager` e `NEDNSOverHTTPSSettings`; somente consultas
DNS são enviadas ao serviço Adless para filtragem na edge. O restante do
tráfego continua seguindo diretamente para seus destinos.

## Targets

- `Adless` — app iOS e integração StoreKit 2;
- `AdlessTests` — testes XCTest do app e das regras reutilizáveis.

Não há extensão embutida. O único entitlement de Network Extension do app é
`dns-settings`; não há App Group, configuração `.mobileconfig`, perfil gerido,
rota de tráfego ou API privada.

## Build e autorização

1. Abra `apps/ios/Adless.xcodeproj` no Xcode.
2. Use `Adless Dev` para desenvolvimento local e `Adless` para archive oficial.
3. Configure no App ID de cada ambiente a capability Network Extension com
   `dns-settings` e regenere os profiles de desenvolvimento/distribuição.
4. Compile o simulador para validar a UI e use um iPhone para validar o DNS
   efetivo.

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Salvar uma configuração não significa que ela está ativa: `isEnabled` é
somente leitura e o iOS exige que o usuário aprove a configuração em Ajustes.
O app recarrega o estado real a cada entrada em primeiro plano e responde à
notificação de alteração. Se a configuração for removida em Ajustes, o app
mostra a proteção como desligada e pode instalá-la novamente ao tocar em Ativar.

## Ambientes

| Scheme | Configuration | App ID | DNS endpoint base | Display name |
| --- | --- | --- | --- | --- |
| `Adless Dev` | `Debug Dev` / `Release Dev` | `com.orbeworks.adless.dev` | `https://adless-dns.adless-production.workers.dev` | Adless Dev |
| `Adless` | `Debug` / `Release` | `com.orbeworks.adless` | `https://adless-dns.adless-production.workers.dev` | Adless |

O app mantém um `installationId` interno e dois tokens de 256 bits aleatórios,
`dns-token` e `stats-token`, como Generic Password no Keychain, com
`ThisDeviceOnly`. Eles não são derivados de IDFA, IDFV, Apple Account ou
hardware. O primeiro é usado somente no caminho DoH; o segundo somente no
Bearer do contador.

## Ciclo de proteção

Após uma compra/restauração válida, o app envia o JWS assinado do StoreKit ao
Worker, salva as novas credenciais no Keychain e cria um endpoint individual
`https://adless-dns.adless-production.workers.dev/<dns-token>/dns-query`, salva a configuração DoH da Apple e
recarrega o estado. O iOS mantém a configuração enquanto o app não está
aberto, inclusive após reinicialização e com a tela bloqueada. A assinatura
StoreKit e o status server-side são as autoridades: quando expira, o Worker
deixa de bloquear e o app tenta remover a configuração; se a remoção não for
confirmada, a UI orienta a desativação manual em Ajustes.

O endpoint aplica a blocklist na edge. Consultas permitidas seguem por DoH
para Cloudflare DNS e, em falha transitória, Quad9. O app não conhece nem
processa pacotes DNS individuais e não usa DNS em texto puro.

## Contadores

O app consulta `GET /v1/stats` ao entrar em primeiro plano e depois da ativação,
autenticando com o `stats-token`. O cache local mantém o último total quando a API está
offline e nunca reduz o valor exibido. Falhas do contador não desligam a
proteção nem geram erro invasivo.

## Testes no dispositivo

Teste em iPhone físico: ativação e remoção em Ajustes, reinicialização, tela
bloqueada, Wi‑Fi/5G, modo avião, IPv4/IPv6, navegadores e apps diferentes.
Registre também o comportamento com Private Relay, “Limitar Rastreamento de
Endereço IP”, outro perfil DNS, outra VPN, captive portal e redes que bloqueiam
DoH. O sistema ou outra configuração pode substituir o DNS do Adless; o app
não promete prevalência nessas situações.

A suíte XCTest usa mocks e não depende da rede. O smoke test DoH opcional e as
instruções operacionais estão em [`docs/dns-cloud.md`](../../docs/dns-cloud.md),
[`docs/TESTING.md`](../../docs/TESTING.md) e
[`docs/ios-release.md`](../../docs/ios-release.md).

## StoreKit

Os product IDs são `com.orbeworks.adless.pro.monthly` e
`com.orbeworks.adless.pro.yearly`, no mesmo grupo de assinaturas, com trial de
sete dias configurado no App Store Connect. Compras, restauração, cancelamento,
grace period e expiração continuam sob StoreKit 2; o Worker valida server-side
o JWS e recebe as notificações V2 da Apple. Não há conta nem validação em
Railway.
