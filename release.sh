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
branch=""
repository=""

cd "$project_dir"

if [[ "$publish" == "--publish" ]]; then
  command -v gh >/dev/null || { echo "缺少 gh CLI" >&2; exit 1; }
  git remote get-url origin >/dev/null 2>&1 || { echo "缺少 Git 远端 origin，停止发布。" >&2; exit 1; }
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || { echo "当前处于 detached HEAD，停止发布。" >&2; exit 1; }
  gh auth status >/dev/null
  repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  git ls-remote origin >/dev/null
  if git ls-remote --tags origin "refs/tags/$version" | grep -q .; then
    echo "远端版本标签已存在：$version" >&2
    exit 1
  fi
  if gh release view "$version" --repo "$repository" >/dev/null 2>&1; then
    echo "GitHub Release 已存在：$version" >&2
    exit 1
  fi
fi

if [[ "$identity" == "-" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到稳定代码签名身份：$identity；不会回退为 ad-hoc。" >&2
  exit 1
fi

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
ln -s /Applications "$staging/Applications"
hdiutil create -volname LaunchScope -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
shasum -a 256 "$dmg" > "$dmg.sha256"
scripts/release_smoke.sh "$dmg" "$version"
echo "发布产物：$dmg"
echo "校验文件：$dmg.sha256"

if [[ "$publish" == "--publish" ]]; then
  git tag -a "$version" -m "LaunchScope $version"
  if ! git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/$version"; then
    git tag -d "$version" >/dev/null
    echo "源码分支与版本标签推送失败，本地标签已回滚。" >&2
    exit 1
  fi
  if ! gh release create "$version" "$dmg" "$dmg.sha256" \
      --repo "$repository" --generate-notes --title "LaunchScope $version"; then
    git push origin ":refs/tags/$version" >/dev/null 2>&1 || true
    git tag -d "$version" >/dev/null
    echo "GitHub Release 创建失败，本轮版本标签已回滚；已推送的源码分支保留。" >&2
    exit 1
  fi
fi
