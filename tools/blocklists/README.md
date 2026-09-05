# Pipeline da blocklist

Fonte canônica de geração, validação e sincronização dos artefatos públicos e
da edge. Leia as [instruções do escopo](AGENTS.md) antes de alterar o pipeline.
**Implemented:** as operações abaixo estão no código local. Publicação requer
deployment separado; consulte [operação Cloudflare](../../docs/dns-cloud.md).

## Entradas e transformações

[sources.json](sources.json) habilita somente OISD Small por HTTPS, formato
`adblock`. Atribuição e revisão de licença ficam em
[THIRD_PARTY_BLOCKLISTS.md](../../THIRD_PARTY_BLOCKLISTS.md).
[allowlist.txt](allowlist.txt) é declarativa e contém apenas comentários no
estado auditado; não há exceções específicas habilitadas.

[generate_blocklist.py](generate_blocklist.py) usa somente a biblioteca padrão
Python. Símbolos principais:

| Símbolo | Contrato implementado |
| --- | --- |
| `download_https` | Exige URL HTTPS, rejeita destino final não HTTPS, corpo vazio, HTML/JSON identificado e download acima do limite |
| `normalize_domain`, `parse_domains` | Lowercase, normalização Unicode/Punycode, remoção de duplicatas; rejeitam nomes inválidos e sintaxe executável; ignoram IPs/nomes reservados |
| `_candidate_from_line` | Aceita regras de domínio Adblock e domínios simples; modo auto também aceita hosts. Não executa filtros baixados. |
| `apply_allowlist` | Remove domínio permitido e seus descendentes do conjunto; não remove ancestrais bloqueados |
| `canonical_text`, `deterministic_gzip` | Ordenação única, newline final, gzip sem nome e com `mtime=0` |
| `generate` | Confere contagem/variação, deriva `version` do SHA-256 do texto e preserva `generatedAt` se o gzip não mudar; valida candidato antes de substituir os arquivos |
| `validate_artifacts`, `validate_canonical_text` | Verificam formato, canonicalização, gzip, checksum, tamanhos e contagem |

A política local exige 10.000–200.000 domínios, fonte de 1.000–25.000.000
bytes e variação máxima de 35%. A variação é a diferença simétrica dos
conjuntos dividida pela contagem anterior, não só crescimento. Sem versão
anterior não existe comparação de variação.

## Artefatos e comandos

| Saída | Produtor |
| --- | --- |
| [manifest.json](../../apps/landing-page/public/blocklists/manifest.json), `blocklist.txt`, `blocklist.txt.gz`, `blocklist.sha256` no mesmo diretório | `generate_blocklist.py` |
| [apps/dns-worker/data/blocklist.txt](../../apps/dns-worker/data/blocklist.txt) | Gerador com `--sync-worker` e preparador |
| [apps/dns-worker/data/blocklist.meta.json](../../apps/dns-worker/data/blocklist.meta.json) | [prepare_blocklist.py](../dns-worker/prepare_blocklist.py) |

O manifesto contém SHA-256 do **gzip**; `textSHA256` da metadata da edge é o
hash do **texto**. `sourceSHA256` aponta ao checksum do gzip. `downloadUrl` é
relativa. `--sync-worker` copia apenas o texto: ainda é necessário preparar
metadata. O preparador valida a saída pública e sempre regrava texto/metadata.

Validação local sem regenerar:

```sh
python3 -B -m unittest discover -s tools/blocklists/tests -v
python3 -B tools/blocklists/validate_blocklist.py
cmp apps/landing-page/public/blocklists/blocklist.txt apps/dns-worker/data/blocklist.txt
```

Atualização, somente quando mudanças de artefatos estiverem no escopo:

```sh
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
npm run test:dns-worker
```

O gerador acessa a rede e escreve arquivos. `--config`, `--allowlist`,
`--output-dir`, `--worker-output` e `--timeout` permitem execução controlada;
não apontar fixtures para a saída de produção. `--allow-large-change` exige
revisão explícita dos domínios alterados e justificação. Nunca editar artefatos
à mão nem acrescentar consultas reais de usuários às fixtures.

## Automação e rollback

[update-blocklist.yml](../../.github/workflows/update-blocklist.yml) agenda
execução semanal, domingo às 03:17 UTC, além de dispatch manual. Roda testes,
gera e valida; rejeita mudanças fora dos seis arquivos esperados e faz
commit/push somente desses arquivos. Disparar esse workflow exige autorização
para suas escritas no Git. O comportamento de encadeamento de deploys e as
lacunas dos workflows ficam em [DEVELOPMENT.md](../../docs/DEVELOPMENT.md).

Preservar o conjunto completo anterior em histórico/revisão e o deployment
correspondente. Rollback da edge segue o runbook Cloudflare; publicar artefatos
antigos na landing exige também autorização Railway. Não assumir que um
commit do gerador atualizou qualquer serviço remoto. Registre somente versão,
contagem e checksum, sem dados de consultas.

## Limites e pendências de validação

- **Implemented:** [test_blocklists.py](tests/test_blocklists.py) cobre parsing,
  IDN, allowlist com descendentes, rejeição de fonte vazia/HTML/sintaxe
  executável, determinismo, preservação da última saída após variação excessiva,
  corrupção do gzip e matriz de domínios públicos permitidos/bloqueados.
  Downloads são mockados; as fixtures em [fixtures](fixtures) não contêm
  tráfego de usuários. A suíte não prova disponibilidade atual do upstream.
- **Pending:** permitir `safe.example.com` não sobrepõe `example.com` que
  continue bloqueado: o Worker faz suffix matching sem allowlist em runtime.
  Revisar ancestrais ao incluir uma exceção e testar a resolução resultante.
- **Pending:** `validate_blocklist.py` compara contagem e metadata, mas não
  compara diretamente os bytes de texto público e Worker. `cmp` acima cobre
  essa lacuna na operação atual. `validate_artifacts` valida o formato da
  versão, mas não recalcula sua correspondência com o hash do texto.
- **Pending:** `maximumManifestBytes` e `maximumPayloadBytes` são declarados
  em `sources.json`, mas não são aplicados por `validate_artifacts`; não tratá-los
  como garantias de limite ao validar arquivos externos.
- **Pending:** o candidato é validado antes da troca, mas as substituições são
  atômicas por arquivo, não uma transação do conjunto. Falha de I/O/interrupção
  durante a troca pode exigir restauração e nova validação.
- **Pending:** não há teste dedicado da CLI `prepare_blocklist.py`, de toda a
  metadata cruzada ou de falhas reais HTTPS/redirecionamentos. A lista não tem
  mecanismo de atualização dinâmica no Worker: mudar o DNS publicado exige
  incluir o novo bundle em deploy autorizado.
