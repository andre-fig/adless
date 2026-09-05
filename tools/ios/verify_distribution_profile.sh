#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 PATH_TO_ADLESS_APP" >&2
  exit 2
fi

app="$1"
profile="$app/embedded.mobileprovision"
plist_buddy=/usr/libexec/PlistBuddy
expected_bundle_id=com.orbeworks.adless

fail() {
  echo "$1" >&2
  exit 1
}

plist_value() {
  "$plist_buddy" -c "Print $2" "$1" 2>/dev/null
}

plist_has_key() {
  "$plist_buddy" -c "Print $2" "$1" >/dev/null 2>&1
}

require_value() {
  actual="$(plist_value "$1" "$2")" || fail "$4"
  test "$actual" = "$3" || fail "$4"
}

require_allowed_entitlement_keys() {
  candidate_plist="$1"
  description="$2"
  /usr/bin/python3 - "$candidate_plist" "$description" <<'PY'
import plistlib
import sys

allowed = {
    "application-identifier",
    "beta-reports-active",
    "com.apple.developer.networking.networkextension",
    "com.apple.developer.team-identifier",
    "get-task-allow",
    "keychain-access-groups",
}
with open(sys.argv[1], "rb") as handle:
    entitlements = plistlib.load(handle)
unexpected = sorted(set(entitlements) - allowed)
if unexpected:
    print(
        f"Unexpected entitlement in {sys.argv[2]}: {', '.join(unexpected)}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

require_absent_capabilities() {
  candidate_plist="$1"
  description="$2"
  entitlements_path="$3"
  for entitlement in \
    'com.apple.security.application-groups' \
    'com.apple.developer.networking.vpn.api' \
    'com.apple.developer.networking.HotspotConfiguration' \
    'com.apple.developer.networking.wifi-info' \
    'com.apple.developer.networking.multipath' \
    'com.apple.developer.associated-domains' \
    'aps-environment' \
    'com.apple.developer.icloud-container-identifiers' \
    'com.apple.developer.ubiquity-container-identifiers' \
    'com.apple.developer.icloud-services' \
    'com.apple.developer.pass-type-identifiers' \
    'com.apple.developer.in-app-payments' \
    'com.apple.developer.applesignin'
  do
    key="$entitlements_path:$entitlement"
    if plist_has_key "$candidate_plist" "$key"; then
      fail "Unexpected capability found in $description"
    fi
  done
}

require_dns_settings_only() {
  candidate_plist="$1"
  description="$2"
  entitlements_path="$3"
  network_extension_key="$entitlements_path:com.apple.developer.networking.networkextension"
  require_value \
    "$candidate_plist" \
    "$network_extension_key:0" \
    'dns-settings' \
    "dns-settings is missing from $description"
  if plist_has_key "$candidate_plist" "$network_extension_key:1"; then
    fail "Unexpected additional Network Extension capability found in $description"
  fi
}

require_profile_authorizes_dns_settings() {
  # A provisioning profile is an allowlist, not the app's effective capabilities.
  # Apple issues Network Extensions profiles with the provider family included:
  # https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
  /usr/bin/python3 - "$1" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    profile = plistlib.load(handle)
permitted = profile.get("Entitlements", {}).get(
    "com.apple.developer.networking.networkextension", []
)
if not isinstance(permitted, list) or "dns-settings" not in permitted:
    print("Provisioning profile does not authorize dns-settings", file=sys.stderr)
    raise SystemExit(1)
PY
}

test -d "$app" || fail "Adless.app is missing"
test -f "$profile" || fail "Distribution provisioning profile is missing"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
signed_entitlements="$temporary_directory/signed-entitlements.plist"
profile_plist="$temporary_directory/profile.plist"
profile_entitlements="$temporary_directory/profile-entitlements.plist"

codesign -d --entitlements :- "$app" > "$signed_entitlements" 2>/dev/null \
  || fail "Unable to read signed app entitlements"
test -s "$signed_entitlements" || fail "Signed app entitlements are empty"
security cms -D -i "$profile" > "$profile_plist" 2>/dev/null \
  || fail "Unable to decode the embedded provisioning profile"
plutil -lint "$signed_entitlements" >/dev/null \
  || fail "Signed app entitlements are not a valid plist"
plutil -lint "$profile_plist" >/dev/null \
  || fail "Embedded provisioning profile is not a valid plist"
plutil -extract Entitlements xml1 -o "$profile_entitlements" "$profile_plist" \
  || fail "Unable to extract provisioning profile entitlements"

expiration_date="$(plutil -extract ExpirationDate raw -o - "$profile_plist")" \
  || fail "Provisioning profile ExpirationDate is missing"
expiration_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration_date" '+%s' 2>/dev/null)" \
  || fail "Provisioning profile ExpirationDate is invalid"
test "$expiration_epoch" -gt "$(date -u '+%s')" \
  || fail "Provisioning profile is expired"

profile_team="$(plist_value "$profile_plist" ':TeamIdentifier:0')" \
  || fail "Provisioning profile TeamIdentifier is missing"
printf '%s\n' "$profile_team" | grep -Eq '^[A-Z0-9]{10}$' \
  || fail "Provisioning profile TeamIdentifier is invalid"
expected_application_identifier="$profile_team.$expected_bundle_id"

require_value "$profile_plist" ':Entitlements:application-identifier' \
  "$expected_application_identifier" "Provisioning profile application identifier does not match Adless"
require_value "$profile_plist" ':Entitlements:com.apple.developer.team-identifier' \
  "$profile_team" "Provisioning profile team identifier is inconsistent"
require_value "$profile_plist" ':Entitlements:get-task-allow' \
  'false' "Provisioning profile must set get-task-allow=false"

require_value "$signed_entitlements" ':application-identifier' \
  "$expected_application_identifier" "Signed app application identifier does not match its profile"
require_value "$signed_entitlements" ':com.apple.developer.team-identifier' \
  "$profile_team" "Signed app team identifier does not match its profile"
require_value "$signed_entitlements" ':get-task-allow' \
  'false' "Signed app must set get-task-allow=false"

if plist_has_key "$profile_plist" ':ProvisionedDevices'; then
  fail "A development or ad hoc provisioning profile cannot be used for distribution"
fi
if plist_has_key "$profile_plist" ':ProvisionsAllDevices'; then
  fail "An enterprise provisioning profile cannot be used for App Store Connect"
fi

require_profile_authorizes_dns_settings "$profile_plist"
require_dns_settings_only "$signed_entitlements" 'signed app' ''
require_allowed_entitlement_keys "$profile_entitlements" 'provisioning profile'
require_allowed_entitlement_keys "$signed_entitlements" 'signed app'
require_absent_capabilities "$profile_plist" 'provisioning profile' ':Entitlements'
require_absent_capabilities "$signed_entitlements" 'signed app' ''

echo "Verified distribution profile, signing linkage, and minimal signed app capabilities."
