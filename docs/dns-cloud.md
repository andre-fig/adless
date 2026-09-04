# DNS Cloud: operação e implantação

Este documento descreve o Worker em `apps/dns-worker/`. A referência canônica
de preços é [Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)
e [Durable Objects Pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/).
Os valores abaixo foram revisados em 26 de agosto de 2026; confirme-os antes de
contratar ou estimar orçamento.

## Topologia e limites

O hostname de produção é `adless-dns.adless-production.workers.dev` e o endpoint é
`https://adless-dns.adless-production.workers.dev/<dns-token>/dns-query`. O DNS do iOS envia somente wire
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

O build usa `jose`, `@peculiar/x509` e `reflect-metadata` para validar JWS/X.509
no runtime compatível com Workers. O teste usa mocks e verifica POST/GET,
content type, IDs, EDNS0, tipos DNS, correspondência exata e
por subdomínio, allowlist incorporada no artefato, fallback, NXDOMAIN,
SERVFAIL, cache, limites, rate limiting, checksum e ausência de DNS em texto
puro.

Os testes locais usam mocks. Existe somente o Worker remoto de produção,
publicado no subdomínio `workers.dev` da conta Cloudflare. Não use tokens reais
em shell history ou issue. A validação deve enviar um query DNS sintético,
conferir `Content-Type: application/dns-message`, ID e rcode, e nunca imprimir
o hostname consultado.

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

O `wrangler.toml` declara o Worker `adless-dns` em `workers.dev`, o Durable
Object `StatsDurableObject` e a migração SQLite. Não é necessário configurar
zone DNS ou certificado customizado; a Cloudflare fornece o HTTPS do
`workers.dev`. Confirme o endpoint com:

```sh
curl -i https://adless-dns.adless-production.workers.dev/healthz
```

Não há credenciais Cloudflare neste repositório e o deploy não foi considerado
publicado até um run do workflow ou `wrangler deploy` retornar sucesso e o
smoke test abaixo passar.

## Smoke test

O smoke test opcional exige somente um token descartável no ambiente:

```sh
ADLESS_DNS_TOKEN='...' ADLESS_STATS_TOKEN='...' \
  python3 tools/dns/smoke_worker.py --url https://adless-dns.adless-production.workers.dev
```

O script testa POST e GET, resposta wire, ID, content type e endpoint de
estatísticas sem registrar token, IP ou domínio.
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

`POST /v1/authorization/register` recebe `{ installationId,
transactionJWS }`. O Worker valida localmente a cadeia X.509 da Apple e a
assinatura ES256 do StoreKit 2, confere `com.orbeworks.adless`, os dois product
IDs e o ambiente, e grava no KV `AUTH` somente hashes SHA-256 dos dois tokens,
além do estado da assinatura. A resposta contém `dnsToken` e `statsToken` uma
vez para o app salvá-los no Keychain.

`POST /v1/notifications/apple` recebe o `signedPayload` das App Store Server
Notifications V2. O Worker valida a assinatura, deduplica pelo
`notificationUUID` e atualiza renovação, expiração, reembolso, revogação,
billing retry e grace period. Cancelamento de renovação não corta o acesso
enquanto `expiresDate` ainda estiver no futuro.

O caminho DNS calcula o hash do token, consulta apenas o KV e decide antes de
cache, Durable Object ou upstream. Token ativo bloqueia normalmente; token
emitido cuja validade acabou resolve via upstream sem bloqueio e sem stats;
token desconhecido, inventado ou revogado recebe 401. Apple e Railway nunca
são consultados em uma requisição DNS.

### Configuração manual Apple

No App Store Connect, configure App Store Server Notifications V2 em Production
e Sandbox com o endpoint
`https://adless-dns.adless-production.workers.dev/v1/notifications/apple`.
No Apple Developer, o App ID `com.orbeworks.adless` precisa deixar somente a
capability `dns-settings` e gerar um novo profile de distribuição. O profile
local antigo contém capabilities históricas e não deve ser usado para
TestFlight.

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

O limite por token/IP do Worker é apenas um fallback por isolate, mantido em
memória. Como o endpoint usa `workers.dev` sem zone própria, não há regra WAF
de zone neste repositório. Mantenha a validação de método, tamanho, wire format
e token no Worker. O token ainda é bearer e pode ser compartilhado até ser
revogado.

## Estatísticas permitidas

O caminho crítico agenda `POST` com `{"increment":1}` no Durable Object e não
aguarda a gravação para responder DNS. O objeto mantém `blockedTotal` e
`updatedAt` por instalação. `GET /v1/stats` exige exatamente o Bearer
`stats-token` e
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
valide o deploy localmente, substitua o secret do GitHub, execute produção e só
então revogue o token antigo. Os tokens de instalação são trocados após nova
autorização; seus hashes ficam no KV e os valores originais ficam no Keychain
com `ThisDeviceOnly`, sem migração para um novo aparelho. Em abuso, aplique
bloqueio/rate limit na edge e considere invalidar os tokens afetados por uma
mudança de produto, sem expor tokens nos logs.

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
