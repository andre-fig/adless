#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

has_path_matching() {
  local paths_file="$1"
  shift
  local path pattern

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    for pattern in "$@"; do
      # The right-hand side is intentionally unquoted: pattern matching is
      # the purpose of this helper.
      # shellcheck disable=SC2053
      if [[ "$path" == $pattern ]]; then
        return 0
      fi
    done
  done < "$paths_file"

  return 1
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Adless hook: '$command_name' is required for this change." >&2
    echo "Install it with: $install_hint" >&2
    return 1
  fi
}

run_actionlint() {
  require_command actionlint "brew install actionlint"
  actionlint "$REPO_ROOT"/.github/workflows/*.yml
}

run_shellcheck() {
  local paths_file="$1"
  local path

  require_command shellcheck "brew install shellcheck"
  while IFS= read -r path; do
    [ -f "$REPO_ROOT/$path" ] || continue
    case "$path" in
      *.sh|.githooks/pre-commit|.githooks/pre-push)
        shellcheck "$REPO_ROOT/$path"
        ;;
    esac
  done < "$paths_file"
}

run_python_syntax() {
  local paths_file="$1"
  local path

  require_command python3 "install Python 3"
  while IFS= read -r path; do
    case "$path" in
      *.py)
        python3 - "$REPO_ROOT/$path" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
        ;;
    esac
  done < "$paths_file"
}

run_blocklist_tests() {
  require_command python3 "install Python 3"
  python3 -m unittest discover -s "$REPO_ROOT/tools/blocklists/tests" -v
}

run_release_tests() {
  require_command python3 "install Python 3"
  python3 -B -m unittest discover -s "$REPO_ROOT/tools/appstore/tests" -v
  python3 -B -m unittest discover -s "$REPO_ROOT/tools/dns-worker/tests" -v
  run_actionlint
}

run_worker_checks() {
  require_command npm "install Node.js 20 or newer"
  npm --prefix "$REPO_ROOT" run test:dns-worker
  npm --prefix "$REPO_ROOT" run build:dns-worker
}

run_worker_deploy_dry_runs() {
  require_command npx "install Node.js 20 or newer"

  local dry_run_directory
  dry_run_directory="$(mktemp -d "${TMPDIR:-/tmp}/adless-wrangler-dry-run.XXXXXX")"
  trap 'find "$dry_run_directory" -depth -delete' RETURN

  (
    cd "$REPO_ROOT"
    npx --yes wrangler@4 deploy --env="" \
      --config apps/dns-worker/wrangler.toml \
      --dry-run \
      --outdir "$dry_run_directory/production"
    npx --yes wrangler@4 deploy --env development \
      --config apps/dns-worker/wrangler.toml \
      --dry-run \
      --outdir "$dry_run_directory/development"
  )
}

run_landing_lint() {
  require_command npm "install Node.js 20 or newer"
  npm --prefix "$REPO_ROOT" run lint
}

run_landing_typecheck() {
  require_command npm "install Node.js 20 or newer"
  npm --prefix "$REPO_ROOT" run typecheck
}

run_landing_checks() {
  run_landing_typecheck
  npm --prefix "$REPO_ROOT" run build:landing
}

run_ios_tests() {
  require_command xcodebuild "install Xcode"
  require_command xcrun "install Xcode command-line tools"

  local simulator_id derived_data
  simulator_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  if [ -z "$simulator_id" ]; then
    echo "Adless hook: no available iPhone simulator was found." >&2
    return 1
  fi

  derived_data="$(mktemp -d "${TMPDIR:-/tmp}/adless-pre-push.XXXXXX")"
  trap 'rm -rf "$derived_data"' RETURN

  xcodebuild \
    -project "$REPO_ROOT/apps/ios/Adless.xcodeproj" \
    -scheme AdlessTests \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    test
}
