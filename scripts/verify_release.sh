#!/usr/bin/env bash
set -euo pipefail

app_dir="${1:-}"
expected_version="${2:-}"
if [[ -z "$app_dir" || -z "$expected_version" ]]; then
  echo "用法：scripts/verify_release.sh <LaunchScope.app> <x.y.z>" >&2
  exit 1
fi

info_plist="$app_dir/Contents/Info.plist"
executable="$app_dir/Contents/MacOS/LaunchScope"
icon="$app_dir/Contents/Resources/AppIcon.icns"
helper="$app_dir/Contents/Library/LaunchServices/LaunchScopePrivilegedHelper"
helper_plist="$app_dir/Contents/Library/LaunchDaemons/com.nekutai.launchscope.helper.plist"

test -d "$app_dir"
test -f "$info_plist"
test -x "$executable"
test -s "$icon"
test -x "$helper"
test -f "$helper_plist"

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"

[[ "$actual_version" == "$expected_version" ]]
[[ "$bundle_id" == "com.nekutai.launchscope" ]]
[[ "$minimum_system" == "26.0" ]]
codesign --verify --deep --strict "$app_dir"
codesign --verify --strict "$helper"
helper_identifier="$(codesign -dvv "$helper" 2>&1 | sed -n 's/^Identifier=//p')"
[[ "$helper_identifier" == "com.nekutai.launchscope.helper" ]]
codesign -dv "$app_dir" 2>&1 | grep -Fq 'Signature=adhoc' && {
  echo "发布应用不能使用 ad-hoc 签名" >&2
  exit 1
}

echo "发布应用验收通过：$app_dir ($expected_version)"
