#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 [--layout-only] PATH_TO_XCARCHIVE" >&2
  exit 2
fi

layout_only=false
if [ "$#" -eq 2 ]; then
  test "$1" = "--layout-only"
  layout_only=true
  archive="$2"
else
  archive="$1"
fi

app="$archive/Products/Applications/Adless.app"
test -d "$app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = "com.orbeworks.adless"

if [ -d "$app/PlugIns" ]; then
  plugin_count="$(find "$app/PlugIns" -type d -name '*.appex' -print | wc -l | tr -d '[:space:]')"
  test "$plugin_count" -eq 0
fi
test -z "$(find "$archive" -type d -name '*.appex' -print -quit)"

if [ "$layout_only" = true ]; then
  echo "Verified Adless.app archive with no embedded extensions."
  exit 0
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
entitlements="$temporary_directory/Adless.entitlements.plist"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
test -s "$entitlements"
grep -q 'dns-settings' "$entitlements"
if grep -Eq 'dns-proxy|packet-tunnel-provider|NEDNSProxy|NEPacketTunnel|NETunnelProvider|com\.orbeworks\.adless\.tunnel|application-groups' "$entitlements"; then
  echo "Legacy networking entitlement found in signed archive" >&2
  exit 1
fi
echo "Verified signed Adless.app archive with dns-settings and no embedded extensions."
