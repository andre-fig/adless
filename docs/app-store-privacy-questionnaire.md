# App Privacy: inventário para revisão

Última verificação documental: 2026-09-04, código local. **Implemented** descreve
o que o código faz; **Pending** identifica validação do binary, dos provedores
ou do formulário. Nenhuma resposta do App Store Connect foi consultada ou salva.
Este documento é o pacote de evidências para preencher o questionário, não uma
afirmação de que as opções abaixo já foram aprovadas.

A Apple exige considerar dados do app e parceiros e distingue processamento
transitório de retenção, finalidade e vínculo com a pessoa/dispositivo. Ausência
de conta não basta para declarar dados sem vínculo. Aplicar os critérios de
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
ao inventário real antes de salvar o formulário.

## Evidências do código

| Componente | Implemented: tratamento observado | Pending antes de responder |
| --- | --- | --- |
| iOS / Keychain | UUID interno, dois bearers, IDs de transação e nonces atual/pendente em blob ThisDeviceOnly | Não caracterizar token como anonimato ou vínculo criptográfico ao dispositivo; conferir comportamento real após reinstalação |
| iOS / cache | Snapshot de assinatura e contadores numéricos em Application Support | Não confundir cache no dispositivo com retenção no backend |
| Autorização Worker | Recebe JWS de transação/AppTransaction, UUID e nonce; na migração, prova com credenciais anteriores | Classificar identificadores e dados de compra usados para funcionalidade/antifraude |
| KV `AUTH` | Registros de instalação e assinatura, produto/ambiente/status/prazos, IDs StoreKit, índices/replay e hashes de tokens/nonce | Não declarar que só existem hashes e um total; confirmar retenção e controles remotos |
| Durable Objects | `STATS` guarda agregado; `AUTHORITY` guarda autoridade de assinatura e ordenação de eventos | Considerar todos os objetos persistidos, não apenas o contador |
| Resolução DNS | Worker processa consultas; permitidas seguem para Cloudflare DoH ou Quad9. Não há histórico de consultas em KV/DO | Cache de respostas e infraestrutura podem reter dados temporários/metadados; verificar políticas e configuração efetiva |
| Sentry | Crash/performance e eventos técnicos; sem identidade de usuário definida pelo app | Rever SDK incluído no binary, identificadores/metadados padrão e configuração do projeto Sentry |
| Railway | Landing estática e páginas legais; o app atual não baixa manifesto/blocklist | Rever metadados do acesso ao site separadamente; não descrevê-lo como downloader iOS |

Fontes: [InstallationTokenStore](../apps/ios/Adless/Services/InstallationTokenStore.swift),
[clientes HTTP](../apps/ios/Adless/Services/DNSStatsAPIClient.swift),
[authorization.ts](../apps/dns-worker/src/authorization.ts),
[stats.ts](../apps/dns-worker/src/stats.ts),
[SentryConfiguration](../apps/ios/Adless/Services/SentryConfiguration.swift).
Arquitetura e dados persistidos: [ARCHITECTURE](ARCHITECTURE.md);
modelo de ameaças e privacidade: [SECURITY](SECURITY.md);
limites de cache/logs remotos: [dns-cloud](dns-cloud.md).

## Como classificar sem inventar garantias

- **Implemented:** há diagnósticos, agregado de uso e metadados persistidos de
  autorização. Não selecionar “nenhuma coleta” com base na ausência de login.
- **Pending:** revisar as categorias de diagnósticos, uso, identificadores e
  compras contra os campos atuais da Apple. Pagamento/cartão é tratado pela
  Apple; o backend Adless ainda armazena informações de assinatura/transação.
- **Pending:** avaliar vínculo por categoria; UUID da instalação, relação com
  transações e hashes associados permitem correlação. “Not linked to the user”
  não é conclusão demonstrada pelo código. Finalidade observada é funcionalidade
  e confiabilidade; não confundir essa classificação com rastreamento publicitário.
- **Implemented:** não há conta, login, SDK de anúncios ou código de associação
  para publicidade no app. **Pending:** confirmar também práticas dos parceiros
  antes de marcar “Tracking: No” como resposta final.
- **Implemented:** não há histórico de navegação/consultas em KV ou DO; isso não
  significa que nenhum QNAME ou pacote passe pela infraestrutura. O cache DNS
  contém respostas temporárias. Token DNS no path e pacote no parâmetro de GET
  DoH tornam URL completa sensível. Cloudflare e os upstreams processam dados
  para resolver consultas; confirmar retenção/logs remotos antes de responder
  sobre browsing history e metadados.

`AdlessSentry.start()` desabilita PII padrão, network tracking/breadcrumbs,
failed requests, auto breadcrumbs, screenshots, view hierarchy e tracing de
interações; traces têm amostragem configurada. `capture` sanitiza URLs, hosts e
IPs da descrição. Isso não prova ausência universal de dados identificáveis:
`SubscriptionManager` também usa `os_log` com descrições de erro, e o SDK e o
projeto remoto precisam de revisão. Nunca introduzir credenciais/JWS/nonce nos
erros, tags, logs ou comandos exibidos. **Pending:** confirmar descarte de IP,
retenção e acesso ao projeto Sentry. O upload opcional de dSYM inclui fontes,
conforme [ios-release](ios-release.md).

## Divergências de políticas e checklist final

**Pending no produto:** `SubscriptionView.swift` e o conteúdo legal da landing
ainda descrevem persistência como apenas agregado e hashes, sem todo o estado de
autorização/assinatura. O catálogo PT/EN/ES contém chave legal anterior que não
corresponde ao literal atual do Swift. A política web também atribui ao app um
download de blocklist que não existe. Essas divergências foram registradas;
nenhum texto do código-fonte foi alterado nesta auditoria.

Antes da submissão, conferir política pública, texto embutido e traduções com
este inventário e o binary assinado, revisar definições/políticas vigentes dos
provedores e só então salvar App Privacy mediante autorização. Registrar evidência
de validação sem payloads, dados de conta, identificadores de instalação ou
credenciais. Não há endpoint de exclusão de credenciais no Worker; não prometer
que desinstalar o app apaga estado no backend.

URL candidata da Privacy Policy e metadata: [app-store-submission](app-store-submission.md).
Instruções oficiais para salvar respostas:
[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
