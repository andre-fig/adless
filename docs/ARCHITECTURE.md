# Arquitetura do Adless

**Implemented — código local.** Este documento descreve responsabilidades e
invariantes. A revisão publicada e os recursos remotos precisam de evidência
separada em [dns-cloud](dns-cloud.md) e [ios-release](ios-release.md).

## Dois fluxos independentes

```text
iPhone / DNS escolhido pelo iOS
  → Cloudflare Worker
      → reconhecer credencial no KV AUTH
      → resolver autorização no DO AUTHORITY, quando aplicável
      ├─ desconhecida / papel errado: rejeitar antes de DO, cache DNS e upstream
      ├─ conhecida sem acesso ou bloqueio pausado em STATS: Cloudflare DoH → Quad9 (pass-through)
      └─ assinatura e bloqueio ativos: blocklist/cache
           ├─ bloqueada: resposta local + incremento best effort em STATS
           ├─ cache válido: resposta com transaction ID atual
           └─ permitida sem cache: Cloudflare DoH → Quad9 em falha

StoreKit → Transaction JWS + AppTransaction JWS quando disponível
  → POST /v1/authorization/register
  → verificar assinatura/cadeia Apple, produto, bundle, ambiente, datas e replay
  → ordenar estado no DO AUTHORITY → derivar tokens DNS/stats
  → KV AUTH (hashes, vínculo de instalação e estado da assinatura)
  → par de tokens na resposta → commit Keychain → configuração DNS do iOS

App Store Server Notifications V2 → POST /v1/notifications/apple
  → verificar JWS → ordenar evento no DO AUTHORITY → projetar estado no KV AUTH
```

Os dois provedores upstream usam HTTPS. Cloudflare é primário; Quad9 é fallback
sequencial, não consulta paralela. DNS válido, inclusive NXDOMAIN, encerra a
tentativa. Se ambos falham, o Worker retorna SERVFAIL. Não há fallback em texto
puro nem garantia de internet quando toda a infraestrutura DNS está indisponível.

Railway serve a landing e os artefatos públicos de blocklist. O gerador prepara
a cópia embutida no Worker antes da publicação; nem o Worker nem o app baixam
essa lista durante uma consulta. Railway não participa da resolução nem da
autorização. Tráfego geral de sites, vídeos, mensagens e downloads não atravessa Adless.

## Responsabilidades e fontes

| Componente | Símbolos e responsabilidade |
| --- | --- |
| [AdlessApp.swift](../apps/ios/Adless/AdlessApp.swift) | `AppViewModel`: concilia StoreKit, autorização, DNS real e apresentação |
| [SubscriptionManager.swift](../apps/ios/Adless/Services/SubscriptionManager.swift) | Produtos, compras, restauração, entitlement e transações verificadas |
| [InstallationTokenStore.swift](../apps/ios/Adless/Services/InstallationTokenStore.swift) | UUID de instalação, nonce persistido e commit atômico de credenciais no Keychain |
| [DNSSettingsManager.swift](../apps/ios/Adless/Managers/DNSSettingsManager.swift) | Instalar, reler e remover `NEDNSOverHTTPSSettings` com `NEDNSSettingsManager` |
| [handler.ts](../apps/dns-worker/src/handler.ts) | Endpoints, autorização, rate limit, blocklist/cache, fallback e stats |
| [dns.ts](../apps/dns-worker/src/dns.ts) / [blocklist.ts](../apps/dns-worker/src/blocklist.ts) | Wire format DNS, TTL/ID e matching por nome/sufixo |
| [authorization.ts](../apps/dns-worker/src/authorization.ts) / [apple-jws.ts](../apps/dns-worker/src/apple-jws.ts) | Verificação JWS, emissão, replay, migração e estados de assinatura |
| [stats.ts](../apps/dns-worker/src/stats.ts) | `StatsDurableObject`: contadores/preferência de bloqueio por instalação **e**, em objetos separados, autoridade da assinatura |
| [Gerador](../tools/blocklists/generate_blocklist.py) / [preparador](../tools/dns-worker/prepare_blocklist.py) | Fonte OISD Small, allowlist, artefatos validados e cópia edge |

## DNS e estado apresentado pelo iOS

O Xcode tem somente `Adless` e `AdlessTests`; o entitlement de NetworkExtension
permitido é `dns-settings`. O manager usa `matchDomains = [""]` e
`matchDomainsNoSearch = true`. Salvar não equivale a habilitar: `isEnabled` é
somente leitura e a aprovação final pertence ao usuário em Ajustes.

`AppViewModel.protectionIsConfirmed` exige assinatura, credenciais locais,
bloqueio habilitado no Worker, ausência de autorização pendente e
`DNSSettingsState.enabled`.
Esse estado exige o endpoint das credenciais atuais; um perfil Adless antigo
habilitado é `staleEnabled` e não confirma proteção. Primeiro plano, notificações
de configuração e retorno das operações provocam nova leitura. Pausar ou perder
acesso preserva o perfil DNS; o Worker encaminha consultas sem aplicar a lista.
Esse critério local não mede disponibilidade ou bloqueio real do serviço remoto.

O app guarda UUID de instalação, nonce aleatório e credenciais no Keychain
`AfterFirstUnlockThisDeviceOnly`, sem derivar identidade de IDFA/IDFV/hardware.
O par atual é derivado no Worker por HMAC, não gerado livremente pelo cliente.
O nonce é persistido antes da requisição: mesma transação/nonce recupera o mesmo
par, enquanto uma rotação exige transação admitida e novo nonce. Migração v1
da mesma transação exige prova dos dois tokens antigos. O `installationId` estável preserva stats.
Detalhes e estados de falha ficam no [README iOS](../apps/ios/README.md).

## Autorização e disponibilidade

`authorizeToken` reconhece o hash e papel no KV e lê o registro da instalação
**antes** de consultar o DO de autoridade. Credencial corrente consulta/semeia a
autoridade serializada; desconhecida não chega ao DO. O DO participa da decisão
de autorização: a regra não é “nenhum DO antes da autorização”. A regra é
“nenhum cache DNS, contador STATS ou upstream antes da decisão”.

Assinatura expirada, revogada ou reembolsada permite somente DNS pass-through;
reembolso é representado como estado `revoked`. Cancelar renovação mantém
acesso até o prazo pago. Grace period pode estender o prazo; billing retry
isoladamente não concede acesso. Tokens DNS substituídos continuam conhecidos
em pass-through; stats substituído é recusado. Esse compromisso preserva
resolução após perda da resposta de rotação, mas não revoga o uso do upstream
de um DNS token vazado. Consulte [SECURITY](SECURITY.md).

Falha do DO após reconhecimento no KV degrada DNS para pass-through e nega
stats. Falha inicial lançada pelo KV só pode usar uma credencial reconhecida
recentemente no mesmo isolate, durante a janela de dez minutos de
`authorizeWithAvailability`; essa memória comprova reconhecimento, nunca
assinatura ativa. Ausência de cache ou cache vencido resulta em erro; KV
retornando registro ausente rejeita o token. Erro de leitura do registro legado,
após reconhecimento, segue a degradação da autoridade. Não transformar
desconhecido em fail-open.

KV é eventualmente consistente e não oferece commit de múltiplas chaves.
Emissão grava mappings/índices e usa o registro de instalação como ponto final
de commit. `AUTHORITY` ordena eventos de assinatura, inclusive refund/revoke,
para não depender apenas desses índices. A autoridade não torna todo o KV
fortemente consistente. Production/Sandbox têm chaves e objetos distintos no
Worker oficial; Xcode usa outro Worker e bindings isolados. JWS Sandbox
com evidência de AppTransaction não prova criptograficamente origem TestFlight.

## Blocklist, cache e contadores

Matching usa nome exato e sufixos por label, lowercase/ASCII/Punycode. A allowlist
é aplicada na geração, não por endpoint de edição em runtime. Respostas
bloqueadas IN A/AAAA usam `0.0.0.0`/`::`; outros tipos recebem NODATA. ID/pergunta
e EDNS são preservados, TTL bloqueado é 60 segundos.

O cache em memória é por `installationId` e mensagem com ID zerado, preservando
flags/tipo/classe/EDNS. Expira pelo menor TTL considerado pelo parser, atualiza
TTL restante e reescreve o transaction ID. HTTP usa `no-store`. Pass-through
não usa blocklist, cache DNS, rate limit ativo nem contador. Limites, circuit
breaker e detalhes de TTL ficam em [dns-cloud](dns-cloud.md).

Cada bloqueio agenda incremento best effort de `STATS`. A UI guarda total e
baseline diário em [BlockingStatsStore.swift](../apps/ios/Adless/Services/BlockingStatsStore.swift)
e não reduz o total diante de falha/reset remoto. O número diário é estimado
a partir de leituras do total, não uma série temporal de consultas no servidor.

## Dados e limites de confiança

| Local | Conteúdo implementado |
| --- | --- |
| iPhone | Credenciais/UUID/nonce no Keychain; snapshot de assinatura e totais locais |
| KV `AUTH` | Hashes de tokens/nonce, mappings, UUIDs de instalação, IDs Apple, produtos, ambientes, datas, estados, claims/índices e marcadores de notificação |
| DO `STATS` | Objetos por instalação com `blockedTotal` e `updatedAt` |
| DO `AUTHORITY` | Objetos por assinatura/ambiente com eventos e estado ordenado, incluindo IDs Apple |
| Memória do Worker | Lista, queries/respostas em cache, hashes token/IP para limites e reconhecimento recente |
| Provedores | Cloudflare recebe requisição HTTPS/IP e consulta; upstream recebe consulta permitida; Sentry recebe diagnósticos configurados |

Cliente e tokens bearer não provam pagamento; JWS verificado e autoridade da
assinatura concedem acesso. Cloudflare termina TLS e permanece dentro do limite
de confiança. Ausência de histórico DNS persistido no código não significa
anonimato, ausência de metadados ou dados totalmente anônimos. Inventário,
retenção, logs e procedimentos estão em [SECURITY](SECURITY.md).

## Decisões e alternativas abandonadas

- DNS nativo delega resolução ao iOS sem manter processo do app aberto.
- Packet Tunnel, DNS Proxy e DNS local estão fora da arquitetura atual: o
  projeto não tem providers, interfaces, rotas ou extensão para executá-los.
  Parsers Swift residuais são utilitários testados, não um resolvedor instalado.
- Filtragem edge centraliza a política sem distribuir listas para cada iPhone.
- StoreKit mantém compra/pagamento na Apple; o Worker verifica autorização sem
  criar conta ou backend de pagamentos. IDs de assinatura continuam necessários.
- Dois tokens restringem papéis; nonce persistido/derivação idempotente evita
  instalar um token intermediário após retry. DO ordena eventos; KV mapeia credenciais.

Private Relay, outra VPN/perfil DNS, captive portal e políticas de rede podem
interferir. DNS não bloqueia todo anúncio servido pelo mesmo domínio do conteúdo.
Testes necessários e lacunas estão em [TESTING](TESTING.md); pendências de código
encontradas na auditoria ficam em [REPOSITORY_AUDIT](REPOSITORY_AUDIT.md).
