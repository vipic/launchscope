#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

scripts=(
  deploy.sh
  release.sh
  scripts/check_shell.sh
  scripts/check_coverage.sh
  scripts/publish.sh
  scripts/verify_release.sh
  scripts/ui_smoke.sh
)

for script in "${scripts[@]}"; do
  bash -n "$script"
done

echo "Shell syntax checks passed (${#scripts[@]} files)."
