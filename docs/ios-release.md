# Automated iOS release

The repository uses a two-branch flow:

```text
develop  ->  TestFlight  ->  pull request  ->  main  ->  test, archive, upload, submit
```

## Automatic TestFlight builds

Every push to `develop` that changes production iOS code, resources, project
configuration, the App Store Connect helper, or the export options starts
`.github/workflows/testflight-ios.yml`. A manual run is also available from
**Actions → Upload Adless to TestFlight → Run workflow**.

The workflow creates a Release archive, exports an App Store distribution IPA,
validates it with Apple's tooling, uploads it to App Store Connect, and waits
for the build to reach `VALID`. It does not attach the build to an App Store
version or submit anything for review. The archive uses the production
StoreKit code path; the local `Adless.storekit` configuration is not supplied
to the archive or export commands.

The workflow shares the same App Store Connect secrets and automatic signing
setup as the production release workflow. A newer `develop` run cancels an
older one, so only the newest development build is kept in flight. A build
number is selected above the highest build already known by App Store Connect.

Every push to `main` that changes production iOS code/resources, the App Store
Connect release helper, or the export options starts
`.github/workflows/release-ios.yml`. A blocklist-only commit does not start an
iOS binary release. The workflow keeps only one release in flight: a newer run
cancels the previous run in the same concurrency group. If Apple has already
accepted an upload before cancellation, the next preflight still checks the
App Store state and avoids submitting a duplicate version.

## GitHub secrets

The private repository must contain these three Apple Actions secrets:

- `ASC_KEY_ID`: App Store Connect API key ID;
- `ASC_ISSUER_ID`: App Store Connect issuer ID;
- `ASC_PRIVATE_KEY`: the complete contents of the `.p8` key;

`SENTRY_AUTH_TOKEN` is an optional fourth secret: when present, it must be a
Sentry token allowed to upload debug symbols for the `portside-xz/adless`
project.

The key is written only to the runner's temporary directory with mode `600`.
It is never committed, logged, or included in the IPA. The workflow uses the
same key for the App Store Connect API and for Xcode automatic provisioning.
When `SENTRY_AUTH_TOKEN` is present, the release runner installs `sentry-cli`
and the Xcode archive phase uploads dSYMs to Sentry. If it is absent, the app
still builds, but Sentry issues from that build will not have uploaded symbols.

The Apple Developer team must allow automatic signing for the app and the DNS
Proxy extension. If Apple requires a distribution certificate or profile to be
managed manually for this account, configure that in the Apple Developer
portal and add the corresponding CI signing secrets before enabling a release;
do not commit certificates or provisioning profiles.

## App Store Connect preparation

The version configured in `apps/ios/Adless.xcodeproj` must already exist in App
Store Connect with its metadata, products, agreements, screenshots, and review
information completed. The workflow intentionally does not create or edit
metadata or prices.

The preflight step behaves safely when the version is already `READY_FOR_REVIEW`,
`WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`,
`PENDING_APPLE_RELEASE`, or `READY_FOR_SALE`: it reports that there is nothing
to submit and exits successfully. This prevents a normal commit from creating
a second review submission for the same version. For a new release, first
create the new version in App Store Connect and change `MARKETING_VERSION` in
the project; then merge the prepared changes into `main`.

For a version in `PREPARE_FOR_SUBMISSION` or a rejected version, the workflow:

1. checks the current App Store state;
2. chooses a build number higher than both the repository and App Store;
3. runs the iOS tests;
4. archives and exports the signed IPA;
5. validates and uploads it with Apple's tooling;
6. waits for processing to become `VALID`;
7. links the build to the version and submits a new review submission.

If a later API or signing step fails, the workflow stops and leaves the last
valid App Store build untouched. The build may have been uploaded before a
failure in the final submission step; in that case finish the review submission
from App Store Connect instead of uploading the same build again.

## Manual release

Use **Actions → Release Adless iOS to App Store Connect → Run workflow**. The
same version-state and signing checks apply. It is not a bypass for a version
that Apple is already reviewing.

## Local checks

```sh
actionlint .github/workflows/release-ios.yml
python3 -m py_compile tools/appstore/appstore_connect.py
xcodebuild -project apps/ios/Adless.xcodeproj \
  -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

The helper uses only Python's standard library and the `openssl` executable
already available on macOS runners. No Apple private key is required for local
tests of the iOS project.
