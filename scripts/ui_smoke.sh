#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
identity="${CODESIGN_IDENTITY:-Nekutai}"
runner="$project_dir/.build/debug/LaunchScopeUISmoke"

cd "$project_dir"
mise run deploy
swift build --product LaunchScopeUISmoke
if [[ "$identity" == "-" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到稳定代码签名身份：$identity；UI 冒烟不会使用 ad-hoc。" >&2
  exit 1
fi
codesign --force --sign "$identity" --identifier com.nekutai.launchscope.ui-smoke "$runner"
exec "$runner"
