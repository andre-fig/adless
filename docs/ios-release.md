# Publicação do iOS

O fluxo é:

```text
develop → TestFlight → pull request → main → archive, validação e App Store
```

## TestFlight

Cada push relevante em `develop` inicia `.github/workflows/testflight-ios.yml`;
há também execução manual. O pre-push local executa `AdlessTests`; o workflow
de publicação cria um archive Release do scheme `Adless`, exporta, inspeciona o
archive/IPA, valida com as ferramentas Apple, envia ao TestFlight, espera o
processamento e adiciona o build ao grupo interno. Ele não submete a revisão.

O archive usa produtos StoreKit reais/Sandbox; `Adless.storekit` é apenas para
desenvolvimento. O scheme `Adless Dev` nunca é usado para distribuição.

## App Store

Cada push relevante em `main` inicia `.github/workflows/release-ios.yml`. O
pre-push local executa `AdlessTests`; o workflow escolhe um build acima do
conhecido no App Store Connect, cria archive, exporta, verifica, valida, envia,
espera o processamento e submete a versão. Versões já em revisão ou à venda
são ignoradas sem erro para evitar submissão duplicada.

Metadata, screenshots, preços, acordos, produtos e trial devem existir no App
Store Connect antes do workflow. O repositório não cria preços nem alterará a
configuração de assinatura.

## Secrets

Obrigatórios:

- `ASC_KEY_ID`;
- `ASC_ISSUER_ID`;
- `ASC_PRIVATE_KEY`, conteúdo completo do `.p8`.

Opcional:

- `SENTRY_AUTH_TOKEN`, somente para upload de dSYM ao projeto configurado.

A chave é materializada no diretório temporário do runner, com permissão 600,
e nunca entra no IPA ou nos logs. Não há credencial Apple no repositório.

O App ID de produção `com.orbeworks.adless` precisa ter a capability Network
Extension `dns-settings`, e o profile de distribuição deve conter o entitlement
correspondente. O target não tem extensão embutida nem App Group. Se a equipe
Apple ainda não tiver habilitado a capability, ative-a no App ID, regenere o
profile e permita signing automático; isso é uma etapa externa ao repositório.
Remova também do App ID as capabilities antigas de provider, Packet Tunnel,
DNS Proxy e App Groups e regenere os profiles de desenvolvimento e distribuição.
Um profile gerenciado antigo pode continuar listando permissões históricas,
mesmo quando elas não são entitlements efetivos do app; não use esse profile
para o release final.

As App Store Server Notifications V2 precisam ser configuradas manualmente no
App Store Connect para Production e Sandbox apontando para:
`https://adless-dns.adless-production.workers.dev/v1/notifications/apple`.
O endpoint valida o `signedPayload`; não há segredo Apple no app ou no Worker.

### Resultado da verificação de deployment

A documentação da Apple descreve DNS Settings como uma configuração do sistema
iOS que usa os protocolos criptografados nativos e diz que o usuário precisa
ativá-la explicitamente. A restrição de iOS supervisionado documentada para
`DNS proxy provider` não se aplica ao caminho `dns-settings` usado aqui. A
documentação do entitlement também instrui habilitar Network Extensions para
um app distribuído pela App Store. Portanto, não há uma exigência objetiva de
MDM indicada para esta arquitetura, mas a aprovação da capability no App ID e
o profile de distribuição continuam sendo pré-requisitos externos que não
podem ser simulados no repositório.

## Verificações de pacote

Depois do archive:

```sh
sh tools/ios/verify_archive.sh /tmp/Adless.xcarchive
sh tools/ios/verify_ipa.sh /tmp/Adless-export/Adless.ipa
```

Os scripts conferem no código assinado o bundle ID, presença de `dns-settings`,
ausência de App Group/entitlement legado, ausência total de `.appex` e
existência de somente `Adless.app`. O profile embutido deve ser conferido
separadamente no portal Apple e regenerado se ainda listar capabilities antigas.
O workflow também exige somente `Adless.app.dSYM` no archive.

Essas verificações são intencionalmente feitas no artefato assinado, não só no
projeto fonte. Sem credenciais da equipe não é possível afirmar que um archive
de distribuição foi assinado; nesse caso o build local sem assinatura só prova
layout e compilação.

## Checks locais

```sh
actionlint .github/workflows/testflight-ios.yml
actionlint .github/workflows/release-ios.yml
python3 -m py_compile tools/appstore/appstore_connect.py
xcodebuild -project apps/ios/Adless.xcodeproj -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

O deploy do DNS é independente e está documentado em
[`dns-cloud.md`](dns-cloud.md); ele usa `CLOUDFLARE_API_TOKEN` e
`CLOUDFLARE_ACCOUNT_ID`, nunca secrets do app.

## Referências oficiais

- [DNS settings](https://developer.apple.com/documentation/networkextension/dns-settings);
- [`NEDNSSettingsManager`](https://developer.apple.com/documentation/networkextension/nednssettingsmanager);
- [`NEDNSOverHTTPSSettings`](https://developer.apple.com/documentation/networkextension/nednsoverhttpssettings);
- [Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension);
- [Enable App ID capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).
