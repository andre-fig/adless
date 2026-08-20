# Instruções do monorepo Adless

Este arquivo orienta agentes e colaboradores que alteram o monorepo. Preserve
alterações existentes, mantenha o escopo da tarefa e não introduza serviços que
não fazem parte da arquitetura atual.

## Arquitetura

```text
apps/
├── ios/
│   ├── Adless/          # app SwiftUI
│   ├── AdlessDNSProxy/  # Network Extension DNS Proxy
│   └── AdlessTests/     # testes XCTest
└── landing-page/        # React + Vite

tools/blocklists/        # gerador, validador, fixtures e testes Python
apps/landing-page/public/blocklists/
                         # artefatos estáticos publicados
```

O aplicativo não usa backend, login ou banco de dados próprio. A cobrança é
feita exclusivamente pela App Store com StoreKit 2; o app oferece assinatura
mensal e anual com trial de 7 dias configurado no App Store Connect. A landing
page é estática e a blocklist é distribuída pelos arquivos públicos do GitHub
Pages.

## Comandos principais

Execute os comandos a partir da raiz do monorepo.

### Landing page

Requer Node.js 20 ou superior e npm.

```sh
npm ci
npm run dev:landing
npm run lint
npm run build:landing
npm run preview:landing
```

### Blocklist

O pipeline usa somente a biblioteca padrão do Python. Os testes unitários não
devem baixar fontes reais da internet.

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
python3 tools/blocklists/validate_blocklist.py \
  --seed apps/ios/Adless/Resources/SeedBlocklist.txt
```

Use `--allow-large-change` somente após revisar e confirmar uma alteração
legítima acima do limite configurado.

### iOS

Abra `apps/ios/Adless.xcodeproj` no Xcode. Os targets são:

- `Adless`: aplicativo SwiftUI;
- `AdlessDNSProxy`: extensão Network Extension DNS Proxy;
- `AdlessTests`: testes XCTest.

Build sem assinatura para o simulador:

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme Adless \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Para testar, use o scheme `AdlessTests` e um simulador iOS disponível. A
interceptação DNS completa precisa de um dispositivo real; o simulador serve
para build e testes unitários.

## Blocklist

A fonte habilitada no MVP é a OISD Small, declarada em
`tools/blocklists/sources.json`. Não coloque domínios manualmente no código do
app ou da extensão.

O gerador publica, de forma determinística, estes arquivos em
`apps/landing-page/public/blocklists/`:

- `manifest.json`;
- `blocklist.txt.gz`;
- `blocklist.txt`;
- `blocklist.sha256`.

O SHA-256 publicado corresponde ao arquivo compactado `blocklist.txt.gz`.
`generatedAt` não deve provocar commits quando o conteúdo não mudou. A lista
embutida em `apps/ios/Adless/Resources/SeedBlocklist.txt` é produzida pelo
mesmo pipeline e serve apenas como fallback offline.

O manifesto público atual é:

```text
https://andre-fig.github.io/adless/blocklists/manifest.json
```

Ao adicionar ou remover uma fonte, altere o arquivo declarativo, revise
`THIRD_PARTY_BLOCKLISTS.md` e execute toda a validação. Não use URLs HTTP nem
fontes não oficiais.

## Atualização no iOS

O app consulta o manifesto em segundo plano ao abrir ou voltar ao primeiro
plano, no máximo uma vez a cada 24 horas, com backoff para falhas repetidas.
Ativar o bloqueio nunca depende da internet.

Arquivos válidos são baixados para local temporário, validados por HTTPS,
tamanho, gzip, SHA-256, sintaxe e quantidade de domínios, e instalados por
substituição atômica. Falhas preservam a lista local anterior e nunca desligam
o bloqueio.

O app e a extensão compartilham a lista em:

```text
Library/Application Support/Blocklists/blocklist.txt
```

Esse caminho usa o App Group existente `group.com.usefulish.adless`. Não use
`Documents`, não exponha a lista ao usuário e não altere entitlements ou
capabilities sem verificar os dois targets e documentar o motivo.

## Assinatura

O app usa StoreKit 2, sem backend ou conta própria. Os product IDs são:

```text
com.usefulish.adless.pro.monthly
com.usefulish.adless.pro.yearly
```

Os dois produtos devem pertencer ao mesmo Subscription Group no App Store
Connect. O trial gratuito de 7 dias precisa ser configurado como Introductory
Offer no App Store Connect; não basta alterar uma constante no código.

O app considera `subscribed` e `inGracePeriod` como acesso válido, persiste um
snapshot verificado no App Group e a extensão recusa iniciar ou processar DNS
quando o snapshot está ausente ou expirado. Compras são restauradas com
`AppStore.sync()` e atualizações são observadas por `Transaction.updates`.

Não coloque uma flag manual permanente como `isSubscribed = true`. O acesso
deve derivar da transação verificada pela Apple e da data de validade. Para
testes reais, configure os produtos e uma conta Sandbox no App Store Connect.

## GitHub Actions e publicação

`.github/workflows/update-blocklist.yml` executa diariamente e também pode ser
executado manualmente. Ele baixa, normaliza, valida e publica somente os
artefatos permitidos. Mudanças inesperadas devem fazer o workflow falhar.

`.github/workflows/deploy-pages.yml` constrói a landing e publica o diretório
`apps/landing-page/dist` no GitHub Pages após alterações na `main` ou execução
manual. O workflow usa as versões atuais das actions e não deve receber
segredos desnecessários.

Ao alterar workflows:

- use permissões mínimas;
- mantenha `concurrency` e timeouts;
- não use `git add .`, `git add -A` ou curingas para publicar artefatos;
- não faça download ou execute código vindo de uma blocklist;
- valide YAML e, quando disponível, execute `actionlint`;
- verifique o run no GitHub após publicar alterações.

## Regras de alteração

- Preserve funcionalidades e mudanças existentes.
- Não crie backend, Railway, autenticação, painel, banco ou dependência pesada
  sem solicitação explícita.
- Prefira dependências já presentes e soluções da biblioteca padrão quando
  forem suficientes.
- Não introduza URLs HTTP ou segredos no repositório.
- Não edite arquivos gerados manualmente quando houver um gerador responsável.
- Não inclua `apps/ios/build/` ou outros artefatos locais de build em commits.
- Antes de editar, confira `git status` e mantenha mudanças não relacionadas
  intactas.
- Faça commit e push somente quando o usuário autorizar explicitamente.

## Checklist antes de entregar

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run build:landing
git status --short --branch
```

Para mudanças no iOS, acrescente o build e os testes do Xcode. Para mudanças na
blocklist, valide também o seed embutido e confirme que o manifesto aponta para
arquivos existentes.

Consulte os detalhes específicos em `README.md`, `apps/ios/README.md`,
`apps/landing-page/README.md` e `tools/blocklists/README.md`.
