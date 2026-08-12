#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

scripts=(
  deploy.sh
  release.sh
  scripts/check_shell.sh
  scripts/check_coverage.sh
  scripts/check_design_tokens.sh
  scripts/diagnostics.sh
  scripts/lib/command_log.sh
  scripts/next_version.sh
  scripts/publish.sh
  scripts/verify_release.sh
  scripts/ui_smoke.sh
  scripts/release_acceptance.sh
  scripts/release_smoke.sh
)

for script in "${scripts[@]}"; do
  bash -n "$script"
done

echo "Shell syntax checks passed (${#scripts[@]} files)."
