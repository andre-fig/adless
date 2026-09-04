# Arquitetura do Adless

## Topologia

```text
iPhone
  │ NEDNSSettingsManager + NEDNSOverHTTPSSettings
  ▼
https://adless-dns.adless-production.workers.dev/<dns-token>/dns-query
  │ Cloudflare Worker, blocklist em memória
  ├─ token desconhecido/revogado → rejeição antes de cache, DO e upstream
  ├─ token expirado → Cloudflare DoH sem bloqueio e sem estatística
  ├─ bloqueado → resposta DNS sintetizada, sem upstream
  └─ token ativo permitido → Cloudflare DoH
                   └─ falha transitória → Quad9 DoH
```

O iOS gerencia o DNS criptografado; o app não cria interface de rede, não
instala rota e não encaminha HTTP, HTTPS, vídeo, mensagens ou downloads. A
configuração usa o domínio completo (`matchDomains = [""]`) e o Worker é um
endpoint RFC 8484, não um proxy HTTP genérico.

## iOS

O projeto contém apenas os targets `Adless` e `AdlessTests`. O app usa a
capability `com.apple.developer.networking.networkextension` com o valor
`dns-settings`. Não há extensão, App Group, `.mobileconfig`, entitlement de
tráfego ou API privada.

`DNSSettingsManager` sempre chama `loadFromPreferences` antes de ler ou
alterar o estado. `saveToPreferences` cria/atualiza a configuração DoH e
`removeFromPreferences` a remove; `isEnabled` é somente leitura porque a
ativação final é autorizada pelo usuário em Ajustes. O app nunca usa um
booleano persistido como fonte de verdade. A notificação de alteração, o
primeiro plano e o estado real recarregado mantêm a UI coerente após reinício,
troca de rede ou remoção manual.

O app mantém um `installationId` UUID e dois tokens opacos de 32 bytes,
`dns-token` e `stats-token`, no Keychain com
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; não deriva de identidade,
IDFA, IDFV ou conta Apple. Após compra/restauração, envia somente o
`Transaction.jwsRepresentation` ao endpoint de autorização e grava os tokens
retornados. O Worker nunca grava os valores originais, apenas seus hashes.

O endpoint de autorização valida a cadeia X.509 e a assinatura ES256 do JWS
StoreKit 2, confere bundle ID, produto e ambiente, e registra a instalação no
KV `AUTH`. O endpoint de notificações valida App Store Server Notifications V2
e atualiza renovação, expiração, reembolso, revogação, billing retry e grace
period. Nenhum desses endpoints é consultado no caminho de cada query DNS.

## Serviço edge

`apps/dns-worker/src/dns.ts` valida cabeçalho, exatamente uma pergunta, nomes
com compressão segura, contagens, limites, EDNS0 e todos os tipos DNS sem
lista restritiva. POST exige `application/dns-message`; GET usa `dns` em
Base64URL. Erros estruturais retornam `FORMERR` quando há bytes suficientes.
Falha dos dois resolvedores retorna `SERVFAIL` em uma mensagem DNS válida.

`blocklist.ts` carrega a lista canônica em um `Set` e testa o nome completo e
cada sufixo de label. A comparação é lowercase, sem ponto final, com nomes
ASCII/Punycode; assim `sub.ads.example.com` corresponde a
`ads.example.com`, mas `notads.example.com` não corresponde.

Respostas bloqueadas usam o transaction ID recebido, repetem a pergunta e
TTL 60 segundos. A consulta não alcança upstream. A resposta A é `0.0.0.0`,
AAAA é `::` e outros tipos recebem NODATA. EDNS0 é preservado quando presente.

Consultas permitidas são enviadas sequencialmente para
`https://cloudflare-dns.com/dns-query` e, somente em timeout, falha TLS ou de
transporte, HTTP não aceito, corpo vazio ou DNS inválido, para
`https://dns.quad9.net/dns-query`. Uma resposta DNS válida, incluindo
NXDOMAIN, não dispara fallback. Não há DNS UDP/TCP em texto puro. O Worker
mantém um cache por instalação e wire query (ID zerado,
flags/tipo/classe/EDNS preservados) somente até o menor TTL recebido; cache negativo usa TTL de autoridade quando
presente. Um circuit breaker por isolate abre após três falhas primárias por
15 segundos.

## Blocklist

A fonte atual é OISD Small e a allowlist é aplicada por
`tools/blocklists/generate_blocklist.py`. A saída canônica é publicada na
landing e copiada para `apps/dns-worker/data/` por
`tools/dns-worker/prepare_blocklist.py`. O metadata inclui versão derivada do
conteúdo, contagem, checksum do texto e checksum do artefato público. O Worker
confere schema, versão, ordenação, contagem e checksum antes de resolver.

O workflow rejeita fonte vazia, lista inválida e variação acima do limite sem
`--allow-large-change`. Ele gera em diretório candidato e substitui cada
artefato validado atomically; uma versão anterior válida permanece disponível
para rollback no histórico de deploy.

## Estatísticas

Quando bloqueia, o Worker agenda uma escrita best effort em
`StatsDurableObject` com apenas `increment: 1`. O ID do Durable Object é
derivado do `installationId`, portanto a troca de credenciais mantém o
contador; seu armazenamento contém somente `blockedTotal` e `updatedAt`.
QNAME, pacote DNS e IP não são dimensões nem valores persistidos.

`GET /v1/stats` exige `Authorization: Bearer <stats-token>`; o `dns-token` é
rejeitado nesse caminho e o endpoint retorna `{ blockedTotal, updatedAt }`. O
app lê em primeiro plano e após ativação, preserva o último valor offline e
nunca reduz a UI.
Rate limiting é mantido na edge por janela curta, usando somente
`SHA-256(token):SHA-256(IP)` como chave em memória; token e IP brutos não são
registrados nem gravados. Em caso de falha temporária do KV, apenas uma
autorização positiva conhecida pode ser reutilizada por até 10 minutos e até
seu `accessUntil`; tokens desconhecidos continuam rejeitados.

Os tokens são credenciais bearer de baixo privilégio; a assinatura Apple é a
autorização server-side. Não há conta, login, Railway ou banco externo.

## Privacidade e interferências

Todas as consultas DNS escolhidas pelo iOS para o Adless passam pelo endpoint
HTTPS do serviço. Consultas bloqueadas não seguem para um resolvedor; as
permitidas seguem para Cloudflare DNS ou Quad9. O serviço não vende dados, não
usa consultas para publicidade e não mantém histórico de domínios. Cloudflare
é provedor da edge e os resolvedores aplicam suas próprias políticas. Logs de
aplicação não recebem QNAME, pacote DNS, token, IP ou URL completa.

Isso não promete anonimato, ocultação de IP, ausência absoluta de logs de
infraestrutura ou que o provedor de acesso não possa inferir destinos. Private
Relay, “Limitar Rastreamento de Endereço IP”, outro perfil DNS, outra VPN,
captive portal e políticas da rede podem substituir ou impedir o DNS salvo.
