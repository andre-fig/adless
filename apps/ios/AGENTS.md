# Instruções do app iOS

Escopo: `apps/ios/`. Aplique também o [AGENTS da raiz](../../AGENTS.md).
Leia o [README local](README.md) para responsabilidades e estados; publicação,
perfis e gates Apple estão em [ios-release](../../docs/ios-release.md).

## Arquitetura e invariantes

- SwiftUI: `AdlessApp.swift` / `AppViewModel` coordenam StoreKit, autorização,
  configuração DNS e UI; `ContentView.swift` reage ao foreground.
  `SubscriptionManager.swift` verifica transações; `InstallationTokenStore.swift`
  persiste credenciais; o actor `DNSSettingsManager` serializa preferências.
- Use somente `NEDNSSettingsManager` + `NEDNSOverHTTPSSettings`. Os targets são
  `Adless` e `AdlessTests`. Não introduza Packet Tunnel, DNS Proxy, DNS local,
  `.appex`, App Group, `.mobileconfig`, interface ou rota de tráfego.
- O entitlement de rede permitido é exclusivamente `dns-settings`. Revise
  também os entitlements efetivos e o provisioning profile do artefato.
- StoreKit fornece estados checking/active/inactive/unavailable. Cancelar
  renovação não equivale a expirar; valide expiração, grace, revogação e
  reembolso junto ao Worker. Um cache local nunca autoriza um token no servidor.
- Persista `installationId`, par DNS/stats e metadados em um único blob
  versionado do Keychain `AfterFirstUnlockThisDeviceOnly`. Não derive identidade
  de IDFA, IDFV, conta Apple ou hardware; não prometa exclusão no uninstall.
- Persista o `rotationNonce` antes do POST; retries da mesma transação reutilizam
  o nonce. Confirme o par inteiro antes de instalar DNS. Prova com o par antigo
  só cabe à migração legada; preserve migração e recuperação de escrita falha.
- `isEnabled` é somente leitura. Instalar significa salvar e reler preferências;
  ativar depende do usuário em Ajustes. Remover significa remover, reler e
  confirmar ausência; se falhar, orientar desativação manual.
- Nunca derive proteção ativa só de compra, sucesso do save, contador ou
  `isOn`: preserve `AppViewModel.protectionIsConfirmed` (entitlement,
  credenciais reconciliadas e `.enabled`). Perfil com URL antiga,
  credenciais pendentes ou escopo DNS divergente é `.staleEnabled`, sem
  confirmação de bloqueio. Preserve testes dessa distinção.
- Não há deep link público para a tela específica de DNS. Use somente
  `UIApplication.openSettingsURLString`; `App-Prefs:` e `prefs:` são proibidos.
  Preserve o tutorial de navegação em Ajustes e a atualização ao retornar.
- `Localizable.xcstrings` usa EN, PT-BR e ES. Confira chaves efetivamente usadas
  pela UI, textos legais, acessibilidade e tutorial nos três idiomas. O app
  tem orientação textual; tutorial com screenshots ainda exige trabalho próprio.
- O simulador não prova interceptação DNS. Não prometa prevalência sobre DNS
  próprio de apps, Private Relay, VPN, outro perfil ou restrições da rede.

## Ambientes e validação

`Adless Dev` usa Debug/Release Dev; `Adless` usa Debug/Release com identidade
oficial. `Adless Dev` aponta para o Worker `adless-dns-development`, com KV,
Durable Objects, segredo e identidade StoreKit isolados; `Adless` aponta para o
Worker de produção. Não compartilhe bindings ou origem entre eles.
Debug/Release não definem o ambiente StoreKit: Xcode local usa `Adless.storekit`,
TestFlight usa Sandbox e App Store pública usa Production. O Worker Dev aceita
JWS local somente com `environment=Xcode`, bundle Dev, AppTransaction correspondente
e certificado Xcode fixado; o Worker de produção não aceita esse ambiente.

Comandos a partir da raiz, em ambiente com dependências já disponíveis:

```sh
xcodebuild -project apps/ios/Adless.xcodeproj -scheme Adless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
xcodebuild -project apps/ios/Adless.xcodeproj -scheme AdlessTests \
  -destination "platform=iOS Simulator,id=$ADLESS_SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO test
```

Defina `ADLESS_SIMULATOR_ID` com um simulador disponível. Use `AdlessTests`:
os TestActions de `Adless` e `Adless Dev` não incluem testes. Para archive,
exportação e `verify_archive.sh` / `verify_ipa.sh`, siga os comandos e limites
de autorização em [ios-release](../../docs/ios-release.md). Execute também os
testes do Worker quando mudar o contrato de autorização ou o caminho DNS.

Exigem revisão adicional: `AdlessApp.swift`, `DNSSettingsManager.swift`,
`InstallationTokenStore.swift`, `DNSStatsAPIClient.swift`, `SubscriptionManager.swift`,
`DNSCloudConfiguration.swift`, `SentryConfiguration.swift`, entitlements,
`Info.plist`, configurações/schemes e o projeto Xcode. Consulte as limitações
no README antes de tratar comportamento não testado como garantia.
