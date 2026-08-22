#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

if [ "${CI:-}" = "true" ]; then
  echo "Adless Git hooks skipped in CI"
  exit 0
fi

git -C "$repo_root" config --local core.hooksPath .githooks
echo "Adless Git hooks enabled for $repo_root"
echo "To disable them: git -C \"$repo_root\" config --unset core.hooksPath"
