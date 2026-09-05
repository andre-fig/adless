# Instruções gerais do Adless

O Adless é um app iOS de bloqueio de anúncios/rastreadores por DNS, com assinatura
StoreKit. Somente DNS passa pelo serviço; não há conta, login ou proxy de tráfego.

## Mapa e arquitetura

| Escopo | Responsabilidade / tecnologia |
| --- | --- |
| `apps/ios/` | SwiftUI, StoreKit 2, Keychain, NetworkExtension `dns-settings` |
| `apps/dns-worker/` | TypeScript, Cloudflare Workers, KV `AUTH`, DO `STATS`/`AUTHORITY`, JWS Apple |
| `apps/landing-page/` | React, Vite, TypeScript, Tailwind; site estático no desenho Railway |
| `tools/blocklists/` e `tools/dns-worker/` | Python; geração, validação e preparação da lista edge |
| `tools/ios/`, `tools/dns/`, `tools/appstore/`, `tools/sentry/` | Verificações e operação especializada |
| `.github/workflows/`, `.githooks/`, `tools/dev/` | Automação e verificações locais |
| `docs/` | Explicações e procedimentos canônicos |

O iOS configura `NEDNSSettingsManager`/`NEDNSOverHTTPSSettings`. O Worker autoriza
credenciais, bloqueia na edge e consulta Cloudflare DoH, com Quad9 sequencial.
StoreKit/JWS alimenta a autorização no KV e no DO de assinatura. Railway não
participa das consultas DNS. Não reintroduza Packet Tunnel, DNS Proxy, DNS local,
App Group, `.appex`, APIs privadas ou serviços fora dessa arquitetura sem decisão
explícita de escopo.

## Antes de trabalhar

- Execute `git status --short --branch`; identifique alterações locais e arquivos não versionados.
- Use `rg --files` e `rg` para localizar instruções, arquivos e símbolos antes de criar conteúdo.
- Leia o `AGENTS.md` mais próximo e a documentação canônica do assunto. Instruções
  específicas prevalecem dentro de seu escopo; instruções explícitas do usuário
  prevalecem sobre estes arquivos.
- Preserve alterações locais do usuário. Não restaure, limpe, descarte ou sobrescreva
  trabalho preexistente. Se houver sobreposição, entenda o diff e faça a menor edição.
- Código/configuração local comprovam **Implemented**, nunca publicação remota.
  **Deployed** exige evidência de publicação; **Verified** exige teste/inspeção com
  escopo definido; **Pending** identifica o que falta confirmar ou executar.

## Segurança e autorização

- Nunca exponha secrets. Nunca insira tokens no código, logs, documentação ou
  comandos exibidos; não mostre valores de ambiente, JWS, credenciais ou URLs completas de DNS.
- Não registre QNAME, pacote DNS, IP ou identificadores Apple de clientes. Não
  confunda ausência de logs no código com ausência de metadados no provedor.
- Nunca faça deploy, commit ou push sem autorização explícita. Nunca altere
  Cloudflare, Railway, App Store Connect, domínio, DNS ou GitHub Secrets sem autorização.
- Alterações destrutivas de dados, capabilities/profiles, migrações remotas,
  publicação, novas integrações e mudança acima do limite da blocklist exigem
  autorização explícita. Não execute comandos Git destrutivos.
- Preserve concorrência, timeout, actions atuais, permissões mínimas e secrets mínimos nos workflows.
- Edite fontes/allowlist/geradores; artefatos de blocklist só podem ser atualizados
  pelos geradores. Consulte as instruções específicas antes de regenerar.

## Comandos e validação

Requisitos e efeitos colaterais em [DEVELOPMENT](docs/DEVELOPMENT.md).
`npm ci` instala dependências **e configura hooks locais**; não o rode em uma
tarefa restrita a documentação. `npm run dev:landing` inicia a landing.

Ordem recomendada, ajustando ao escopo autorizado:

```sh
git diff --check
python3 -B -m unittest discover -s tools/blocklists/tests -v
npm run test:dns-worker
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
git status --short --branch
```

Execute testes relevantes após mudanças. `lint`/`typecheck` cobrem a landing;
`build:dns-worker` faz checagem TypeScript. iOS acrescenta XCTest/build e,
para distribuição, verificações de archive/IPA. Documentação requer links,
caminhos, comandos, secrets e diff conferidos, sem gerar artefatos funcionais.
Informe arquivos alterados, validações executadas, falhas e limites da evidência.

## Fontes canônicas

[Arquitetura](docs/ARCHITECTURE.md) · [Segurança](docs/SECURITY.md) ·
[Desenvolvimento](docs/DEVELOPMENT.md) · [Testes](docs/TESTING.md) ·
[Operação Cloudflare](docs/dns-cloud.md) · [Apple e lançamento](docs/ios-release.md) ·
[Mapa completo da documentação](README.md)
