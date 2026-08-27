# DNS Cloud: operação e implantação

Este documento descreve o Worker em `apps/dns-worker/`. A referência canônica
de preços é [Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)
e [Durable Objects Pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/).
Os valores abaixo foram revisados em 26 de agosto de 2026; confirme-os antes de
contratar ou estimar orçamento.

## Topologia e limites

O hostname de produção é `dns.adless.app` e o endpoint é
`https://dns.adless.app/<token>/dns-query`. O DNS do iOS envia somente wire
messages RFC 8484. O Worker não aceita URL de destino, JSON para resolução,
DNS UDP/TCP, CORS ou métodos diferentes de GET/POST.

Limites implementados:

- token Base64URL opaco com 43 caracteres;
- POST e corpo DNS com no máximo 4 KiB;
- exatamente uma pergunta e no máximo 4.096 resource records;
- timeout de 1,5 s por upstream;
- rate limit padrão de 1.200 requisições por minuto por token/IP em memória;
- cache local do isolate limitado a 512 entradas e ao TTL recebido;
- respostas A/AAAA bloqueadas com TTL sintético de 60 segundos; a resposta HTTP
  continua `Cache-Control: no-store`;
- circuit breaker após três falhas do Cloudflare, aberto por 15 s.

O rate limiting por IP é uma medida de abuso na edge; o IP não é enviado para
o Durable Object nem armazenado pela aplicação. A proteção antifraude do token
é deliberadamente de baixo privilégio e não substitui autenticação de conta.

## Desenvolvimento local

```sh
npm ci
npm --prefix apps/dns-worker run prepare:blocklist
npm --prefix apps/dns-worker run build
npm --prefix apps/dns-worker run test
```

O build não precisa de dependências JavaScript adicionais. O teste usa mocks e
verifica POST/GET, content type, IDs, EDNS0, tipos DNS, correspondência exata e
por subdomínio, allowlist incorporada no artefato, fallback, NXDOMAIN,
SERVFAIL, cache, limites, rate limiting, checksum e ausência de DNS em texto
puro.

Para executar localmente com Wrangler, use `wrangler dev` e um token de teste.
O ambiente `staging` é separado:

```sh
npx --yes wrangler@4 dev --config apps/dns-worker/wrangler.toml --env staging
npx --yes wrangler@4 deploy --config apps/dns-worker/wrangler.toml --env staging
```

Staging deve ser fechado antes do deploy. Gere um token descartável de 256 bits
fora do repositório e grave-o somente como secret da Cloudflare:

```sh
openssl rand -base64 32 | tr '+/' '-_' | tr -d '=' \
  | npx --yes wrangler@4 secret put STAGING_ALLOWED_DNS_TOKEN \
      --env staging --config apps/dns-worker/wrangler.toml
```

O ambiente precisa ter `DEPLOYMENT_ENV=staging` e esse secret válido. O Worker
rejeita tokens diferentes antes de rate limit, cache, Durable Object ou
upstream; se o secret estiver ausente ou inválido, responde indisponível em vez
de abrir o resolvedor. Essa allowlist é exclusiva para staging e não representa
a autorização server-side de assinaturas da produção.

Não use o token real em shell history ou issue. A validação deve enviar um
query DNS conhecido, conferir `Content-Type: application/dns-message`, ID e
rcode, e nunca imprimir o hostname consultado.

## Deploy de produção

O workflow `.github/workflows/deploy-dns-worker.yml` requer os secrets:

- `CLOUDFLARE_API_TOKEN`: token mínimo para editar Workers, Durable Objects e
  a rota/zone necessárias;
- `CLOUDFLARE_ACCOUNT_ID`: conta Cloudflare do projeto.

O comando reproduzível é:

```sh
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
npm run build:dns-worker
npx --yes wrangler@4 deploy --config apps/dns-worker/wrangler.toml
```

O `wrangler.toml` declara o Worker `adless-dns`, a rota
`dns.adless.app/*`, o Durable Object `StatsDurableObject` e a migração SQLite.
No painel DNS, `dns.adless.app` deve estar na zone `adless.app` com o proxy
Cloudflare habilitado e certificado Universal SSL ativo. O hostname customizado
é uma configuração externa: confirme `dig +short dns.adless.app`, cadeia TLS e
o certificado com `openssl s_client -connect dns.adless.app:443
-servername dns.adless.app </dev/null`.

Não há credenciais Cloudflare neste repositório e o deploy não foi considerado
publicado até um run do workflow ou `wrangler deploy` retornar sucesso e o
smoke test abaixo passar.

## Smoke test

O smoke test opcional exige somente um token descartável no ambiente:

```sh
ADLESS_INSTALLATION_TOKEN='...' \
  python3 tools/dns/smoke_worker.py --url https://dns.adless.app
```

O script testa POST e GET, resposta wire, ID, content type e endpoint de
estatísticas sem registrar token, IP ou domínio. Use `--url` para staging.
Falha de DNS, TLS, status HTTP, formato ou estatística deve interromper o
check; nunca contorne TLS com `curl -k`.

## Blocklist, publicação e rollback

1. `generate_blocklist.py` baixa somente fontes HTTPS declaradas, normaliza e
   deduplica os nomes e aplica `allowlist.txt`.
2. A lista canônica, gzip, manifesto e checksum são validados antes da troca.
3. `prepare_blocklist.py` copia atomicamente a lista e cria metadata com versão,
   contagem e checksum do texto.
4. O Worker verifica schema, versão, ordenação, contagem e checksum no primeiro
   uso do isolate; uma lista inválida não resolve consultas.
5. O workflow cancela uma execução concorrente e só faz commit dos artefatos
   esperados.

Para rollback, selecione no Cloudflare o deployment anterior do Worker ou faça
checkout do commit conhecido e rode novamente os mesmos comandos. Não edite
`apps/dns-worker/data/blocklist.txt` manualmente. Antes e depois do rollback,
confira a versão/contagem/checksum no commit e execute o smoke test. Se uma
fonte baixar vazia ou variar acima do limite, interrompa, investigue a fonte e
use `--allow-large-change` somente após revisão.

## Autorização de assinatura

O código atual não possui uma base server-side de tokens autorizados e não
valida transações StoreKit na edge. Qualquer string Base64URL de 43 caracteres
é aceita; portanto o endpoint atual é um resolvedor aberto para fins de
produção e não deve ser publicado. StoreKit é validado apenas localmente pelo
app e a remoção por expiração só ocorre quando o app volta ao primeiro plano.

A solução mínima futura, sem conta, é um endpoint de controle separado que
receba o `Transaction.jwsRepresentation` de uma transação verificada, valide a
assinatura/estado com a App Store Server API ou certificados Apple e grave
somente `SHA-256(installation-token)`, `originalTransactionId`, estado,
`expiresAt` e revogação. App Store Server Notifications V2 atualizaria esse
registro; o caminho DNS consultaria um cache edge/DO e nunca a Apple por query.
O app deve reenviar a transação em compra, restauração e retorno ao primeiro
plano. Para não cortar a internet de uma instalação expirada, a política deve
ser explícita: após `expiresAt` o Worker pode continuar em uma janela curta de
grace e, depois, responder sem filtragem via upstream para manter resolução,
enquanto o app remove a configuração no próximo primeiro plano. Isso reduz a
eficácia antifraude; responder `SERVFAIL` preservaria a cobrança, mas pode
deixar um DNS ativo sem resolução. Essa escolha ainda não está implementada.

## Logs e observabilidade

`wrangler.toml` desativa explicitamente `observability` e URLs de preview. Não
há `console.log`, Logpush, Sentry ou dimensão de Analytics Engine no código.
Ainda assim, a conta Cloudflare pode ter regras de Logs, Logpush, WAF ou
tracing configuradas fora do repositório; elas precisam ser auditadas e
desativadas para este hostname. GET DoH inclui o pacote em `?dns=` e o token
no pathname, portanto metadados de requisição da plataforma podem revelar
esses campos mesmo sem log de aplicação. O uso de POST pelo cliente é
preferível quando controlável. A política pública não promete ausência de
logs de infraestrutura e identifica Cloudflare e os resolvedores como
processadores do fluxo.

## Rate limiting de produção

O limite por token/IP do Worker é apenas um fallback por isolate. No WAF da
zone `adless.app`, crie uma regra de Rate Limiting para
`http.host eq "dns.adless.app" and http.request.uri.path matches "^/[A-Za-z0-9_-]{43}/dns-query$"`,
característica `IP`, período 60 s, limite inicial 2.400 requests e mitigation
timeout 60 s, ação Block/HTTP 429. Crie outra para
`http.host eq "dns.adless.app" and http.request.uri.path eq "/v1/stats"`,
característica `IP`, 60 s, limite 60 e timeout 60 s. Ajuste com p95 real; não
use um limite baixo que puna CGNAT. O plano deve suportar os campos/limites
escolhidos; planos sem característica por token só conseguem limitar IP.
Mantenha a validação de método, tamanho, wire format e token no Worker. A
regra WAF não substitui o registro de assinatura: o token ainda é bearer e
pode ser compartilhado até ser revogado.

## Estatísticas permitidas

O caminho crítico agenda `POST` com `{"increment":1}` no Durable Object e não
aguarda a gravação para responder DNS. O objeto mantém `blockedTotal` e
`updatedAt` por instalação. `GET /v1/stats` exige exatamente o Bearer token e
retorna somente esses dois campos. Não use Analytics Engine, logs de request,
QNAME, pacote DNS, URL completa, token ou IP como dimensão.

O total é eventualmente consistente. O app conserva o maior valor conhecido
quando a API falha; contadores podem aparecer atrasados, nunca diminuir. Para
disponibilidade, monitore somente taxa de erro, latência, status, versão do
Worker, contagem de regras e consumo agregado. Alertas de custo devem observar
requests Worker/DO, CPU-ms, duração DO, storage e o limite de orçamento da
conta. Configure alertas no painel Cloudflare, pois o repositório não possui
token administrativo.

## Upstreams e incidentes

Os upstreams são `https://cloudflare-dns.com/dns-query` e
`https://dns.quad9.net/dns-query`. O Worker faz fallback sequencial apenas
quando há falha de transporte/TLS, HTTP não aceito, corpo vazio ou resposta DNS
inválida. NXDOMAIN e outras respostas DNS válidas são finais. Se ambos falham,
retorna SERVFAIL rapidamente; não usa resolver sem HTTPS.

Em incidente:

1. verifique `/healthz` e uma consulta sintética sem domínio sensível;
2. confira latência/status agregados do Worker e os dois upstreams;
3. se somente Cloudflare falhar, aguarde o circuit breaker ou confirme que
   Quad9 está respondendo;
4. se o endpoint falhar, preserve a configuração no iOS e corrija/rollback o
   Worker — o app não deve afirmar proteção ativa quando o iOS estiver
   desabilitado;
5. se a lista estiver suspeita, faça rollback do deployment e publique a última
   versão validada;
6. após a recuperação, execute smoke test em mais de uma região e registre
   apenas versão, latência agregada e status.

Quando a assinatura expira, o app remove a configuração DNS localmente; falha
temporária de stats não remove proteção. Redes com captive portal, bloqueio de
DoH, Private Relay, “Limitar Rastreamento de Endereço IP”, outra VPN ou perfil
DNS podem substituir o resolver. Documente o resultado real, sem prometer que
o Adless prevalece nessas situações.

## Secrets e rotação

O app não contém token administrativo, credencial Cloudflare ou segredo global.
Para rotacionar `CLOUDFLARE_API_TOKEN`, crie o novo token com permissões mínimas,
teste um deploy staging, substitua o secret do GitHub, execute produção e só
então revogue o token antigo. O token de instalação não é rotacionado em massa.
Ele é aleatório, fica no Keychain com `ThisDeviceOnly` e não é migrado para um
novo aparelho; no mesmo aparelho, o Keychain pode sobreviver à desinstalação do
app. Esta versão ainda não possui endpoint de exclusão ou registro server-side
de tokens. Em abuso, aplique bloqueio/rate limit na edge e considere invalidar
os tokens afetados por uma mudança de produto, sem expor tokens nos logs.

## Latência e custo

Meça POST e GET a partir de regiões diferentes (América do Sul, América do
Norte, Europa e Ásia), em Wi‑Fi e rede móvel, registrando apenas p50/p95,
status, tamanho da resposta e versão do Worker. Não registre QNAME ou IP no
artefato de teste.

Estimativa mensal em Workers Paid, com 30 dias, uma leitura de stats diária,
1 ms de CPU Worker por requisição DNS, 2 ms de duração DO a 128 MiB por
incremento, SQLite DO e duas escritas de storage por bloqueio. O plano inclui
10 milhões de requests Worker e 30 milhões de CPU-ms; excedentes são
US$0,30/milhão e US$0,02/milhão. SQLite DO inclui 1 milhão de requests,
25 bilhões de rows lidas, 50 milhões de rows escritas e 400.000 GB-s; os
excedentes são US$0,15/milhão de requests, US$0,001/milhão de rows lidas,
US$1,00/milhão de rows escritas e US$12,50/milhão de GB-s. Os 5 GB-month de
SQLite são suficientes para os dois pequenos valores por instalação nos
volumes abaixo; o tamanho real ainda precisa ser medido.

Cada célula abaixo é `custo / writes DO` com TTL 0 (cada bloqueio observado
gera duas escritas):

| Usuários | Consultas/usuário/dia | 10% | 25% | 40% |
| ---: | ---: | ---: | ---: | ---: |
| 50 | 1.000 | US$5,00 / 0,30M | US$5,00 / 0,75M | US$5,00 / 1,20M |
| 50 | 3.000 | US$5,00 / 0,90M | US$5,02 / 2,25M | US$5,12 / 3,60M |
| 50 | 5.000 | US$5,00 / 1,50M | US$5,13 / 3,75M | US$5,30 / 6,00M |
| 50 | 10.000 | US$6,58 / 3,00M | US$6,91 / 7,50M | US$7,25 / 12,00M |
| 100 | 1.000 | US$5,00 / 0,60M | US$5,00 / 1,50M | US$5,03 / 2,40M |
| 100 | 3.000 | US$5,00 / 1,80M | US$5,19 / 4,50M | US$5,39 / 7,20M |
| 100 | 5.000 | US$6,58 / 3,00M | US$6,91 / 7,50M | US$7,25 / 12,00M |
| 100 | 10.000 | US$11,30 / 6,00M | US$11,98 / 15,00M | US$12,65 / 24,00M |
| 1.000 | 1.000 | US$11,31 / 6,00M | US$11,99 / 15,00M | US$12,66 / 24,00M |
| 1.000 | 3.000 | US$31,41 / 18,00M | US$33,44 / 45,00M | US$57,46 / 72,00M |
| 1.000 | 5.000 | US$51,51 / 30,00M | US$79,89 / 75,00M | US$128,26 / 120,00M |
| 1.000 | 10.000 | US$111,76 / 60,00M | US$208,51 / 150,00M | US$305,26 / 240,00M |
| 10.000 | 1.000 | US$111,89 / 60,00M | US$208,63 / 150,00M | US$305,38 / 240,00M |
| 10.000 | 3.000 | US$432,88 / 180,00M | US$723,13 / 450,00M | US$1.013,38 / 720,00M |
| 10.000 | 5.000 | US$753,88 / 300,00M | US$1.237,63 / 750,00M | US$1.721,38 / 1.200,00M |
| 10.000 | 10.000 | US$1.556,38 / 600,00M | US$2.523,89 / 1.500,00M | US$3.491,39 / 2.400,00M |

TTL 60 reduz os eventos observados somente quando o resolvedor do aparelho
reutiliza a resposta e deixa de enviar a consulta novamente ao Worker. Se `h`
é a fração de bloqueios servidos pelo cache do cliente, use `B × (1-h)` para
os eventos e requests DO e `D - B × h` para requests/CPU do Worker. Se o
resolvedor não reutilizar a resposta, TTL 60 não reduz o caminho de origem.
Como `h` não é medido pelo projeto, não há valor honesto único para TTL 60.
Com `h=50%` no cenário 1.000 usuários/1.000 consultas/25%, o custo estimado
cai de US$11,99 para US$10,30; com 10.000 usuários cai de US$208,63 para
US$116,01. TTL 0 não reduz o custo de requests Worker e aumenta a frequência
de eventos DO; TTL 60 aceita até 60 s de retenção de uma decisão de bloqueio,
sem cache HTTP público.

O custo de storage, observabilidade, WAF, domínio, impostos, upstreams e
planos Enterprise não está incluído quando não há cobrança aplicável; a
retenção real de SQLite e a taxa `h` precisam ser medidas antes de contratar.

Referências de protocolo e upstream: [Cloudflare DoH API](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/), [Cloudflare wireformat](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/#wireformat), [Quad9 FAQ](https://quad9.net/support/faq/).
