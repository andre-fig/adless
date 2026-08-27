#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 PATH_TO_IPA" >&2
  exit 2
fi

ipa="$1"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
unzip -q "$ipa" -d "$temporary_directory"
app_count="$(find "$temporary_directory/Payload" -maxdepth 1 -type d -name '*.app' -print | wc -l | tr -d '[:space:]')"
test "$app_count" -eq 1
app="$(find "$temporary_directory/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
test -z "$(find "$app" -type d -name '*.appex' -print -quit)"
test -z "$(unzip -Z1 "$ipa" | grep -E '(^|/)(PacketTunnel|DNSProxy|.*\.appex)(/|$)' || true)"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = "com.orbeworks.adless"
codesign -d --entitlements :- "$app" 2>/dev/null | grep -q 'dns-settings'
if codesign -d --entitlements :- "$app" 2>/dev/null | grep -Eq 'dns-proxy|packet-tunnel-provider|NEDNSProxy|NEPacketTunnel|NETunnelProvider|com\.orbeworks\.adless\.tunnel|application-groups'; then
  echo "Legacy networking entitlement found in IPA" >&2
  exit 1
fi
echo "Verified IPA with one Adless.app, dns-settings, and no embedded extensions."
