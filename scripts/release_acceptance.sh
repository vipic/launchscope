#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
tap_name="nekutai/launchscope-acceptance"
formula_name="$tap_name/launchscope-acceptance"
formula_template="$project_dir/Tests/ManualAcceptance/Formula/launchscope-acceptance.rb"
worker_template="$project_dir/Tests/ManualAcceptance/launchscope-acceptance-worker.sh"
plist_template="$project_dir/Tests/ManualAcceptance/com.nekutai.launchscope.acceptance.plist"
worker_download="/tmp/launchscope-acceptance-worker.sh"
agent_path="$HOME/Library/LaunchAgents/com.nekutai.launchscope.acceptance.plist"
shell_path="$HOME/.bashrc"
domain="gui/$(id -u)"
label="com.nekutai.launchscope.acceptance"
state_dir="$(mktemp -d /tmp/launchscope-release-acceptance.XXXXXX)"
cron_fixture="$state_dir/crontab"
shell_fixture="$state_dir/bashrc"
cleanup_failed=0
tap_created=0
formula_installed=0
worker_created=0
agent_created=0
cron_created=0
shell_created=0

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export LAUNCHSCOPE_APP_ARGUMENT="--release-acceptance"

cleanup() {
  if test "$agent_created" -eq 1; then
    launchctl bootout "$domain" "$agent_path" >/dev/null 2>&1 || true
    launchctl enable "$domain/$label" >/dev/null 2>&1 || true
    if test -f "$agent_path" && cmp -s "$agent_path" "$plist_template"; then
      unlink "$agent_path"
    elif test -e "$agent_path"; then
      echo "验收 LaunchAgent 已被外部修改，保留现场：$agent_path" >&2
      cleanup_failed=1
    fi
  fi

  if test "$cron_created" -eq 1 && crontab -l > "$state_dir/current-crontab" 2>/dev/null; then
    if cmp -s "$state_dir/current-crontab" "$cron_fixture"; then
      crontab -r
    else
      echo "验收期间 crontab 被外部修改，保留现场。" >&2
      cleanup_failed=1
    fi
  fi

  if test "$shell_created" -eq 1; then
    if test -f "$shell_path" && cmp -s "$shell_path" "$shell_fixture"; then
      unlink "$shell_path"
    elif test -e "$shell_path"; then
      echo "验收期间 $shell_path 被外部修改，保留现场。" >&2
      cleanup_failed=1
    fi
  fi

  if test "$formula_installed" -eq 1; then
    brew services stop "$formula_name" >/dev/null 2>&1 || true
    brew uninstall "$formula_name" >/dev/null 2>&1 || true
  fi
  if test "$tap_created" -eq 1; then brew untap "$tap_name" >/dev/null 2>&1 || true; fi
  if test "$worker_created" -eq 1 && test -e "$worker_download"; then unlink "$worker_download"; fi
  case "$state_dir" in
    /tmp/launchscope-release-acceptance.*) rm -R "$state_dir" ;;
    *) echo "拒绝清理非验收临时目录：$state_dir" >&2; cleanup_failed=1 ;;
  esac
  return "$cleanup_failed"
}
trap cleanup EXIT

cd "$project_dir"
test ! -e "$agent_path" || { echo "验收 Agent 已存在：$agent_path" >&2; exit 1; }
test ! -e "$shell_path" || { echo "为避免覆盖现有配置，验收要求 $shell_path 不存在。" >&2; exit 1; }
if crontab -l > "$state_dir/original-crontab" 2> "$state_dir/crontab-error"; then
  echo "为避免触碰现有任务，验收要求当前用户没有 crontab。" >&2
  exit 1
elif ! grep -qi "no crontab" "$state_dir/crontab-error"; then
  echo "无法确认 crontab 初始状态。" >&2
  exit 1
fi
if brew list --formula | grep -qx "launchscope-acceptance"; then
  echo "验收 formula 已存在，请先确认其来源。" >&2
  exit 1
fi
if brew tap | grep -qx "$tap_name"; then
  echo "验收 tap 已存在，请先确认其来源。" >&2
  exit 1
fi

cp "$worker_template" "$worker_download"
worker_created=1
brew tap-new --no-git "$tap_name" >/dev/null
tap_created=1
tap_path="$(brew --repository "$tap_name")"
cp "$formula_template" "$tap_path/Formula/launchscope-acceptance.rb"
brew install --formula "$formula_name" >/dev/null
formula_installed=1
brew services start "$formula_name"

cp "$plist_template" "$agent_path"
agent_created=1
launchctl bootstrap "$domain" "$agent_path"

printf '@reboot /opt/homebrew/opt/launchscope-acceptance/bin/launchscope-acceptance --once\n' > "$cron_fixture"
crontab "$cron_fixture"
cron_created=1
printf '/opt/homebrew/opt/launchscope-acceptance/bin/launchscope-acceptance --once\n' > "$shell_fixture"
cp "$shell_fixture" "$shell_path"
shell_created=1

scripts/ui_smoke.sh --release-acceptance

launchctl print "$domain/$label" >/dev/null
brew services list --json | /usr/bin/python3 -c 'import json,sys; services=json.load(sys.stdin); item=next((x for x in services if x.get("name")=="launchscope-acceptance"), None); raise SystemExit(0 if item and item.get("status")=="started" else 1)'
crontab -l > "$state_dir/final-crontab"
cmp "$state_dir/final-crontab" "$cron_fixture"
cmp "$shell_path" "$shell_fixture"
if grep -q "LaunchScope disabled" "$state_dir/final-crontab" "$shell_path"; then
  echo "验收项目未完全恢复。" >&2
  exit 1
fi

echo "发布控制验收通过：LaunchAgent、Homebrew、Cron、Shell 均完成停用、复扫、恢复及系统状态复核。"
