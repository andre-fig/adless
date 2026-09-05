# Pendências do Adless

Este é um índice de acompanhamento, não autorização para implementar ou publicar.
A [auditoria](docs/REPOSITORY_AUDIT.md) registra evidências e limitações; cada
assunto abaixo tem uma fonte canônica para evitar checklists duplicados.

| Estado | Item | Onde acompanhar |
| --- | --- | --- |
| Implemented | DoH no Worker e fallback sequencial Cloudflare/Quad9 | [Arquitetura](docs/ARCHITECTURE.md) |
| Implemented | Catálogos PT/EN/ES; cobertura de textos novos ainda incompleta | [iOS](apps/ios/README.md) e [landing](apps/landing-page/README.md) |
| Pending | Confirmar falhas, troca de rede e proteção real em iPhone | [Testes](docs/TESTING.md) |
| Pending | Alinhar landing, Privacy Policy, Terms e Support à implementação | [Landing](apps/landing-page/README.md) |
| Pending | Conferir preços por moeda/território, oferta introdutória e elegibilidade | [Apple e lançamento](docs/ios-release.md) |
| Pending | Validação remota de Worker/bindings/JWS/notifications e publicação Apple | [Cloudflare](docs/dns-cloud.md) e [Apple](docs/ios-release.md) |

O antigo item “testar falhas e trocas de rede” estava concluído sem distinguir
mocks de testes físicos. O código comprova cobertura automatizada parcial, não
aprovação em dispositivo; por isso a etapa física permanece Pending.

Ideias de produto preservadas, ainda **Pending** de decisão de escopo:

- Content Blocker para Safari: não implementado; exigiria rever a arquitetura
  sem extensão antes de qualquer alteração.
- Trocar o logo.
- Adicionar efeito de fundo quando a proteção estiver ativa.

Não transformar ideias ou lacunas registradas em mudanças técnicas durante uma
tarefa documental. Quando resolvidas, atualizar a fonte canônica e anexar evidência
adequada antes de alterar seu estado.
