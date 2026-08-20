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

Abra `apps/ios/Adless.xcodeproj` no Xcode, configure o Team e o App Group `group.com.adless.shared` para os targets `Adless` e `AdlessDNSProxy`, e execute o scheme `Adless`.

Consulte os READMEs de [apps/ios](apps/ios/README.md) e [apps/landing-page](apps/landing-page/README.md) para detalhes específicos de cada projeto.
