#!/usr/bin/env bash
set -euo pipefail

latest_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")"
current_version="${latest_tag#v}"

if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "不支持的当前版本标签：$latest_tag" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
range="HEAD"
if git rev-parse --verify --quiet "$latest_tag^{commit}" >/dev/null; then
  range="$latest_tag..HEAD"
fi

commits="$(git log "$range" --pretty=format:%B --no-merges 2>/dev/null || true)"
if [[ -z "$(printf '%s' "$commits" | tr -d '[:space:]')" ]]; then
  echo "$current_version"
  exit 0
fi

if printf '%s\n' "$commits" | grep -Eq '(^[[:alpha:]]+(\([^)]+\))?!:|^BREAKING CHANGE:|^BREAKING-CHANGE:)'; then
  major=$((major + 1))
  minor=0
  patch=0
elif printf '%s\n' "$commits" | grep -Eq '^feat(\([^)]+\))?:'; then
  minor=$((minor + 1))
  patch=0
else
  patch=$((patch + 1))
fi

echo "$major.$minor.$patch"
