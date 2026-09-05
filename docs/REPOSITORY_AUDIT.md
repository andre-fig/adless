# Auditoria do repositório e da documentação

Última verificação: **2026-09-04, UTC−3**. Auditoria do workspace em `develop`,
incluindo alterações locais preexistentes. Este relatório é evidência pontual,
não declaração de aprovação de produção. Somente Markdown foi autorizado.

## Escopo e método

**Verified:** inventário inicial de 202 arquivos versionados/não ignorados,
incluindo 16 Markdown existentes e o único `AGENTS.md` então presente, na raiz.
Foram inspecionados estrutura, scripts npm, fontes das três aplicações, projeto
Xcode/schemes/StoreKit/entitlements/localizações, testes, ferramentas Python e
shell, hooks, cinco workflows, configuração Cloudflare e documentação anterior.
Assets foram inventariados e referências/JSON conferidos; isso não substitui
revisão visual no dispositivo. Dependências instaladas e artefatos locais
ignorados não foram tratados como código proprietário a auditar.

O Git começou com 23 arquivos modificados e três não versionados: 21 arquivos
não Markdown e cinco documentos. Antes de editar, foram guardados hashes de
todos os arquivos inventariados, diff inicial e cópias dos Markdown fora do
workspace. A comparação final distingue as mudanças desta tarefa do trabalho
anterior. No encerramento surgiram duas edições externas à tarefa, descritas
na seção Git; foram preservadas e a documentação foi reconciliada. A convenção
predominante era português; ela foi mantida conforme a exceção de idioma solicitada.

**Implemented** = confirmado no código/configuração local.
**Deployed** = há evidência de publicação do componente indicado.
**Verified** = inspeção/teste realizado, dentro do limite explicitado.
**Pending** = não confirmado, não implementado ou ainda dependente de ação manual.

## Arquivos criados e atualizados

**Criados — seis Markdown:**

- [apps/ios/AGENTS.md](../apps/ios/AGENTS.md)
- [apps/dns-worker/AGENTS.md](../apps/dns-worker/AGENTS.md)
- [apps/landing-page/AGENTS.md](../apps/landing-page/AGENTS.md)
- [tools/blocklists/AGENTS.md](../tools/blocklists/AGENTS.md)
- [SECURITY.md](SECURITY.md)
- [REPOSITORY_AUDIT.md](REPOSITORY_AUDIT.md), este relatório operacional.

**Atualizados — 16 Markdown:**

| Arquivos | Finalidade final |
| --- | --- |
| [AGENTS.md](../AGENTS.md), [README.md](../README.md) | Regras gerais curtas e índice hierárquico |
| [CONTRIBUTING.md](../CONTRIBUTING.md), [copilot-instructions.md](../.github/copilot-instructions.md) | Entrada para fontes canônicas, sem segundo conjunto de regras |
| [TODO.md](../TODO.md) | Pendências e ideias preservadas com evidência/escopo distintos |
| [THIRD_PARTY_BLOCKLISTS.md](../THIRD_PARTY_BLOCKLISTS.md) | Proveniência, licença e atribuição ainda não confirmada |
| [README iOS](../apps/ios/README.md), [README landing](../apps/landing-page/README.md), [README blocklists](../tools/blocklists/README.md) | Referência de cada implementação/ferramenta |
| [ARCHITECTURE.md](ARCHITECTURE.md), [DEVELOPMENT.md](DEVELOPMENT.md), [TESTING.md](TESTING.md) | Arquitetura, setup/automação e testes sem misturar evidência remota |
| [dns-cloud.md](dns-cloud.md), [ios-release.md](ios-release.md) | Operação Cloudflare e lançamento Apple |
| [app-store-submission.md](app-store-submission.md), [app-store-privacy-questionnaire.md](app-store-privacy-questionnaire.md) | Metadata e revisão manual de privacidade |

Nenhum documento foi excluído. Segurança ganhou fonte própria porque não havia
documento canônico do modelo de ameaças; este relatório separa resultados
temporários das instruções permanentes. Os outros assuntos permaneceram nos
documentos existentes.

## Fontes canônicas e consolidação

O [índice do README](../README.md) é o mapa completo. Arquitetura pertence a
`ARCHITECTURE.md`; dados/ameaças/rotação a `SECURITY.md`; setup/hooks/workflows a
`DEVELOPMENT.md`; cobertura e matriz física a `TESTING.md`; operação Cloudflare
a `dns-cloud.md`; publicação Apple a `ios-release.md`. READMEs locais detalham
somente a aplicação/pipeline. Submission e App Privacy mantêm finalidades
próprias, com links para os runbooks.

Conteúdo de contribuição e Copilot foi reduzido a encaminhamento operacional.
Informações técnicas úteis das cinco edições locais de documentação foram
preservadas ou incorporadas aos canônicos: nonce persistido, commit único,
retry, migrações, perfil antigo habilitado, autoridade serializada, pass-through,
gates de UI e inspeção estrita de archive/profile/IPA. Não houve restauração dos
documentos para a versão de HEAD.

A tabela antiga de custo foi substituída com justificativa no runbook: omitira
KV e AUTHORITY por consulta. Dimensões, fórmula de volume e roteiro de medição
foram preservados; preços/estimativas sem base atual não são orçamento válido.
O item antigo “falhas e trocas de rede concluídas” passou a distinguir mocks
existentes de testes físicos pendentes. Ideias de Safari/visual foram mantidas.

## Contradições corrigidas na documentação

| Afirmação anterior | Evidência de código / correção |
| --- | --- |
| Um installation token usado também para stats | `DNSStatsAPIClient`, `InstallationTokenStore` e `authorizeToken`: par separado por papel; par atual derivado no Worker |
| O app baixa manifesto/lista do Railway | Não há downloader iOS; `worker.ts` importa artefato gerado. Parsers Swift residuais são helpers de testes |
| Nenhum DO participa antes de autorizar | `authorizeToken` reconhece KV e consulta/semeia `AUTHORITY`; somente desconhecido é recusado antes de qualquer DO |
| Durable Object guarda apenas contadores | `StatsDurableObject` também atende objetos de autoridade com eventos/IDs Apple, usando binding e nomes distintos |
| Persistência é só total e hashes; ausência de conta prova dados sem vínculo | `AuthorizationRecord`, índices e autoridade armazenam metadados/IDs vinculáveis; App Privacy precisa de revisão por categoria |
| Trial/grupo/preços já configurados remotamente | `Adless.storekit` e Product IDs comprovam fixtures/expectativas locais, não App Store Connect |
| Prova antiga transmitida apenas uma vez | Tentativa de migração pode repetir a prova em retries até commit; a exigência do Worker se refere à mesma transação v1 |
| Rotação invalida todo uso do DNS token antigo | `authorizeToken` conserva mapping antigo em pass-through; stats antigo é negado |
| Marcador de notificação KV elimina reprocessamento | `processAppleNotification` aplica a autoridade antes do marcador; idempotência efetiva está no DO |
| Existe apenas um Worker remoto de produção | Há um alvo no TOML; a conta e a revisão publicada não foram inspecionadas |
| Hooks/workflows garantem todos os testes/publicação | Hooks dependem de instalação/caminhos; workflows iOS/Worker não executam suas suítes e upload não equivale a aprovação/publicação |
| Workflow exige exclusivamente um dSYM | Exige app dSYM e ausência de `.appex.dSYM` superior; não proíbe todo outro dSYM |
| Copilot proíbe validação remota de recibo | Regra obsoleta conflitava com JWS server-side existente; substituída por referência à arquitetura real |
| Parser da fonte aceita só regras Adblock exatas | `_candidate_from_line` também aceita domínios simples; atribuição/pipeline corrigidos |
| Testes provam downloads HTTPS, todos os timeouts e cache aquecido antes de rejeitar desconhecido | Mocks e asserções cobrem subconjuntos; lacunas explicitadas em `TESTING.md`, incluindo fixture com relógio incoerente |

## Limitações técnicas registradas, sem implementação

Cada item é **Pending**; os documentos indicados contêm símbolos, contexto e
critérios. Nenhum achado autoriza alteração funcional durante esta tarefa.

| Área | Limitação confirmada no código | Fonte canônica |
| --- | --- | --- |
| Assinaturas/UI | Paywall anuncia trial fixo; `makeOption` não consulta elegibilidade | [ios-release](ios-release.md) |
| Grace iOS | Snapshot pode conceder grace, mas autorização exige transação não expirada | [README iOS](../apps/ios/README.md) |
| Proteção/localização | Gate local não mede saúde remota; não há timer de expiração dedicado; faltam strings usadas pela UI; flags macOS/xros não provam suporte | [README iOS](../apps/ios/README.md) |
| TestFlight/release | Allowlist Sandbox local de build não acompanha número dinâmico; release não define `API_PRIVATE_KEYS_DIR` como TestFlight | [ios-release](ios-release.md) |
| Público/legal | Compra única versus assinaturas, persistência incompleta, downloader inexistente, promessas absolutas, localização parcial e terceiros do site | [README landing](../apps/landing-page/README.md) / [App Privacy](app-store-privacy-questionnaire.md) |
| Autorização | KV sem transação multi-chave/timeout explícito; limites de replay por índice não linearizável; nenhuma prova criptográfica exclusiva de TestFlight | [SECURITY](SECURITY.md) |
| Disponibilidade/abuso | Rate limit por isolate; pass-through/registro/notificações fora do limitador; falha de infraestrutura pode interromper DNS | [SECURITY](SECURITY.md) |
| Retenção/rotação | Hashes antigos e eventos sem expurgo; rotação DNS conserva upstream; secret não tem key ring/recuperação automática | [SECURITY](SECURITY.md) |
| Tratamento HTTP | JSON é carregado antes do limite final; falhas de infra podem parecer 401/400; health não testa dependências e stats sem binding pode retornar zero | [SECURITY](SECURITY.md) / [dns-cloud](dns-cloud.md) |
| Blocklists | Allowlist não vence ancestral; verificador não compara todo conteúdo cruzado; limites declarados não aplicados; troca atômica só por arquivo | [README pipeline](../tools/blocklists/README.md) |
| Automação | Sem suíte geral em PR; deploys omitem checks/caminhos; push do gerador com token padrão não encadeia publicação automaticamente | [DEVELOPMENT](DEVELOPMENT.md) |
| Testes | JWS positivo simulado; sem runtime/consistência KV real; smoke aceita SERVFAIL; teste de “cache populado” usa credencial expirada | [TESTING](TESTING.md) |

## Evidência remota e informações não confirmadas

**Deployed / Verified, alcance limitado:** em `2026-09-05T01:53:12Z`, GET sem
credenciais no health público retornou HTTP 200, `status=ok` e
`environment=production`. O manifesto público da landing retornou HTTP 200,
versão `vccdec93540613cc1` e 58.216 domínios. Seus metadados correspondem aos
artefatos locais conferidos. Essas duas leituras não fizeram consultas DNS nem
acessaram dados de instalações. URLs e resultado operacional ficam em
[dns-cloud](dns-cloud.md).

**Pending:** deployment/version ID, revisão Worker/site publicada, bindings e
migrations efetivos, secrets/permissões, configuração/retenção de logs, plano,
faturamento, domínios/DNS, branch protections e execução de workflows. Não foram
consultados dados KV/DO ou configurações autenticadas de Cloudflare/Railway/GitHub.

**Pending:** App Store Connect/Apple Developer, produtos/trial/grupo/preços,
Notifications V2 recebidas, profiles/certificados/capabilities, TestFlight,
revisão/disponibilidade pública e compra Production. Nome comercial/SKU prévios
e atribuição pessoal da fonte OISD foram preservados como não confirmados.
Settings, DNS físico e localizações reais também exigem aparelho. As referências
oficiais Apple/Cloudflare/GitHub/OISD citadas nos documentos esclarecem regras;
não comprovam configuração da conta Adless.

## Mapa dos AGENTS.md

| Instrução | Escopo | Regras próprias que justificam o arquivo |
| --- | --- | --- |
| [Raiz](../AGENTS.md) | Todo o repositório | Segurança, autorização, Git sujo, comandos e precedência |
| [iOS](../apps/ios/AGENTS.md) | `apps/ios/` | UI verdadeira, StoreKit/Keychain, DNS nativo, APIs públicas e entitlements |
| [Worker](../apps/dns-worker/AGENTS.md) | `apps/dns-worker/` | Autorização antes de resolução, tokens, pass-through, privacidade e regressões DNS |
| [Landing](../apps/landing-page/AGENTS.md) | `apps/landing-page/` | Claims públicos, tradução, terceiros e artefatos estáticos |
| [Blocklists](../tools/blocklists/AGENTS.md) | `tools/blocklists/` | Geração exclusiva, limites, allowlist e continuidade de resolução |

`tools/dns-worker/`, demais ferramentas e workflows continuam sob a raiz e os
runbooks vinculados; o arquivo em `tools/blocklists/` não herda automaticamente
para um diretório irmão. Instruções específicas prevalecem no seu escopo, sem
substituir autorização explícita do usuário.

## Validações executadas

| Verificação | Resultado e limite |
| --- | --- |
| Suíte Python com `python3 -B -m unittest discover -s tools/blocklists/tests -v` | **Verified:** 10 testes passaram; sem bytecode no repositório |
| Suíte Worker | **Verified:** 78 testes passaram, em 60 casos principais; mesmo tsconfig/suíte oficial compilados com `--outDir` temporário externo e executados por `node --test` |
| `npm run lint` | **Verified:** zero erros, oito avisos preexistentes `react-refresh/only-export-components` |
| `npm run typecheck` | **Verified:** projetos app/node da landing passaram |
| `npm run build:dns-worker` | **Verified:** checagem TypeScript passou, sem emissão |
| Build landing | **Verified:** `npm --workspace @adless/landing-page run build -- --outDir` com diretório temporário externo passou; aviso esperado de saída fora do projeto |
| Validador blocklist e conferência cruzada | **Verified:** texto público/edge idêntico, gzip/texto/checksums/versão coerentes; nenhum artefato regenerado |
| `actionlint` | **Verified:** cinco workflows passaram, sem alteração de YAML |
| Ferramentas iOS/Sentry/ASC | **Verified:** sintaxe shell dos quatro scripts, compilação Python em memória e `--help` ASC; JSON/referências de assets inspecionados |
| Links, caminhos e comandos | Conferência final registrada abaixo; caminhos de exemplos de saída/variáveis são parâmetros, não arquivos obrigatórios existentes |
| Busca de secrets e revisão do diff | Revisão dos Markdown e padrões de credenciais, sem imprimir valores sensíveis; alterações anteriores comparadas com baseline |
| iOS build/XCTest/archive/IPA | **Pending:** não executados nesta tarefa documental; fontes dos testes e verificadores inspecionadas. Xcode pode resolver packages/escrever arquivos fora do escopo |
| Smoke autenticado/Apple real | **Pending:** não executado; apenas os dois GET públicos descritos acima |

Não foi executado `npm ci`, gerador, preparador ou dry-run Wrangler. Os testes
que geram produtos usaram diretórios temporários externos; nenhum artefato
funcional do workspace foi escrito por esta tarefa. Não confundir sucesso das suítes com as
lacunas de cobertura documentadas.

## Git, preservação e resumo do diff

**Verified:** esta tarefa atualizou 16 Markdown e criou seis; nenhum arquivo
foi removido. Dos 186 arquivos não Markdown inventariados, 184 permaneceram
idênticos ao baseline, incluindo 19 dos 21 já sujos/não versionados. Os dois
restantes receberam edições externas durante o encerramento; não foram escritos
nem revertidos pelos agentes desta auditoria. Cinco documentos já sujos foram
atualizados preservando informação útil, conforme a consolidação acima.

Edições externas observadas em `2026-09-05T02:12:47Z`:

- [wrangler.toml](../apps/dns-worker/wrangler.toml): a allowlist local de builds
  Sandbox passou de `2` para `2,6`. O runbook foi ajustado; não há evidência de
  publicação desse valor. Modificação do arquivo observada às `02:11:37Z`.
- [verify_distribution_profile.sh](../tools/ios/verify_distribution_profile.sh):
  o profile agora deve conter `dns-settings`, podendo autorizar valores de
  Network Extension adicionais; o app assinado continua restrito somente a
  `dns-settings`. O runbook foi ajustado e a sintaxe revalidada. Modificação
  do arquivo observada às `02:10:58Z`.

Essas alterações impedem afirmar igualdade total do workspace com o início,
mas não são mudanças funcionais desta tarefa. A preservação significa que
nenhuma edição externa foi descartada ou substituída.

Resumo do diff documental: regras distribuídas em cinco AGENTS curtos, índice
raiz, runbooks corrigidos, modelo de segurança e relatório separados, evidência
local/remota marcada e pendências técnicas registradas. `git diff --stat` não
inclui arquivos novos não versionados; o status completo também inclui código
preexistente e não deve ser atribuído à auditoria.

**Verified — conferência final:** 327 links relativos sem destino ausente;
21 caminhos citados a partir da raiz conferidos, além dos destinos dos links;
comandos comparados aos scripts/configuração; busca de padrões de secrets sem
ocorrências; nenhuma referência por número de linha. Diff documental completo
revisado por escopo e contra as cópias iniciais. `git diff --check` passou.
Comparação SHA-256: as únicas diferenças não Markdown são as duas edições
externas descritas acima; nenhum arquivo inventariado desapareceu. Os oito
avisos de lint permaneceram sem correção funcional.

`git status --short --branch` ao encerrar:

```text
## develop...origin/develop
 M .github/copilot-instructions.md
 M AGENTS.md
 M CONTRIBUTING.md
 M README.md
 M THIRD_PARTY_BLOCKLISTS.md
 M TODO.md
 M apps/dns-worker/src/authorization.ts
 M apps/dns-worker/src/handler.ts
 M apps/dns-worker/src/stats.ts
 M apps/dns-worker/src/types.ts
 M apps/dns-worker/test/worker.test.ts
 M apps/dns-worker/wrangler.toml
 M apps/ios/Adless/AdlessApp.swift
 M apps/ios/Adless/ContentView.swift
 M apps/ios/Adless/Managers/DNSSettingsManager.swift
 M apps/ios/Adless/Resources/Info.plist
 M apps/ios/Adless/Resources/Localizable.xcstrings
 M apps/ios/Adless/Services/DNSCloudConfiguration.swift
 M apps/ios/Adless/Services/DNSStatsAPIClient.swift
 M apps/ios/Adless/Services/InstallationTokenStore.swift
 M apps/ios/Adless/Services/SubscriptionManager.swift
 M apps/ios/AdlessTests/BlocklistTests.swift
 M apps/ios/README.md
 M apps/landing-page/README.md
 M docs/ARCHITECTURE.md
 M docs/DEVELOPMENT.md
 M docs/TESTING.md
 M docs/app-store-privacy-questionnaire.md
 M docs/app-store-submission.md
 M docs/dns-cloud.md
 M docs/ios-release.md
 M tools/blocklists/README.md
 M tools/ios/verify_archive.sh
 M tools/ios/verify_ipa.sh
?? apps/dns-worker/AGENTS.md
?? apps/ios/AGENTS.md
?? apps/ios/AdlessTests/DNSSettingsManagerTests.swift
?? apps/ios/AdlessTests/InstallationTokenStoreTests.swift
?? apps/landing-page/AGENTS.md
?? docs/REPOSITORY_AUDIT.md
?? docs/SECURITY.md
?? tools/blocklists/AGENTS.md
?? tools/ios/verify_distribution_profile.sh
```

**Nenhum deploy, upload, submissão, alteração remota, commit ou push foi
realizado. Somente Markdown foi alterado pela tarefa.** A leitura do health e
do manifesto não publicou ou modificou recursos.

## Manutenção recomendada

- Atualizar a fonte canônica junto de mudanças de contrato; AGENTS devem conter
  invariantes e links, sem deployment IDs, números de build ou resultados datados.
- Antes de publicação, registrar separadamente revisão local, deployment/version,
  ambiente Apple, testes executados e pendências manuais sanitizadas.
- Repetir links/caminhos/comandos/diff e testes pertinentes; não concluir cobertura
  pelo nome do teste nem configuração remota pela presença de um YAML/TOML.
- Abrir tarefas próprias para limitações registradas, priorizando proteção real,
  autorização/disponibilidade, elegibilidade e alinhamento de privacidade antes
  de distribuição. Não resolver pendências técnicas silenciosamente em documentação.
- Manter material Apple/público/traduções coerente com dados e comportamento do
  código; conservar o histórico documental útil ao revisar evidências operacionais.
