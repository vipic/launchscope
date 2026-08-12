#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
publish="${2:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：./release.sh <x.y.z> [--publish]" >&2
  exit 1
fi

project_dir="$(cd "$(dirname "$0")" && pwd)"
identity="${CODESIGN_IDENTITY:-Nekutai}"
staging="$project_dir/.release_staging"
app_dir="$staging/LaunchScope.app"
contents="$app_dir/Contents"
launch_services="$contents/Library/LaunchServices"
launch_daemons="$contents/Library/LaunchDaemons"
dist="$project_dir/dist"

if [[ "$identity" == "-" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到稳定代码签名身份：$identity；不会回退为 ad-hoc。" >&2
  exit 1
fi

cd "$project_dir"
mise run check
test -z "$(git status --porcelain)" || { echo "工作区存在未提交改动，停止发布。" >&2; exit 1; }
if git rev-parse "$version" >/dev/null 2>&1; then
  echo "版本标签已存在：$version" >&2
  exit 1
fi

rm -rf "$staging"
mkdir -p "$contents/MacOS" "$contents/Resources" "$launch_services" "$launch_daemons" "$dist"
cp ".build/release/LaunchScope" "$contents/MacOS/LaunchScope"
cp ".build/release/LaunchScopePrivilegedHelper" "$launch_services/LaunchScopePrivilegedHelper"
cp "scripts/com.nekutai.launchscope.helper.plist" "$launch_daemons/com.nekutai.launchscope.helper.plist"
cp "Sources/LaunchScope/Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"
cp "scripts/Info.plist.template" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$contents/Info.plist"
codesign --force --sign "$identity" --identifier com.nekutai.launchscope.helper "$launch_services/LaunchScopePrivilegedHelper"
codesign --force --deep --sign "$identity" "$app_dir"
scripts/verify_release.sh "$app_dir" "$version"

dmg="$dist/LaunchScope-$version.dmg"
rm -f "$dmg"
hdiutil create -volname LaunchScope -srcfolder "$app_dir" -ov -format UDZO "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
shasum -a 256 "$dmg" > "$dmg.sha256"
echo "发布产物：$dmg"
echo "校验文件：$dmg.sha256"

if [[ "$publish" == "--publish" ]]; then
  command -v gh >/dev/null || { echo "缺少 gh CLI" >&2; exit 1; }
  git tag "$version"
  git push origin "$version"
  gh release create "$version" "$dmg" "$dmg.sha256" --generate-notes --title "LaunchScope $version"
fi
