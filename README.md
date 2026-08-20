# Adless

Monorepo do Adless, com o aplicativo iOS e sua landing page no mesmo repositório.

## Estrutura

```text
apps/
├── ios/            # Aplicativo iOS em SwiftUI + NetworkExtension
└── landing-page/   # Landing page em React + Vite
```

## Landing page

Requer Node.js 20+ e npm.

```sh
npm install
npm run dev:landing
```

Outros comandos úteis:

```sh
npm run build:landing
npm run lint
npm run preview:landing
```

## Aplicativo iOS

Abra `apps/ios/Adless.xcodeproj` no Xcode, configure o Team e o App Group
`group.com.usefulish.adless` para os targets `Adless` e `AdlessDNSProxy`, e
execute o scheme `Adless`. O target `AdlessDNSProxy` precisa da capability
Network Extension (DNS Proxy) no App ID correspondente.

A cobrança é feita exclusivamente pela App Store com StoreKit 2, sem backend,
login ou banco próprio. O app oferece assinaturas mensal e anual com trial de
7 dias configurado no App Store Connect.

## Blocklist

A blocklist é gerada sem backend pelo workflow diário
`.github/workflows/update-blocklist.yml`. A fonte habilitada no MVP é somente a
OISD Small; atribuição e licença estão em
[THIRD_PARTY_BLOCKLISTS.md](THIRD_PARTY_BLOCKLISTS.md).

Os artefatos públicos ficam em `apps/landing-page/public/blocklists/` e são
servidos pela mesma build estática da landing. A URL esperada do manifesto é
`https://andre-fig.github.io/adless/blocklists/manifest.json`. O app consulta o manifesto no
máximo uma vez a cada 24 horas, valida uma nova versão em arquivo temporário e
mantém a lista local anterior ou a lista embutida quando está offline ou quando
uma atualização falha.

Para gerar manualmente e atualizar também o fallback embutido:

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
```

Detalhes operacionais estão em
[`tools/blocklists/README.md`](tools/blocklists/README.md).

O workflow `deploy-pages.yml` publica a build da landing no GitHub Pages. É
necessário selecionar `GitHub Actions` como fonte de publicação em Settings →
Pages no repositório.

Consulte os READMEs de [apps/ios](apps/ios/README.md) e [apps/landing-page](apps/landing-page/README.md) para detalhes específicos de cada projeto.
