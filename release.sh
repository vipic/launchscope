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
dist="$project_dir/dist"

if [[ "$identity" == "-" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到稳定代码签名身份：$identity；不会回退为 ad-hoc。" >&2
  exit 1
fi

cd "$project_dir"
mise run check
swift build -c release -Xswiftc -Osize

rm -rf "$staging"
mkdir -p "$contents/MacOS" "$contents/Resources" "$dist"
cp ".build/release/LaunchScope" "$contents/MacOS/LaunchScope"
cp "Sources/LaunchScope/Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"
cp "scripts/Info.plist.template" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$contents/Info.plist"
codesign --force --deep --sign "$identity" "$app_dir"
codesign --verify --deep --strict "$app_dir"

dmg="$dist/LaunchScope-$version.dmg"
rm -f "$dmg"
hdiutil create -volname LaunchScope -srcfolder "$app_dir" -ov -format UDZO "$dmg" >/dev/null
echo "发布产物：$dmg"

if [[ "$publish" == "--publish" ]]; then
  command -v gh >/dev/null || { echo "缺少 gh CLI" >&2; exit 1; }
  git tag "$version"
  git push origin "$version"
  gh release create "$version" "$dmg" --generate-notes --title "LaunchScope $version"
fi
