#!/usr/bin/env bash

set -euo pipefail

maximum_age_minutes="${ADLESS_TEMP_MAX_AGE_MINUTES:-1440}"

case "$maximum_age_minutes" in
  ''|*[!0-9]*)
    echo "error: ADLESS_TEMP_MAX_AGE_MINUTES must be a non-negative integer" >&2
    exit 2
    ;;
esac

current_uid="$(id -u)"
session_temp_root="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
session_temp_root="${session_temp_root:-${TMPDIR:-}}"
session_temp_root="${session_temp_root%/}"

temp_roots=(/private/tmp)
if [ -n "$session_temp_root" ] && [ "$session_temp_root" != /private/tmp ]; then
  temp_roots+=("$session_temp_root")
fi

for temp_root in "${temp_roots[@]}"; do
  test -d "$temp_root" || continue

  find "$temp_root" -mindepth 1 -maxdepth 1 -type d -name 'adless*' \
    -mmin "+$maximum_age_minutes" -print0 |
  while IFS= read -r -d '' candidate; do
    test "$(dirname "$candidate")" = "$temp_root" || continue
    case "$(basename "$candidate")" in
      adless*) ;;
      *) continue ;;
    esac
    test "$(stat -f '%u' "$candidate")" = "$current_uid" || continue

    # shellcheck disable=SC2009
    if ps ax -o command= | grep -F -- "$candidate" | grep -v grep >/dev/null 2>&1; then
      echo "Skipping active temporary directory: $candidate"
      continue
    fi

    find "$candidate" -depth -delete
    echo "Removed stale temporary directory: $candidate"
  done
done

echo "Adless temporary cleanup completed."
