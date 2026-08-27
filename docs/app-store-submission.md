# Preparação da submissão do Adless

Última revisão do código: 26/08/2026.

## Identidade

- App Store Connect app ID: `6803552143`;
- Bundle ID: `com.orbeworks.adless`;
- SKU: `ADLESS-IOS-ORBEWORKS-001`;
- Team ID: `J728Z86KY5`;
- nome: `Adless: Clean Web`;
- versão configurada: `1.0`.

## URLs públicas

- <https://andre-fig.github.io/adless/>;
- <https://andre-fig.github.io/adless/privacy>;
- <https://andre-fig.github.io/adless/terms>;
- <https://andre-fig.github.io/adless/support>;
- <https://andre-fig.github.io/adless/blocklists/manifest.json>.

As páginas são estáticas. O app não tem conta, login ou cadastro.

## StoreKit

O grupo `Adless Pro` contém:

| Plano | Product ID | Oferta |
| --- | --- | --- |
| Mensal | `com.orbeworks.adless.pro.monthly` | 7 dias para novos assinantes elegíveis |
| Anual | `com.orbeworks.adless.pro.yearly` | 7 dias para novos assinantes elegíveis |

Preços, disponibilidade, trial, screenshots de revisão e contratos são
configuração externa do App Store Connect e não são alterados pelo código.

## Texto de revisão sugerido

> Adless configures Apple’s encrypted DNS settings to block known ad and tracker
> domains. Only DNS queries use the Adless service; websites, videos, messages,
> and downloads go directly to their destinations. No account is required. To
> test the main flow, install the app, complete a Sandbox subscription, tap the
> central button, and approve/enable Adless in the iOS DNS settings if asked.
> Return to the app to see the protected state. The same button disables the
> configuration. Restore Purchases is available in the subscription sheet.

Não prometa anonimato, ocultação de IP ou que uma configuração Apple sempre
prevalecerá sobre Private Relay, outra VPN, outro perfil DNS ou política da
rede.

## Build e criptografia

```sh
xcodebuild archive \
  -project apps/ios/Adless.xcodeproj \
  -scheme Adless \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Adless.xcarchive
sh tools/ios/verify_archive.sh /tmp/Adless.xcarchive
```

O bundle precisa ser assinado com `com.apple.developer.networking.networkextension`
contendo `dns-settings`. O archive deve conter apenas `Adless.app`, sem
extensão ou App Group. Após exportar, rode `tools/ios/verify_ipa.sh` antes da
validação/upload Apple. `ITSAppUsesNonExemptEncryption` permanece `false` para
o uso de HTTPS do sistema e SHA-256, sem criptografia proprietária.

Antes do upload, no Apple Developer, mantenha no App ID apenas a capability
`dns-settings` necessária para este target e remova capabilities antigas de
DNS Proxy, Packet Tunnel e App Groups. Regenere os profiles depois dessa
alteração. A lista de capabilities autorizadas em um profile antigo não é o
mesmo que o entitlement efetivo extraído por `codesign`, mas um profile antigo
não deve ser usado para distribuição.

O build anterior registrado no App Store Connect não é evidência do binary
atual; cada release deve repetir archive, inspeção de entitlements e inspeção
do IPA. Sem Team/profile válidos no ambiente local, só é possível provar
compilação e layout sem assinatura.

## Privacidade

Use <https://andre-fig.github.io/adless/privacy> e confira a seção
[`docs/app-store-privacy-questionnaire.md`](app-store-privacy-questionnaire.md)
contra o binary e as políticas atuais da Apple, Cloudflare e Quad9. A alteração
para DNS Cloud deve ser refletida na resposta de App Privacy antes da submissão.
