#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
git -C "$repo_root" config --local core.hooksPath .githooks
echo "Adless Git hooks enabled for $repo_root"
echo "To disable them: git -C \"$repo_root\" config --unset core.hooksPath"
