# Pipeline da blocklist

O pipeline usa somente a biblioteca padrão do Python. `sources.json` declara a
fonte HTTPS habilitada (OISD Small) e `allowlist.txt` contém as exceções. A
saída canônica alimenta a landing page e o bundle do Worker.

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

O gerador normaliza lowercase/IDN, remove duplicatas, aplica allowlist, valida
contagem, cria gzip determinístico e mantém `generatedAt` quando o conteúdo não
muda. Ele rejeita fontes vazias, HTML/JSON de erro e variação acima do limite.
Use `--allow-large-change` somente depois de revisão manual.

Artefatos públicos:

- `apps/landing-page/public/blocklists/manifest.json`;
- `blocklist.txt.gz`, `blocklist.txt` e `blocklist.sha256` no mesmo diretório;
- `apps/dns-worker/data/blocklist.txt` e `blocklist.meta.json` para o Worker.

Não edite esses arquivos manualmente. O workflow gera em candidato, valida
antes da troca e faz commit somente dos caminhos permitidos. A versão anterior
fica disponível no histórico Git e nos deployments do Worker para rollback.
Registre apenas versão, contagem e checksum; nunca consultas de usuários.
