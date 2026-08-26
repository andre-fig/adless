# Guia de desenvolvimento

Este documento descreve como configurar o ambiente, desenvolver cada parte do
monorepo e validar alterações antes de abrir um pull request.

## Pré-requisitos

- macOS com Xcode para desenvolvimento iOS;
- Node.js 20 ou superior e npm 10;
- Python 3;
- `actionlint` para alterações nos workflows;
- iPhone físico e conta Apple Developer para testar a interceptação DNS real.

O simulador é suficiente para a landing page, layout, build e testes unitários.
O DNS Proxy não funciona como interceptação real no simulador.

## Primeiro setup

Na raiz do repositório:

```sh
git clone https://github.com/andre-fig/adless.git
cd adless
npm ci
```

`npm ci` instala as dependências do workspace e executa `prepare`, ativando os
hooks versionados em `.githooks/`. Para reativá-los manualmente:

```sh
npm run setup:hooks
```

Antes de iniciar uma tarefa, confira a branch e as alterações locais:

```sh
git status --short --branch
git switch develop
git pull --ff-only origin develop
```

O fluxo normal é:

```text
develop → pull request → main
```

Não trabalhe diretamente na `main` para mudanças de produto.

## Landing page

A landing fica em `apps/landing-page/` e usa React, Vite, TypeScript, Tailwind
CSS e shadcn/ui.

### Desenvolvimento local

```sh
npm run dev:landing
```

O Vite exibirá a URL local no terminal. A build de produção pode ser servida
com:

```sh
npm run build:landing
npm run preview:landing
```

### Validação

```sh
npm run lint
npm run typecheck
npm run build:landing
```

O TypeScript usa modo `strict` e o ESLint usa regras type-aware. Não adicione
`any`, promessas sem tratamento ou variáveis não utilizadas para silenciar um
erro; corrija o tipo ou o fluxo responsável.

O diretório público real é `apps/landing-page/public/`. A blocklist deve
permanecer em `public/blocklists/` e não pode ser importada para o bundle
JavaScript.

## Aplicativo iOS

Abra o projeto:

```sh
open apps/ios/Adless.xcodeproj
```

Os targets são:

- `Adless`: aplicativo SwiftUI;
- `AdlessDNSProxy`: Network Extension do tipo DNS Proxy;
- `AdlessTests`: testes XCTest.

### Ambientes e schemes

O projeto tem dois ambientes sem duplicar targets:

| Scheme | Configuração | App Bundle ID | Extension Bundle ID | App Group | Nome |
| --- | --- | --- | --- | --- | --- |
| `Adless Dev` | `Debug Dev` / `Release Dev` | `com.orbeworks.adless.dev` | `com.orbeworks.adless.dev.dnsproxy` | `group.com.orbeworks.adless.dev` | Adless Dev |
| `Adless` | `Debug` / `Release` | `com.orbeworks.adless` | `com.orbeworks.adless.dnsproxy` | `group.com.orbeworks.adless` | Adless |

Os valores ficam em `apps/ios/Configurations/Development.xcconfig` e
`apps/ios/Configurations/Production.xcconfig`. O código usa
`apps/ios/Shared/BuildEnvironment.swift`, que lê os valores gerados no
Info.plist. Assim, o App Group, a blocklist, os contadores, o snapshot de
assinatura e o estado do DNS Proxy não são compartilhados entre instalações.

Para desenvolvimento local, selecione `Adless Dev`. Para TestFlight/App
Store, selecione exclusivamente `Adless` e a configuração `Release`.

Antes de executar em um dispositivo, configure no Xcode e no Apple Developer:

1. Team da organização Orbe Works;
2. os dois App IDs do ambiente escolhido;
3. o App Group correspondente associado aos dois App IDs;
4. capability Network Extensions com `DNS Proxy` nos dois App IDs;
5. capability App Groups nos dois App IDs;
6. assinatura válida para o dispositivo.

O ambiente Dev exige estes novos identifiers no portal:

```text
com.orbeworks.adless.dev
com.orbeworks.adless.dev.dnsproxy
group.com.orbeworks.adless.dev
```

Não altere nem associe o App Group Dev aos identifiers oficiais. O ambiente
oficial continua usando somente `com.orbeworks.adless`,
`com.orbeworks.adless.dnsproxy` e `group.com.orbeworks.adless`.

Não altere entitlements ou capabilities sem verificar os dois targets. O
projeto não cria certificados, perfis ou contas Apple automaticamente.

### Build sem assinatura

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme 'Adless Dev' \
  -sdk iphonesimulator \
  -configuration 'Debug Dev' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Para gerar um archive oficial, use `Adless` com `Release`:

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme Adless \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  archive
```

### Testes XCTest

Com um simulador disponível, por exemplo `iPhone 16`:

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Para descobrir os simuladores disponíveis:

```sh
xcrun simctl list devices available
```

Os testes cobrem parser, normalização, gzip, checksum, manifesto, fallback,
atualização e armazenamento. Testes unitários não devem baixar a blocklist
real da internet.

### Simulador e dispositivo físico

Use o simulador para ajustar layout, temas, drawer de assinatura, build e
XCTest. Use um iPhone físico para ativar a Network Extension, verificar DNS
UDP/TCP, testar o failover dos provedores DoH e confirmar o bloqueio em outros
aplicativos e redes.

O simulador pode representar o estado de ativação para desenvolvimento de UI,
mas isso não prova que o DNS está sendo interceptado.

## StoreKit e assinaturas locais

O app não possui backend de assinatura. Os produtos são:

```text
com.orbeworks.adless.pro.monthly
com.orbeworks.adless.pro.yearly
```

O scheme compartilhado `Adless` usa `apps/ios/Adless.storekit` para testes
locais. Esse arquivo contém produtos, grupo de assinatura, preços locais e o
trial de sete dias para desenvolvimento.

Para testar compras localmente:

1. abra o projeto no Xcode;
2. selecione o scheme `Adless`;
3. execute no simulador;
4. use **Debug → StoreKit → Manage Transactions** para inspecionar, renovar
   ou resetar transações.

O argumento `-useStoreKitProducts` faz o app buscar os produtos do StoreKit
local. Uma execução direta de Debug no simulador pode exibir opções de layout
sem produtos carregados, mas essas opções são apenas visuais e não permitem
compras reais.

Não use uma flag fixa como `isSubscribed = true`. O acesso deve vir de
transações verificadas, `Transaction.currentEntitlements`,
`Transaction.updates` e `AppStore.sync()`.

Testes de Sandbox, TestFlight e produção usam o App Store Connect, não o
arquivo `.storekit`. Preços, disponibilidade, grupo, trial e acordos legais
precisam estar configurados externamente.

## Localização do iOS

As traduções do app ficam em `apps/ios/Adless/Resources/Localizable.xcstrings`.
O inglês é o idioma-base e `pt-BR` e `es` estão disponíveis como traduções. O iOS escolhe
automaticamente o primeiro idioma compatível na lista de preferências do
dispositivo e usa inglês como fallback.

Para adicionar um idioma futuro:

1. adicione a região ao `knownRegions` do projeto Xcode;
2. inclua a tradução no `Localizable.xcstrings`;
3. localize os metadados dos produtos no App Store Connect;
4. teste a interface e o fluxo de compra com o idioma selecionado no
   simulador e no dispositivo.

Os preços continuam vindo do StoreKit conforme o storefront da Conta Apple;
não devem ser duplicados como valores fixos por idioma no código.

## Blocklist

A fonte habilitada no MVP é a OISD Small, declarada em
`tools/blocklists/sources.json`. O pipeline usa apenas a biblioteca padrão do
Python.

### Testes e geração

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
python3 tools/blocklists/validate_blocklist.py \
  --seed apps/ios/Adless/Resources/SeedBlocklist.txt
```

O gerador baixa fontes somente por HTTPS, rejeita respostas suspeitas, aplica a
allowlist, remove duplicados, ordena a saída e valida limites de tamanho e
variação. A atualização da lista embutida deve ser feita pelo gerador, nunca
editando `SeedBlocklist.txt` manualmente.

Para uma alteração legítima acima do limite de variação, revise os resultados
e use explicitamente:

```sh
python3 tools/blocklists/generate_blocklist.py \
  --allow-large-change \
  --sync-seed
```

Os artefatos publicados são:

```text
apps/landing-page/public/blocklists/manifest.json
apps/landing-page/public/blocklists/blocklist.txt
apps/landing-page/public/blocklists/blocklist.txt.gz
apps/landing-page/public/blocklists/blocklist.sha256
apps/ios/Adless/Resources/SeedBlocklist.txt
```

O SHA-256 publicado corresponde ao arquivo gzip. Não faça commit de arquivos
gerados se o conteúdo não mudou.

### Atualização no iOS

O app consulta o manifesto público no máximo uma vez a cada 24 horas:

```text
https://andre-fig.github.io/adless/blocklists/manifest.json
```

Durante uma atualização, o app valida HTTPS, origem, tamanho, gzip, SHA-256,
formato e quantidade de domínios antes de instalar qualquer arquivo. A lista
ativa anterior continua sendo usada até a conclusão de todas as validações.

O App Group contém a lista ativa em:

```text
Library/Application Support/Blocklists/blocklist.txt
```

Para forçar uma checagem durante testes, use o fluxo de atualização exposto
pelos testes ou limpe o estado de desenvolvimento em um ambiente controlado.
Não remova dados de produção nem altere arquivos compartilhados manualmente
durante uma sessão ativa.

## Hooks locais

Os hooks evitam consumir minutos dos runners quando uma falha pode ser
detectada localmente.

### `pre-commit`

Executa verificações rápidas nos arquivos staged:

- `actionlint` quando workflows mudam;
- sintaxe Python quando ferramentas Python mudam;
- lint da landing quando código ou dependências da landing mudam.

### `pre-push`

Seleciona verificações pelo caminho alterado:

- blocklist: testes Python;
- landing: lint, typecheck e build;
- iOS: XCTest no simulador disponível;
- workflows: `actionlint`.

Se um hook falhar, corrija a causa. Use `--no-verify` somente quando houver
um motivo documentado e a validação equivalente for executada manualmente.

## GitHub Actions

Os workflows ficam em `.github/workflows/`:

- `ios-tests.yml`: roda XCTest em pull requests e manualmente;
- `release-ios.yml`: em mudanças relevantes na `main`, faz preflight,
  archive, export, validação, upload e submissão no App Store Connect;
- `update-blocklist.yml`: roda semanalmente aos domingos e manualmente;
- `deploy-pages.yml`: publica a landing e os arquivos estáticos no GitHub
  Pages.

Os testes iOS não são repetidos no release para evitar consumo desnecessário
de macOS; o `pre-push` local e o workflow do pull request são as validações
antes do archive.

Ao editar workflows:

```sh
actionlint .github/workflows/*.yml
```

Mantenha `concurrency`, timeouts, permissões mínimas e caminhos explícitos.
Nunca use `git add .` ou `git add -A` em automações.

## Release iOS

Antes de enviar uma versão:

1. crie a nova versão no App Store Connect;
2. atualize `MARKETING_VERSION` no projeto Xcode;
3. preencha metadata, preços, produtos, screenshots, review information,
   termos e privacidade no App Store Connect;
4. valide localmente e abra um pull request a partir da `develop`;
5. faça merge para `main` somente quando o PR estiver aprovado.

O workflow usa os secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` e `ASC_PRIVATE_KEY`.
A chave `.p8` nunca deve ser commitada. O preflight evita uma segunda
submissão quando a versão já está em revisão ou disponível.

Detalhes operacionais estão em [`ios-release.md`](ios-release.md).

## Checklist antes de abrir um PR

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run typecheck
npm run build:landing
git status --short --branch
```

Acrescente o build/teste Xcode para mudanças em `apps/ios/` e `actionlint`
para mudanças em `.github/workflows/`. Na descrição do PR, informe os
comandos executados e qualquer validação que dependa de um dispositivo físico,
App Store Connect ou GitHub Actions.
