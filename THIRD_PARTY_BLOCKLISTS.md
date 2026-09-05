# Fontes de blocklist de terceiros

Fonte canônica de atribuição. O funcionamento do pipeline pertence a
[tools/blocklists/README.md](tools/blocklists/README.md).

**Implemented:** [sources.json](tools/blocklists/sources.json) habilita uma
única fonte, **OISD Small**, em [small.oisd.nl](https://small.oisd.nl/), formato
`adblock`. O projeto de origem é [OISD](https://oisd.nl/); a relação das listas
incluídas é publicada em [included lists / small](https://oisd.nl/includedlists/small).

**Verified:** o arquivo [LICENSE do repositório oficial OISD](https://github.com/sjhgvr/oisd/blob/main/LICENSE)
publica GNU General Public License versão 3. Isso identifica o texto da licença
consultado; não estabelece, por si só, a conformidade comercial do Adless.

**Pending:** a documentação anterior atribuía a manutenção a Stephan van Ruth.
Essa atribuição histórica é preservada aqui, mas não foi reconfirmada nas páginas
consultadas. Confirmar o responsável e os termos aplicáveis à fonte distribuída
antes de atualizar a atribuição pública.

O gerador extrai domínios de regras `||domain^` e também aceita domínios simples,
produzindo texto ASCII/Punycode ordenado. Não transporta sintaxe executável nem
inclui a lista no app iOS: distribui artefatos estáticos pela landing e uma cópia
embutida no Worker.

**Pending:** o responsável pelo produto deve concluir a revisão da licença,
atribuições e obrigações de redistribuição para a publicação comercial na App
Store. Não existe comprovação dessa revisão no código. Antes de habilitar nova
fonte, registrar aqui URL original, responsável, licença e decisão de revisão;
preservar a proveniência e manter a saída reproduzível.
