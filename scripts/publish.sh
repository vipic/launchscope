#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "用法：mise run publish -- <x.y.z>" >&2
  exit 1
fi

exec "$(dirname "$0")/../release.sh" "$version" --publish
