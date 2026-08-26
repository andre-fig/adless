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
extension="$app/PlugIns/PacketTunnel.appex"

test -d "$app"
test -d "$extension"

plugin_count="$(find "$app/PlugIns" -maxdepth 1 -type d -name '*.appex' -print | wc -l | tr -d '[:space:]')"
test "$plugin_count" -eq 1

if [ "$layout_only" = true ]; then
  echo "Verified Adless.app with only PacketTunnel.appex."
  exit 0
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

check_signed_bundle() {
  bundle="$1"
  expected_identifier="$2"
  expected_group="$3"
  name="$(basename "$bundle" | tr '.' '_')"
  entitlements="$temporary_directory/$name.entitlements.plist"

  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")"
  test "$identifier" = "$expected_identifier"
  codesign -d --entitlements :- "$bundle" > "$entitlements" 2>/dev/null
  test -s "$entitlements"
  network_extension="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.networking.networkextension:0' "$entitlements")"
  app_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$entitlements")"
  test "$network_extension" = "packet-tunnel-provider"
  test "$app_group" = "$expected_group"
}

check_signed_bundle "$app" "com.orbeworks.adless" "group.com.orbeworks.adless"
check_signed_bundle "$extension" "com.orbeworks.adless.tunnel" "group.com.orbeworks.adless"
echo "Verified Adless.app with only PacketTunnel.appex and signed Packet Tunnel/App Group entitlements."
