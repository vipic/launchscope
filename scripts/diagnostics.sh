#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
workflow="${1:-}"
mode="${2:-}"
if [[ "$workflow" != "release" && "$workflow" != "publish" ]]; then
  echo "用法：scripts/diagnostics.sh <release|publish> [--full]" >&2
  exit 2
fi

log="$project_dir/.local/logs/$workflow/latest.log"
[[ -f "$log" ]] || { echo "尚无 $workflow 日志。" >&2; exit 1; }
if [[ "$mode" == "--full" ]]; then
  exec sed -n '1,$p' "$log"
fi
grep -E 'event=(workflow|stage|command)\.(start|finish)|event=artifact' "$log"
