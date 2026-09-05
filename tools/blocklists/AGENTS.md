# Instruções do pipeline de blocklist

Este escopo cobre `tools/blocklists/` e herda o [AGENTS.md da raiz](../../AGENTS.md).
O [README](README.md) é a fonte canônica de formatos, política, comandos,
saídas, cobertura e limitações. A preparação da edge fica em
[`tools/dns-worker/prepare_blocklist.py`](../dns-worker/prepare_blocklist.py).

- Alterar entradas declarativas ou gerador; nunca editar artefatos à mão.
  Documentar proveniência/licença em [THIRD_PARTY_BLOCKLISTS.md](../../THIRD_PARTY_BLOCKLISTS.md)
  antes de habilitar outra fonte.
- Tratar downloads como dados não confiáveis: HTTPS, limites, canonicalização,
  rejeição de lista vazia/sintaxe executável e revisão de variação excessiva.
  `--allow-large-change` exige revisão explícita; não usar para contornar falha.
- Preservar determinismo e o último conjunto válido. `--sync-worker` não
  atualiza metadata sozinho; validar também a saída de `prepare_blocklist.py`.
- Ao permitir um domínio, conferir ancestrais ainda bloqueados: a allowlist
  do gerador não sobrepõe suffix matching do Worker em runtime.
- Rodar a suíte Python e o validador do README; mudanças de lista/semântica
  exigem também testes Worker e revisão de domínios essenciais à conectividade.
  Usar fixtures sintéticas, sem consultas reais de usuários.
- Não regenerar em tarefas só documentais. Geração escreve arquivos; dispatch
  do workflow de atualização faz commit/push e requer autorização para isso.
  Publicação da landing e da edge são operações separadas.
