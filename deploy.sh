#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_name="LaunchScope"
build_dir="$project_dir/.build/debug"
app_dir="$HOME/Applications/${app_name} Dev.app"
contents="$app_dir/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"
launch_services_dir="$contents/Library/LaunchServices"
launch_daemons_dir="$contents/Library/LaunchDaemons"
identity="${CODESIGN_IDENTITY:-Nekutai}"

if [[ "$identity" == "-" ]]; then
  echo "LaunchScope 需要稳定代码签名，不能使用 ad-hoc 签名。" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到代码签名身份：$identity" >&2
  echo "请创建 Nekutai 自签名代码签名证书，或设置 CODESIGN_IDENTITY。" >&2
  exit 1
fi

cd "$project_dir"
swift build
test -x "$build_dir/$app_name"

pkill -f "LaunchScope Dev.app" 2>/dev/null || true
mkdir -p "$macos_dir" "$resources_dir" "$launch_services_dir" "$launch_daemons_dir"
cp "$build_dir/$app_name" "$macos_dir/$app_name"
cp "$build_dir/LaunchScopePrivilegedHelper" "$launch_services_dir/LaunchScopePrivilegedHelper"
cp "$project_dir/scripts/com.nekutai.launchscope.helper.plist" "$launch_daemons_dir/com.nekutai.launchscope.helper.plist"
cp "$project_dir/Sources/LaunchScope/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"

version="$(git describe --tags --abbrev=0 2>/dev/null || echo 0.1.0)-dev"
build="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

plist="$contents/Info.plist"
cp "$project_dir/scripts/Info.plist.template" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nekutai.launchscope.dev" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'LaunchScope Dev'" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"

rm -rf "$contents/_CodeSignature"
codesign --force --sign "$identity" --identifier com.nekutai.launchscope.helper "$launch_services_dir/LaunchScopePrivilegedHelper"
codesign --force --deep --sign "$identity" "$app_dir"
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
open "$app_dir"
echo "LaunchScope Dev 已部署：$app_dir"
