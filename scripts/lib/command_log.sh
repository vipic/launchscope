#!/usr/bin/env bash
# 发布工作流的本地结构化日志；只写入已忽略的 .local/logs。

command_log_initialized=false
command_log_finished=false
command_log_stage_name=""
command_log_stage_started=0
command_log_started=0

command_log_now_ms() {
  perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

command_log_init() {
  local workflow="$1"
  local version="${2:-unknown}"
  local timestamp
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  command_log_dir="$project_dir/.local/logs/$workflow"
  command_log_file="$command_log_dir/${timestamp}-$$.log"
  command_log_summary="$command_log_dir/.${timestamp}-$$.summary"
  mkdir -p "$command_log_dir"
  : > "$command_log_file"
  : > "$command_log_summary"
  ln -sfn "$(basename "$command_log_file")" "$command_log_dir/latest.log"
  command_log_started="$(command_log_now_ms)"
  command_log_initialized=true
  printf '%s level=INFO event=workflow.start workflow=%q version=%q\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$workflow" "$version" >> "$command_log_file"
  echo "本地命令日志：$command_log_file"
}

command_log_finish_stage() {
  local status="${1:-0}"
  [[ -n "$command_log_stage_name" ]] || return 0
  local duration=$(( $(command_log_now_ms) - command_log_stage_started ))
  printf '%s|%s|%s\n' "$command_log_stage_name" "$duration" "$status" >> "$command_log_summary"
  printf '%s level=INFO event=stage.finish label=%q duration_ms=%s exit_code=%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$command_log_stage_name" "$duration" "$status" >> "$command_log_file"
  command_log_stage_name=""
}

command_log_stage() {
  command_log_finish_stage 0
  command_log_stage_name="$1"
  command_log_stage_started="$(command_log_now_ms)"
  printf '%s level=INFO event=stage.start label=%q\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$command_log_stage_name" >> "$command_log_file"
}

command_log_run() {
  local label="$1"
  shift
  local started status had_errexit=false
  started="$(command_log_now_ms)"
  [[ $- == *e* ]] && had_errexit=true
  set +e
  "$@" 2>&1 | tee -a "$command_log_file"
  status=${PIPESTATUS[0]}
  $had_errexit && set -e
  printf '%s level=%s event=command.finish label=%q duration_ms=%s exit_code=%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$([[ $status -eq 0 ]] && echo INFO || echo ERROR)" \
    "$label" "$(( $(command_log_now_ms) - started ))" "$status" >> "$command_log_file"
  return "$status"
}

command_log_artifact() {
  local label="$1"
  local path="$2"
  printf '%s level=INFO event=artifact label=%q path=%q size_bytes=%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$label" "$path" "$(stat -f%z "$path")" >> "$command_log_file"
}

command_log_finish() {
  local status="${1:-0}"
  $command_log_initialized || return 0
  $command_log_finished && return 0
  command_log_finished=true
  command_log_finish_stage "$status"
  local total=$(( $(command_log_now_ms) - command_log_started ))
  printf '%s level=%s event=workflow.finish duration_ms=%s exit_code=%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$([[ $status -eq 0 ]] && echo INFO || echo ERROR)" "$total" "$status" >> "$command_log_file"
  echo
  echo "命令耗时汇总："
  while IFS='|' read -r label duration stage_status; do
    [[ -n "$label" ]] || continue
    printf '  %-30s %8.2fs  exit=%s\n' "$label" "$(awk "BEGIN { print $duration / 1000 }")" "$stage_status"
  done < "$command_log_summary"
  printf '  %-30s %8.2fs\n' "总计" "$(awk "BEGIN { print $total / 1000 }")"
  echo "  日志：$command_log_file"
  rm -f "$command_log_summary"
}
