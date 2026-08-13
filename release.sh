#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
version=""
publish=false
auto_version=false
allow_dirty=false
for argument in "$@"; do
  case "$argument" in
    --publish) publish=true ;;
    --auto-version) auto_version=true ;;
    --allow-dirty) allow_dirty=true ;;
    --*) echo "未知参数：$argument" >&2; exit 2 ;;
    *)
      [[ -z "$version" ]] || { echo "只能指定一个版本号。" >&2; exit 2; }
      version="$argument"
      ;;
  esac
done

if $auto_version; then
  [[ -z "$version" ]] || { echo "--auto-version 不能与显式版本同时使用。" >&2; exit 2; }
  $publish && { echo "正式发布必须显式确认版本号，不能使用 --auto-version。" >&2; exit 2; }
  version="$($project_dir/scripts/next_version.sh)"
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：./release.sh <x.y.z> [--publish] [--allow-dirty] | ./release.sh --auto-version" >&2
  exit 2
fi

identity="${CODESIGN_IDENTITY:-Nekutai}"
staging="$project_dir/.release_staging"
app_dir="$staging/LaunchScope.app"
contents="$app_dir/Contents"
launch_services="$contents/Library/LaunchServices"
launch_daemons="$contents/Library/LaunchDaemons"
dist="$project_dir/dist"
dmg="$dist/LaunchScope-$version.dmg"
checksum="$dmg.sha256"
branch=""
repository=""
dmg_mount=""

source "$project_dir/scripts/lib/command_log.sh"
workflow="release"
$publish && workflow="publish"
command_log_init "$workflow" "$version"

cleanup() {
  local status=$?
  if [[ -n "$dmg_mount" ]]; then
    hdiutil detach "$dmg_mount" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$staging"
  command_log_finish "$status"
}
trap cleanup EXIT

step() {
  echo
  echo "━━━ $1 ━━━"
  command_log_stage "$1"
}

cd "$project_dir"
step "1-发布预检"
$publish && $allow_dirty && { echo "--allow-dirty 只能用于本地制品验收，不能用于正式发布。" >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]] && ! $allow_dirty; then
  echo "工作区存在未提交改动，停止发布。" >&2
  exit 1
fi
if [[ "$identity" == "-" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo "找不到稳定代码签名身份：$identity；不会回退为 ad-hoc。" >&2
  exit 1
fi
if git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
  echo "本地版本标签已存在：$version" >&2
  exit 1
fi

if $publish; then
  command -v gh >/dev/null || { echo "缺少 gh CLI。" >&2; exit 1; }
  git remote get-url origin >/dev/null 2>&1 || { echo "缺少 Git 远端 origin。" >&2; exit 1; }
  branch="$(git branch --show-current)"
  [[ "$branch" == "main" ]] || { echo "正式发布必须从 main 分支执行，当前为：${branch:-detached HEAD}" >&2; exit 1; }
  command_log_run gh_auth gh auth status
  repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  command_log_run remote_connectivity git ls-remote origin >/dev/null
  if git ls-remote --tags origin "refs/tags/$version" | grep -q .; then
    echo "远端版本标签已存在：$version" >&2
    exit 1
  fi
  if gh release view "$version" --repo "$repository" >/dev/null 2>&1; then
    echo "GitHub Release 已存在：$version；拒绝覆盖正式制品。" >&2
    exit 1
  fi
fi

step "2-统一验证"
command_log_run check mise run check
if [[ -n "$(git status --porcelain)" ]] && ! $allow_dirty; then
  echo "验证过程改变了工作区，停止发布。" >&2
  exit 1
fi

step "3-组装应用"
mkdir -p "$contents/MacOS" "$contents/Resources" "$launch_services" "$launch_daemons" "$dist"
cp ".build/release/LaunchScope" "$contents/MacOS/LaunchScope"
cp ".build/release/LaunchScopePrivilegedHelper" "$launch_services/LaunchScopePrivilegedHelper"
cp "scripts/com.nekutai.launchscope.helper.plist" "$launch_daemons/com.nekutai.launchscope.helper.plist"
cp "Sources/LaunchScope/Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"
cp "scripts/Info.plist.template" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$contents/Info.plist"
command_log_run strip_app strip -S "$contents/MacOS/LaunchScope"
command_log_run strip_helper strip -S "$launch_services/LaunchScopePrivilegedHelper"

step "4-签名与应用验证"
command_log_run sign_helper codesign --force --sign "$identity" \
  --identifier com.nekutai.launchscope.helper "$launch_services/LaunchScopePrivilegedHelper"
command_log_run sign_app codesign --force --deep --sign "$identity" "$app_dir"
command_log_run verify_app scripts/verify_release.sh "$app_dir" "$version"

step "5-DMG 打包与校验"
dmg_root="$staging/dmg-root"
mkdir -p "$dmg_root"
ditto "$app_dir" "$dmg_root/LaunchScope.app"
ln -s /Applications "$dmg_root/Applications"
mkdir -p "$dmg_root/.background"
cp "Resources/dmg-background.tiff" "$dmg_root/.background/background.tiff"
command -v SetFile >/dev/null 2>&1 && SetFile -a V "$dmg_root/.background"
rm -f "$dmg" "$checksum"
writable_dmg="$staging/LaunchScope-rw.dmg"
dmg_size_kb="$(du -sk "$dmg_root" | cut -f1)"
dmg_size_mb=$(( (dmg_size_kb + 1023) / 1024 + 8 ))
command_log_run create_writable_dmg hdiutil create -volname LaunchScope -srcfolder "$dmg_root" \
  -ov -format UDRW -size "${dmg_size_mb}m" "$writable_dmg"

dmg_mount="$staging/dmg-mount"
mkdir -p "$dmg_mount"
command_log_run attach_writable_dmg hdiutil attach "$writable_dmg" -readwrite -noverify \
  -noautoopen -mountpoint "$dmg_mount"
command_log_run layout_dmg osascript scripts/layout_dmg.applescript "$dmg_mount"
[[ -f "$dmg_mount/.DS_Store" ]] || { echo "Finder 未生成 DMG 布局记录。" >&2; exit 1; }
[[ -f "$dmg_mount/.background/background.tiff" ]] || { echo "DMG 背景文件缺失。" >&2; exit 1; }
sync
command_log_run detach_writable_dmg hdiutil detach "$dmg_mount"
dmg_mount=""

command_log_run create_dmg hdiutil convert "$writable_dmg" -format UDZO -o "$dmg"
command_log_run verify_dmg hdiutil verify "$dmg"
shasum -a 256 "$dmg" > "$checksum"
command_log_artifact dmg "$dmg"
command_log_artifact checksum "$checksum"

step "6-正式制品烟测"
command_log_run smoke_release scripts/release_smoke.sh "$dmg" "$version"
echo "发布产物：$dmg"
echo "校验文件：$checksum"

if $publish; then
  step "7-GitHub 发布"
  release_notes="$staging/release-notes.md"
  scripts/generate_release_notes.sh > "$release_notes"
  git tag -a "$version" -m "LaunchScope $version"
  if ! command_log_run push_atomic git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/$version"; then
    git tag -d "$version" >/dev/null
    echo "源码分支与版本标签推送失败，本地标签已回滚。" >&2
    exit 1
  fi
  if ! command_log_run create_release gh release create "$version" "$dmg" "$checksum" \
      --repo "$repository" --notes-file "$release_notes" --title "LaunchScope $version"; then
    git push origin ":refs/tags/$version" >/dev/null 2>&1 || true
    git tag -d "$version" >/dev/null
    echo "GitHub Release 创建失败，本轮版本标签已回滚；已推送的源码分支保留。" >&2
    exit 1
  fi
else
  step "7-跳过 GitHub 发布"
  echo "仅生成本地签名制品；未创建标签或 GitHub Release。"
fi
