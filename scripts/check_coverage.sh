#!/usr/bin/env bash
set -euo pipefail

minimum="${1:-35}"
profile="$(find .build -path '*/debug/codecov/default.profdata' -print -quit)"

if [[ -z "$profile" ]]; then
  echo "Coverage profile not found. Run: swift test --enable-code-coverage" >&2
  exit 1
fi

debug_dir="${profile%/codecov/default.profdata}"
binary="$debug_dir/LaunchScopePackageTests.xctest/Contents/MacOS/LaunchScopePackageTests"
if [[ ! -x "$binary" ]]; then
  echo "Coverage test binary not found: $binary" >&2
  exit 1
fi

summary_file="$(mktemp -t launchscope-coverage).json"
trap 'rm -f "$summary_file"' EXIT

xcrun llvm-cov export \
  -summary-only \
  -format=text \
  "$binary" \
  -instr-profile "$profile" \
  -ignore-filename-regex='Tests|LaunchScopeApp.swift|/UI/|resource_bundle_accessor.swift' > "$summary_file"

coverage="$(plutil -extract 'data.0.totals.lines.percent' raw -o - "$summary_file")"
echo "Line coverage: ${coverage}% (minimum: ${minimum}%)"

awk -v coverage="$coverage" -v minimum="$minimum" 'BEGIN {
  if (coverage + 0 < minimum + 0) {
    printf("Coverage %.2f%% is below %.2f%%\n", coverage, minimum) > "/dev/stderr"
    exit 1
  }
}'
