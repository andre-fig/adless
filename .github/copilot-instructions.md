# Adless repository instructions

## Repository shape

Adless is a monorepo with two products and a tooling area:

- `apps/ios/`: SwiftUI app, local Packet Tunnel Network Extension, and XCTest target.
- `apps/landing-page/`: static React + Vite + TypeScript landing page.
- `tools/blocklists/`: deterministic Python blocklist generator, validator,
  fixtures, and tests.
- `apps/landing-page/public/blocklists/`: generated files published through
  GitHub Pages.

Read the repository instruction file (`AGENT.md` or `AGENTS.md`) and the README
for the area being changed before editing.
Preserve unrelated working-tree changes and keep changes limited to the task.

## Architectural boundaries

- Do not introduce a backend, database, login, custom authentication, Railway,
  admin panel, or subscription server.
- Purchases are handled only by StoreKit 2 and App Store Connect. The app has
  no user account and no payment or personal identity database.
- The iOS product is a local DNS sinkhole. It uses a Packet Tunnel Network
  Extension only for DNS and does not route traffic through an external VPN server.
- Prefer existing dependencies and the standard library. Do not add a heavy
  dependency for functionality already provided by the project or Apple SDKs.
- Never add HTTP URLs, secrets, private keys, certificates, provisioning
  profiles, or generated build products to the repository.

## iOS rules

Targets in `apps/ios/Adless.xcodeproj` are:

- `Adless`: the SwiftUI application;
- `PacketTunnel`: the local Packet Tunnel extension;
- `AdlessTests`: XCTest.

The existing App Group is `group.com.orbeworks.adless`. Verify both targets
before changing entitlements, capabilities, or shared-file paths. The active
blocklist is shared through:

```text
Library/Application Support/Blocklists/blocklist.txt
```

The app must work offline using
`apps/ios/Adless/Resources/SeedBlocklist.txt`. Downloaded lists must be
validated in a temporary file and installed by atomic replacement. A failed
update must preserve the last valid list and must never disable protection.
Do not use `Documents` or modify the read-only app bundle at runtime.

The app uses StoreKit 2 with these product identifiers:

```text
com.orbeworks.adless.pro.monthly
com.orbeworks.adless.pro.yearly
```

Entitlement state must come from verified Apple transactions and their expiry
or grace-period state. Use `Transaction.currentEntitlements`,
`Transaction.updates`, and `AppStore.sync()` as appropriate. Never implement a
permanent hard-coded subscription flag. The seven-day trial is configured in
App Store Connect or the local `.storekit` configuration, not by inventing a
separate server-side trial system.

The simulator is suitable for builds, UI work, and unit tests. Full DNS
interception must be tested on a physical iPhone.

## Blocklist rules

The enabled MVP source is declared in `tools/blocklists/sources.json` and is
the official OISD Small source. Do not hard-code domains in Swift or in the
DNS extension. Generated artifacts must be produced by the Python pipeline:

- `apps/landing-page/public/blocklists/manifest.json`;
- `apps/landing-page/public/blocklists/blocklist.txt`;
- `apps/landing-page/public/blocklists/blocklist.txt.gz`;
- `apps/landing-page/public/blocklists/blocklist.sha256`;
- `apps/ios/Adless/Resources/SeedBlocklist.txt` when the seed is synchronized.

The published SHA-256 is for `blocklist.txt.gz`. The canonical text output is
deterministic; `generatedAt` must not create a commit when the content is
unchanged. Generated files must not be edited manually.

The generator must keep HTTPS-only downloads, bounded size and timeouts,
syntax validation, duplicate removal, allowlist handling, minimum and maximum
domain limits, abnormal-change protection, deterministic ordering, and atomic
artifact replacement. Never execute content downloaded from a blocklist.
Update `THIRD_PARTY_BLOCKLISTS.md` when sources or licensing information
change.

Run blocklist tests with fixtures; unit tests must not depend on live internet
downloads.

## Landing page rules

The landing page uses React, Vite, TypeScript, Tailwind CSS, and shadcn/ui.
Its public directory is `apps/landing-page/public/`. Blocklist files must stay
outside the JavaScript bundle and remain directly addressable under
`/blocklists/`.

Use strict TypeScript and the existing ESLint flat configuration. Avoid
`any`, floating promises, unused variables, and untyped public APIs. Keep
React component and hook conventions consistent with the existing code.

From the repository root, use:

```sh
npm ci
npm run lint
npm run typecheck
npm run build:landing
npm run dev:landing
```

## GitHub Actions rules

The development flow is:

```text
develop -> pull request -> main
```

Current workflow responsibilities are:

- `testflight-ios.yml`: on relevant `develop` changes, creates a signed Release
  archive, validates and uploads it to TestFlight, then waits for Apple
  processing. It does not submit an App Store version for review.
- `ios-tests.yml`: iOS tests on PRs and manual dispatch. It does not run for
  every push to `develop`.
- `release-ios.yml`: on relevant `main` changes, performs App Store Connect
  preflight, iOS tests, archive, export, validation, upload, processing wait,
  and review submission.
- `update-blocklist.yml`: weekly scheduled blocklist update and manual
  dispatch. It commits only explicit generated paths when content changes.
- `deploy-pages.yml`: deploys the landing and public blocklist artifacts to
  GitHub Pages after relevant `main` changes or manual dispatch.

When changing workflows:

- keep `concurrency` with `cancel-in-progress: true`;
- keep explicit timeouts and least-privilege permissions;
- avoid duplicate triggers and duplicate test/build jobs;
- never use `git add .` or `git add -A` in automation;
- add only the expected generated paths;
- run `actionlint` when available;
- do not add secrets to logs or workflow outputs;
- check the resulting GitHub run after publishing workflow changes.

## Local validation and delivery

`npm install` and `npm ci` activate the versioned hooks through the root
`prepare` script. The pre-commit hook should remain quick. The pre-push hook
runs targeted checks based on changed paths, including iOS XCTest for iOS
changes.

Before finishing a change, run the smallest relevant checks and report exactly
what ran and whether it passed. For broad changes, use:

```sh
git diff --check
python3 -m unittest discover -s tools/blocklists/tests -v
npm run lint
npm run typecheck
npm run build:landing
```

For iOS changes, also run the appropriate `xcodebuild` build or XCTest target.
For workflow changes, run `actionlint`. Check `git status --short --branch`
before delivery and do not claim a build, test, deployment, or App Store
submission succeeded unless it was actually observed.
