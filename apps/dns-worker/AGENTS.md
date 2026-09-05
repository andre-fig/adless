# Instruções do DNS Worker

Escopo: `apps/dns-worker/`. Complementa o [AGENTS da raiz](../../AGENTS.md).
Estado remoto e procedimentos: [operação Cloudflare](../../docs/dns-cloud.md).
Autorização, dados e ameaças: [segurança](../../docs/SECURITY.md).

## Fontes e invariantes

- [src/worker.ts](src/worker.ts): entrada e export de `StatsDurableObject`;
  [src/handler.ts](src/handler.ts): `createDNSWorker`, endpoints e resolução;
  [src/dns.ts](src/dns.ts): parser, respostas e cache;
  [src/blocklist.ts](src/blocklist.ts): normalização e correspondência por sufixo.
- [src/authorization.ts](src/authorization.ts): `authorizeToken`, registro,
  rotação e Notifications V2; [src/apple-jws.ts](src/apple-jws.ts): ES256 e
  cadeia Apple; [src/stats.ts](src/stats.ts): contadores **e** autoridade da
  assinatura; [src/types.ts](src/types.ts): contratos dos bindings.
- Endpoints públicos: `GET/HEAD /healthz`, `GET/POST /{dnsToken}/dns-query`,
  `GET /v1/stats`, `POST /v1/authorization/register` e
  `POST /v1/notifications/apple`. Stats exige Bearer separado do token DNS.
- Primeiro reconheça hash, papel e instalação no KV `AUTH`. Token desconhecido
  deve ser rejeitado **antes de qualquer Durable Object, cache DNS ou upstream**.
  Para token corrente conhecido, `AUTHORITY` participa da autorização antes de
  bloquear, usar cache DNS ou acessar o objeto de métricas `STATS`.
- Ativo exige estado efetivo `active` e `accessUntil` futuro. Expiração,
  reembolso e revogação não tornam uma credencial conhecida desconhecida:
  DNS usa pass-through sem blocklist, cache DNS, rate limit ou stats; stats é
  negado. `refunded` não é enum: REFUND resulta em `revoked`. Cancelar renovação
  conserva acesso até o fim do período; grace period depende do evento Apple.
- Nunca transforme token desconhecido em fail-open. Falha do KV só admite
  pass-through com prova local recente de credencial conhecida; sem prova,
  retorna erro. Falha de `AUTHORITY` após reconhecer a instalação também remove
  bloqueio e nega stats. Não prometa internet em todas as falhas.
- Para consulta ativa: valide wire, consulte blocklist e cache, depois Cloudflare
  DoH primário e Quad9 sequencial. Preserve HTTPS, validação da resposta, timeout,
  SERVFAIL e transaction ID. Resposta DNS válida, inclusive NXDOMAIN, é final.
- Cache é memória do isolate, por instalação e pacote sem transaction ID;
  restaure o ID atual e TTL restante. HTTP permanece `Cache-Control: no-store`.
  Bloqueio A/AAAA usa endereço zero e TTL 60; outros tipos recebem resposta vazia.
- Allowlist é aplicada pelo gerador; não existe exceção dinâmica no Worker.
  Nunca edite `data/` manualmente. Fluxo canônico:
  [blocklists](../../tools/blocklists/README.md).

## Autorização e privacidade

- Preserve tokens DNS/stats derivados separadamente por HMAC, hashes SHA-256 no
  KV, nonce persistido no cliente, retry idempotente e migração schema v1/v2.
  Uma rotação conserva mappings antigos: DNS antigo fica pass-through e stats
  antigo é negado. Não apague hashes para “corrigir” conectividade.
- Preserve a separação Production/Sandbox em claims, índices e autoridade.
  Sandbox exige AppTransaction Apple correspondente e build permitido; habilitar
  Sandbox em uma variável não substitui essa prova. Isso não é App Attest.
- Notifications V2 verifica JWS externo e interno; ordenação/idempotência é no
  DO, antes do marcador KV. Preserve períodos, correções terminais e recuperações
  oficiais; replay não pode desfazer refund/revoke/expiration.
- Não persista nem registre token, nonce, JWS bruto, QNAME, pacote, IP ou URL
  de consulta. `STATS` recebe só incremento numérico por instalação;
  `AUTHORITY` persiste metadados de assinatura. Não descreva todos os DO como
  “somente contadores”. Rate limit token/IP é hash em memória, por isolate.
- [wrangler.toml](wrangler.toml) declara `AUTH`, `STATS`, `AUTHORITY` e migration
  SQLite `v1` para a mesma classe. Não recrie namespaces ou reescreva migration.
  Secret de derivação não é variável pública. Bindings locais não provam deploy.

## Validação e entrega

Da raiz: `npm run test:dns-worker`, `npm run build:dns-worker` e, ao alterar
listas, `python3 -B -m unittest discover -s tools/blocklists/tests -v` e
`python3 -B tools/blocklists/validate_blocklist.py`. O build só faz typecheck;
teste gera `dist-test/`. Execute apenas passos compatíveis com o escopo autorizado.

Dry-run: `npx --yes wrangler@4 deploy --dry-run --config apps/dns-worker/wrangler.toml`.
Deploy exige autorização explícita: `npm --prefix apps/dns-worker run deploy`
prepara artefatos e publica. Smoke e verificação remota segura estão no
[runbook](../../docs/dns-cloud.md); jamais passe tokens literais no comando.

Qualquer mudança em DNS/autorização/cache exige revisão conjunta dos arquivos
acima, testes de regressão para token desconhecido, expiração, falhas KV/DO e
upstreams, migração/rotação e preservação da resolução. Antes de distribuição,
exija o [roteiro físico de iPhone](../../docs/TESTING.md). Não deixe o iPhone
sem internet para impor assinatura. Registre limitações verificáveis; não
contorne testes removendo autorização ou validação de TLS.
