#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
hits="$(grep -rEn 'Color\((red:|\.sRGB)|\.font\(\.system\(size:|cornerRadius: [0-9]' Sources/LaunchScope \
  --include='*.swift' --exclude='UIConstants.swift' || true)"
if [[ -n "$hits" ]]; then
  echo "设计调用点出现未收敛的颜色、字号或圆角字面量；请使用 UIConstants 或文件内私有 token：" >&2
  echo "$hits" >&2
  exit 1
fi
echo "设计 token 检查通过。"
