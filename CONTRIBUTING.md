# Contribuindo com o Adless

Obrigado por contribuir. O Adless é um monorepo com um aplicativo iOS, uma
landing page estática e um pipeline de blocklist. Este guia define o fluxo
esperado para alterações, testes e pull requests.

## Antes de começar

Leia as instruções do repositório (`AGENT.md` ou `AGENTS.md`) e a documentação
da área que será alterada:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): arquitetura e fluxos;
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md): setup e desenvolvimento local;
- [`docs/TESTING.md`](docs/TESTING.md): matriz de testes;
- [`apps/ios/README.md`](apps/ios/README.md): configuração iOS e StoreKit;
- [`apps/landing-page/README.md`](apps/landing-page/README.md): landing page;
- [`tools/blocklists/README.md`](tools/blocklists/README.md): blocklist;
- [`docs/ios-release.md`](docs/ios-release.md): publicação do app.

Preserve alterações existentes no worktree e não misture mudanças não
relacionadas no mesmo commit ou pull request.

## Arquitetura que deve ser preservada

- Não adicione backend, banco de dados, login, autenticação própria, Railway,
  painel administrativo ou servidor de assinatura.
- Compras são feitas exclusivamente por StoreKit 2 e App Store Connect.
- O app usa um Packet Tunnel local apenas para DNS; não o transforme em túnel de tráfego ou
  servidor VPN externo sem uma decisão explícita do produto.
- A blocklist é gerada pelo pipeline Python e distribuída como arquivo estático
  pelo GitHub Pages.
- Não coloque domínios manualmente no código Swift ou na extensão DNS.
- Não adicione URLs HTTP, segredos, chaves `.p8`, certificados, perfis de
  provisionamento ou artefatos de build ao repositório.

## Fluxo de branches

Use o fluxo:

```text
branch de trabalho → develop → pull request → main
```

Não faça push diretamente para `main`. Antes de iniciar:

```sh
git switch develop
git pull --ff-only origin develop
git switch -c nome-curto-da-tarefa
```

Mantenha a branch atualizada antes de abrir o PR. Se houver conflito, resolva
preservando a intenção dos dois lados e rode novamente os testes relevantes.

## Setup local

Na raiz do monorepo:

```sh
npm ci
npm run setup:hooks
```

O `npm ci` já ativa os hooks por meio do script `prepare`; o segundo comando é
útil para reativação manual. Para desenvolvimento iOS, também é necessário
Xcode, um Team configurado e, para DNS real, um iPhone físico com o App Group
`group.com.orbeworks.adless` e a capability Packet Tunnel configurados nos targets.

## Como organizar alterações

### Landing page

Use React, TypeScript strict, Tailwind e os componentes existentes. Execute:

```sh
npm run lint
npm run typecheck
npm run build:landing
```

Mantenha arquivos públicos em `apps/landing-page/public/`. A blocklist não
pode ser importada para o bundle JavaScript.

### iOS

Verifique os targets `Adless`, `PacketTunnel` e `AdlessTests` antes de alterar
entitlements, capabilities, App Group ou configurações do Xcode. Use o App
Group para dados compartilhados e escritas atômicas para arquivos consumidos
pela extensão.

Alterações no DNS devem preservar:

- busca em `Set<String>` e correspondência por domínio e domínios-pai válidos;
- leitura contínua e retenção dos flows UDP/TCP;
- timeout, fallback para o DNS secundário e resposta `SERVFAIL` quando ambos
  falharem;
- proteção offline com a última lista válida ou o seed embutido.

Execute o XCTest no simulador:

```sh
xcodebuild \
  -project apps/ios/Adless.xcodeproj \
  -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

O simulador não substitui o teste de DNS em um iPhone físico.

### Blocklist

Altere fontes em `tools/blocklists/sources.json` e exceções em
`tools/blocklists/allowlist.txt`. Não edite os artefatos gerados manualmente.
Depois execute:

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
python3 tools/blocklists/validate_blocklist.py \
  --seed apps/ios/Adless/Resources/SeedBlocklist.txt
```

Use `--allow-large-change` somente após revisar uma alteração legítima acima
do limite configurado. Testes unitários não podem depender da internet.

## Hooks e validação

Os hooks são parte do fluxo normal e devem permanecer ativos:

- `pre-commit`: verifica diff staged, workflows, sintaxe Python e lint rápido
  da landing conforme os caminhos alterados;
- `pre-push`: executa testes Python, validação completa da landing, XCTest ou
  `actionlint` de acordo com os arquivos enviados.

Para uma alteração ampla, execute:

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run typecheck
npm run build:landing
```

Acrescente `xcodebuild` para mudanças iOS e `actionlint` para mudanças em
`.github/workflows/`. Não use `--no-verify` para esconder uma falha; se for
indispensável, registre o motivo e execute a verificação equivalente.

## Commits

Use mensagens curtas, no imperativo, com um prefixo de área quando possível:

```text
feat: add subscription state recovery
fix: preserve DNS response on upstream timeout
test: cover IDN suffix matching
docs: update development guide
ci: reduce duplicate iOS jobs
chore: refresh generated blocklist
```

Cada commit deve ser coerente e não deve incluir secrets, arquivos de build ou
mudanças não relacionadas. Para blocklists geradas, inclua somente os caminhos
esperados pelo pipeline.

## Pull requests

Um PR deve conter:

1. descrição objetiva do problema e da solução;
2. área afetada e possíveis impactos;
3. comandos de teste executados e seus resultados;
4. indicação explícita quando a validação exigiu iPhone físico, Sandbox,
   App Store Connect ou GitHub Actions;
5. screenshots ou gravação curta para mudanças visuais da landing ou do app;
6. nota sobre migrações de entitlements, capabilities ou configuração externa.

Antes de solicitar revisão:

```sh
git status --short --branch
git diff --check
```

Confirme que não há arquivos acidentais ou secrets no diff. Responda aos
comentários de revisão com novos commits claros ou faça squash conforme a
política do repositório.

## Workflows e publicação

Ao modificar `.github/workflows/`:

- mantenha `concurrency` com cancelamento da execução anterior;
- mantenha timeouts e permissões mínimas;
- evite triggers duplicados e jobs macOS desnecessários;
- use caminhos explícitos, nunca `git add .` ou `git add -A`;
- não exponha secrets em logs ou outputs;
- rode `actionlint` e confira a execução no GitHub depois do merge.

O release iOS é disparado por mudanças relevantes na `main`; o workflow faz
preflight, archive, export, validação, upload e submissão no App Store Connect.
Os testes iOS são antecipados pelo hook local e pelo PR, e não devem ser
duplicados no release sem justificativa.

## Segurança e dados sensíveis

Não publique:

- chaves App Store Connect ou arquivos `.p8`;
- certificados, provisioning profiles ou dados de assinatura;
- logs com dados de conta, pagamento ou identificadores pessoais;
- blocklists ou fixtures que contenham segredos;
- URLs internas ou endpoints HTTP não autorizados.

Se um segredo for incluído acidentalmente, pare o trabalho, não o reutilize e
avise o responsável para revogação/rotação. Remover o arquivo em um commit
posterior não é suficiente.

## Checklist final

- [ ] alteração limitada ao escopo do PR;
- [ ] documentação atualizada quando o comportamento ou arquitetura mudou;
- [ ] testes automatizados relevantes executados;
- [ ] teste manual documentado quando necessário;
- [ ] hooks passaram;
- [ ] nenhum secret ou artefato de build no diff;
- [ ] `git status` limpo, exceto alterações locais não relacionadas.
