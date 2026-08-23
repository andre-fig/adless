# Guia de testes

Este documento descreve os testes automatizados e manuais do Adless, além dos
limites de cada ambiente. O objetivo é validar o bloqueio sem transformar
falhas de uma fonte, de um upstream DNS ou de uma assinatura em perda de
conectividade ou de proteção.

## Pirâmide de validação

```text
pre-commit       verificações rápidas dos arquivos staged
pre-push         testes direcionados aos caminhos alterados
pull request     validação final da landing, blocklist ou iOS
iPhone físico    Network Extension e DNS real
App Store/Sandbox produtos, cobrança, trial e renovação
```

O simulador é adequado para UI, build e XCTest, mas não comprova a
interceptação DNS do sistema. O acesso à internet real não é usado nos testes
unitários.

## Comandos de validação geral

Na raiz do monorepo:

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run typecheck
npm run build:landing
```

Para alterações em workflows:

```sh
actionlint .github/workflows/*.yml
```

Para alterações iOS, acrescente o build ou XCTest correspondente. Antes de
entregar, confirme o estado do worktree com `git status --short --branch`.

Não declare um teste como aprovado sem executar o comando correspondente.

## Landing page

### Testes automatizados

O workspace `apps/landing-page` usa ESLint type-aware e TypeScript strict:

```sh
npm run lint
npm run typecheck
npm run build:landing
```

Esses comandos verificam, respectivamente, regras de código, tipos nos
projetos da aplicação e da configuração do Vite, e a build de produção.

### Teste manual

Para trabalhar na interface:

```sh
npm run dev:landing
```

Verifique manualmente:

- navegação entre home, termos, privacidade e suporte;
- responsividade em viewport móvel e desktop;
- tema claro/escuro;
- seletor de idioma;
- links e arquivos públicos da blocklist;
- ausência da blocklist no bundle JavaScript.

Depois da build, os arquivos públicos devem continuar acessíveis em:

```text
/blocklists/manifest.json
/blocklists/blocklist.txt.gz
/blocklists/blocklist.txt
```

## Pipeline da blocklist

### Testes unitários Python

Execute:

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
```

Os testes usam fixtures e mocks, sem download da OISD ou de qualquer fonte
externa. A suíte cobre:

- entrada de domínio simples;
- formato hosts com `0.0.0.0` e `127.0.0.1`;
- formato Adblock utilizado pela OISD Small;
- comentários, linhas vazias e pontos finais;
- normalização para minúsculas;
- conversão de IDN para ASCII/Punycode;
- deduplicação e ordenação determinística;
- allowlist e remoção de descendentes;
- rejeição de regras executáveis não suportadas;
- rejeição de HTML, fonte vazia e conteúdo inválido;
- gzip determinístico;
- manifesto, versão baseada em conteúdo e checksum;
- preservação da versão anterior em variação excessiva;
- rejeição de gzip corrompido.

### Geração e validação local

```sh
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
python3 tools/blocklists/validate_blocklist.py \
  --seed apps/ios/Adless/Resources/SeedBlocklist.txt
```

O comando de geração acessa a fonte HTTPS configurada e deve ser executado
somente quando a atualização real for desejada. Não edite os artefatos ou o
seed manualmente.

Para uma variação grande que foi revisada e considerada legítima:

```sh
python3 tools/blocklists/generate_blocklist.py \
  --allow-large-change \
  --sync-seed
```

Depois compare o manifesto, a quantidade de domínios e o diff da lista antes
de publicar.

## XCTest do iOS

### Executar a suíte

Com o simulador `iPhone 16` disponível:

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Para listar destinos:

```sh
xcrun simctl list devices available
```

O target `AdlessTests` inclui o app e a extensão necessários para compilar os
testes. Se o nome do simulador variar, use o identificador exibido por
`simctl`.

### Cobertura atual

`apps/ios/AdlessTests/BlocklistTests.swift` cobre:

- parsing canônico e correspondência de subdomínios;
- correspondência de domínio completo e domínios-pai com `Set<String>`;
- maiúsculas e ponto final;
- rejeição de falsos sufixos, como `ads.example.com.evil`;
- IDN já convertido para Punycode;
- matriz de sites que devem permanecer acessíveis;
- matriz de domínios de publicidade que devem ser bloqueados;
- lista canônica não ordenada e conteúdo inválido;
- gzip válido, tamanho esperado e payload corrompido;
- atualização válida e manifesto sem mudança de conteúdo;
- checksum inválido e download interrompido;
- preservação da lista anterior após falha;
- acesso ativo, grace period e expiração da assinatura;
- formatação do trial do StoreKit;
- persistência atômica do estado de assinatura;
- contadores diários e all-time de bloqueios.

Os testes de rede substituem `URLSession` com `StubURLProtocol` e usam
diretórios temporários. Eles não acessam GitHub Pages.

## Testes manuais no iPhone

### Preparação

Antes de testar DNS real:

1. selecione um Team válido no Xcode;
2. confirme o App Group `group.com.orbeworks.adless` nos targets `Adless` e
   `AdlessDNSProxy`;
3. instale o app em um iPhone físico;
4. confirme que a assinatura de desenvolvimento ou Sandbox está ativa;
5. desative outros perfis VPN/DNS que possam interferir no resultado.

O estado de ativação deve sobreviver ao fechamento e à reabertura do app. Ao
abrir, a tela de preparação deve verificar o status existente antes de exibir
`Protection Active` ou `Protection Off`.

### Matriz funcional

Teste cada cenário com proteção desligada e ligada quando aplicável:

| Cenário | Resultado esperado |
| --- | --- |
| Ativar com assinatura válida | botão muda imediatamente e DNS Proxy conecta |
| Desativar | DNS Proxy é desligado e o tráfego volta ao DNS do sistema |
| Fechar e reabrir com proteção ativa | app abre diretamente como ativo |
| Sem internet ao ativar | lista local funciona; ativação não depende do download |
| Manifesto indisponível | lista anterior ou seed continua ativa |
| Assinatura expirada com a extensão ativa | DNS Proxy permanece em pass-through, sem bloquear domínios; a internet continua funcionando |
| Assinatura expirada ao abrir o app | app mostra Premium access required e não ativa uma nova sessão de bloqueio |
| Compra concluída | drawer fecha e o app tenta ativar a proteção |
| Atualização válida da lista | nova lista é instalada sem arquivo parcial |
| Atualização inválida | lista anterior continua ativa |

### Domínios permitidos e bloqueados

A matriz automatizada usa estes domínios de controle:

Devem continuar resolvendo:

```text
www.google.com
web.whatsapp.com
www.instagram.com
www.facebook.com
www.youtube.com
```

Devem ser bloqueados quando a lista contém a regra correspondente:

```text
googlesyndication.com
adsrvr.org
criteo.com
pubmatic.com
adnxs1.com
```

Esses domínios de publicidade são alvos DNS, não necessariamente páginas
visualizáveis no navegador. Para um resultado confiável, verifique o log do
DNS Proxy e o comportamento de uma consulta DNS, além de tentar o carregamento
em um app que use o domínio.

### Correspondência de nomes

Confirme os seguintes casos no XCTest e, quando necessário, em uma build do
dispositivo:

- `ads.example.com` bloqueia `cdn.ads.example.com`;
- `ADS.EXAMPLE.COM.` é tratado como `ads.example.com`;
- `ads.example.com.evil` não é bloqueado pela regra `ads.example.com`;
- `xn--bcher-kva.example` corresponde à forma canônica Punycode;
- um domínio sem regra de pai continua permitido;
- um IP, `localhost` ou regra com wildcard inválido não entra na lista.

## DNS UDP e TCP

O provider aceita os dois tipos de flow:

- UDP: mantém o flow retido, lê datagrams continuamente e reutiliza a conexão
  upstream durante a vida do flow;
- TCP: processa mensagens DNS com prefixo de tamanho e mantém uma conexão TCP
  upstream com buffer limitado.

Valide manualmente:

1. várias consultas em sequência na mesma sessão;
2. abertura simultânea de várias consultas por um app;
3. consulta permitida com upstream primário disponível;
4. fallback para `8.8.8.8` quando `1.1.1.1` falha;
5. resposta rápida `SERVFAIL` quando os dois upstreams não respondem;
6. encerramento do app ou da rede sem flow preso;
7. retomada após alternar entre Wi-Fi e rede celular.

O app não deve deixar páginas permitidas aguardando silenciosamente. Também
não deve enviar HTTP, HTTPS ou conteúdo de aplicativos ao upstream; somente
consultas DNS são encaminhadas.

Para acompanhar os logs no Mac conectado ao dispositivo:

```sh
log stream --style compact --level debug \
  --predicate 'subsystem == "com.orbeworks.adless"'
```

Os logs úteis normalmente aparecem nos processos `Adless` e
`AdlessDNSProxy`. Mensagens do `nesessionmanager` e `neagent` ajudam a
diagnosticar instalação, conexão e encerramento da Network Extension.

## StoreKit manual

### Configuração local

No scheme `Adless`, mantenha o arquivo `Adless.storekit` selecionado. Use
**Debug → StoreKit → Manage Transactions** para:

- comprar o plano mensal e anual;
- validar o trial de sete dias;
- renovar ou expirar uma transação;
- testar restauração de compra;
- limpar transações para repetir o fluxo.

Após uma compra válida, confirme que o drawer fecha e que o app tenta ativar a
proteção. Sem entitlement, o botão deve abrir o drawer em vez de iniciar o
DNS Proxy.

### Sandbox e produção

O arquivo `.storekit` não valida a configuração do App Store Connect. Para
testar Sandbox ou TestFlight, confirme externamente:

- produtos disponíveis para o app;
- mesmo Subscription Group;
- preços e territórios;
- trial de sete dias;
- usuário Sandbox;
- acordos e metadata da assinatura.

Não use credenciais reais em testes locais nem registre dados de pagamento nos
logs.

## Hooks e CI

`npm install` e `npm ci` ativam os hooks locais. O `pre-commit` é rápido; o
`pre-push` escolhe testes pelos arquivos alterados:

- blocklist: testes Python;
- landing: lint, typecheck e build;
- iOS: XCTest no simulador;
- workflows: `actionlint`.

O workflow `ios-tests.yml` roda em pull requests e manualmente. O workflow de
release não repete o XCTest: o teste local e o PR devem passar antes do
archive. `update-blocklist.yml` roda semanalmente e `deploy-pages.yml` publica
a landing e os artefatos estáticos na `main`.

Quando um workflow falhar, primeiro reproduza o comando localmente. Depois
verifique o log do job e o estado externo correspondente, como GitHub Pages,
App Store Connect, assinatura ou dispositivo.

## Como adicionar testes

### Python

- prefira `unittest` e fixtures pequenas;
- faça mock de `download_https` para evitar internet;
- use diretórios temporários para artefatos;
- verifique que uma falha não substitui a versão válida anterior.

### Swift

- use `XCTest` no target `AdlessTests`;
- use `StubURLProtocol` para respostas de manifesto e payload;
- use `FileManager.temporaryDirectory` para storage;
- teste sucesso, falha, retry, checksum e preservação de estado;
- não dependa de uma assinatura real ou de um iPhone conectado.

### Teste manual

Documente no pull request quando uma alteração exigir:

- iPhone físico;
- Wi-Fi ou rede celular;
- produto Sandbox/TestFlight;
- configuração do App Store Connect;
- execução de GitHub Actions.

## Checklist de entrega

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run typecheck
npm run build:landing
```

Para mudanças iOS, execute o `xcodebuild` de `AdlessTests`. Para mudanças de
workflow, execute `actionlint`. Informe os resultados exatos na entrega e não
confunda build bem-sucedido com teste de DNS real no dispositivo.
