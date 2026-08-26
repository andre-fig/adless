#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 PATH_TO_DSYMS" >&2
  exit 2
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "error: SENTRY_AUTH_TOKEN is not set; cannot upload dSYMs." >&2
  exit 1
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "error: sentry-cli is not installed; cannot upload dSYMs." >&2
  exit 1
fi

dsyms_path="$1"
if [ ! -d "$dsyms_path" ]; then
  echo "error: dSYM directory does not exist: $dsyms_path" >&2
  exit 1
fi

export SENTRY_ORG="${SENTRY_ORG:-portside-xz}"
export SENTRY_PROJECT="${SENTRY_PROJECT:-adless}"

sentry-cli debug-files upload --include-sources "$dsyms_path"
