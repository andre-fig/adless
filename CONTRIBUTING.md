# Contribuindo com o Adless

Comece pelo [AGENTS.md da raiz](AGENTS.md), preserve o working tree existente e
mantenha a contribuição dentro da arquitetura de filtragem DNS. Não introduza
contas, proxy de tráfego ou serviços adicionais sem decisão explícita.

```sh
git status --short --branch
```

A hierarquia de instruções evita duplicação: leia também o `AGENTS.md` do
[app iOS](apps/ios/AGENTS.md), do [Worker](apps/dns-worker/AGENTS.md), da
[landing](apps/landing-page/AGENTS.md) ou do [pipeline](tools/blocklists/AGENTS.md)
conforme os arquivos afetados. Setup e efeitos dos hooks/workflows estão em
[DEVELOPMENT.md](docs/DEVELOPMENT.md).

Antes de apresentar uma mudança:

1. Confirme o comportamento no código e cite arquivos/símbolos relevantes;
   atualize o documento canônico da área quando o contrato mudar.
2. Execute a sequência relevante de [TESTING.md](docs/TESTING.md), incluindo
   áreas consumidoras quando mudar autorização, DNS ou blocklists. Testes de
   simulador não aprovam o DNS real no iPhone.
3. Rode `git diff --check`, revise o diff e confira `git status --short --branch`.
4. Descreva problema, comportamento final, arquivos alterados, validações e
   pendências. Separe **Implemented**, **Deployed**, **Verified** e **Pending**.

Não regenerar blocklists em mudança apenas documental. Não executar commit,
push, deploy ou upload para testar os hooks. Regras de autorização e proteção
de secrets são as da raiz; publicação Apple e Cloudflare possuem seus próprios
runbooks em [ios-release.md](docs/ios-release.md) e [dns-cloud.md](docs/dns-cloud.md).
