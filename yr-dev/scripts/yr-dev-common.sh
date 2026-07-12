#!/usr/bin/env bash

YR_DEV_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
YR_DEV_SKILL_DIR=$(cd "$YR_DEV_SCRIPT_DIR/.." && pwd)

load_yr_dev_config() {
  local keep_token="${GITCODE_TOKEN-__YR_UNSET__}"
  local keep_base="${GITCODE_API_BASE-__YR_UNSET__}"
  local keep_name="${YR_SIGNOFF_NAME-__YR_UNSET__}"
  local keep_email="${YR_SIGNOFF_EMAIL-__YR_UNSET__}"
  local keep_signoff="${YR_SIGNOFF-__YR_UNSET__}"

  local config_files=()
  if [[ -n "${YR_DEV_CONFIG:-}" ]]; then
    config_files+=("$YR_DEV_CONFIG")
  else
    config_files+=("$HOME/.config/yr-dev/gitcode.env")
    config_files+=("$YR_DEV_SKILL_DIR/config/gitcode.env.local")
  fi

  local f
  for f in "${config_files[@]}"; do
    if [[ -f "$f" ]]; then
      # shellcheck disable=SC1090
      set -a; source "$f"; set +a
    fi
  done

  [[ "$keep_token" != __YR_UNSET__ ]] && GITCODE_TOKEN="$keep_token"
  [[ "$keep_base" != __YR_UNSET__ ]] && GITCODE_API_BASE="$keep_base"
  [[ "$keep_name" != __YR_UNSET__ ]] && YR_SIGNOFF_NAME="$keep_name"
  [[ "$keep_email" != __YR_UNSET__ ]] && YR_SIGNOFF_EMAIL="$keep_email"
  [[ "$keep_signoff" != __YR_UNSET__ ]] && YR_SIGNOFF="$keep_signoff"

  : "${GITCODE_API_BASE:=https://gitcode.com/api/v5}"
}

require_gitcode_token() {
  if [[ -z "${GITCODE_TOKEN:-}" ]]; then
    echo "ERROR: GITCODE_TOKEN is required. Run scripts/init-config.sh or export GITCODE_TOKEN." >&2
    exit 2
  fi
}

yr_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_repo() {
  local name
  name=$(yr_lower "$1")
  case "$name" in
    yuanrong|main|core) echo "openeuler/yuanrong" ;;
    datasystem|ds) echo "openeuler/yuanrong-datasystem" ;;
    functionsystem|fs|func) echo "openeuler/yuanrong-functionsystem" ;;
    frontend|fe) echo "openeuler/yuanrong-frontend" ;;
    runtime|rt) echo "openeuler/yuanrong-runtime" ;;
    ray-adapter|ray) echo "openeuler/ray-adapter" ;;
    *) echo "$name" ;;
  esac
}

gitcode_get() {
  require_gitcode_token
  curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/$1" | jq "${2:-.}"
}

gitcode_post() {
  require_gitcode_token
  local path="$1" payload="$2"
  curl -sf -X POST "$GITCODE_API_BASE/$path" \
    -H "Content-Type: application/json" \
    -H "private-token: $GITCODE_TOKEN" \
    -d "$payload"
}

gitcode_patch() {
  require_gitcode_token
  local path="$1" payload="$2"
  curl -sf -X PATCH "$GITCODE_API_BASE/$path" \
    -H "Content-Type: application/json" \
    -H "private-token: $GITCODE_TOKEN" \
    -d "$payload"
}

yr_subject_pattern='^(fix|feat|docs|style|refactor|test|chore|perf|ci|build|revert)(\([^)]+\)|\[[^]]+\])?:[[:space:]]*[^[:space:]].*$'

validate_yr_subject() {
  local subject="$1" label="${2:-title}"
  if ! printf '%s\n' "$subject" | grep -Eq "$yr_subject_pattern"; then
    echo "ERROR: $label 不符合 type(scope): 描述 规范: $subject" >&2
    return 1
  fi
}

validate_yr_commit_message() {
  local message="$1" label="${2:-commit}"
  local subject signoff_count
  subject=$(printf '%s\n' "$message" | head -n 1)
  validate_yr_subject "$subject" "$label subject" || return 1
  signoff_count=$(printf '%s\n' "$message" | grep -c '^Signed-off-by: .\+ <[^<>[:space:]]\+@[^<>[:space:]]\+>$' || true)
  if [[ "$signoff_count" -ne 1 ]]; then
    echo "ERROR: $label 必须且只能包含一行有效 Signed-off-by，当前为 $signoff_count" >&2
    return 1
  fi
  if printf '%s\n' "$message" | grep -Eqi '^Co-authored-by:'; then
    echo "ERROR: $label 禁止 Co-authored-by，避免引入未签 CLA 的署名" >&2
    return 1
  fi
}

validate_yr_commit_range() {
  local base="$1" failed=0 sha message
  git rev-parse --verify "$base" >/dev/null 2>&1 || {
    echo "ERROR: base ref 不存在: $base" >&2
    return 1
  }
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    message=$(git show -s --format='%B' "$sha")
    validate_yr_commit_message "$message" "commit ${sha:0:12}" || failed=1
  done < <(git rev-list --reverse "$base"..HEAD)
  [[ "$failed" -eq 0 ]]
}

yr_title_type() {
  printf '%s\n' "$1" | sed -E 's/^([a-z]+).*/\1/'
}

validate_yr_mr_body() {
  local repo="$1" title="$2" body="$3"
  local title_type kind
  validate_yr_subject "$title" "MR title" || return 1
  title_type=$(yr_title_type "$title")
  kind=$(printf '%s\n' "$body" | sed -nE 's#^[[:space:]]*/kind[[:space:]]+([^[:space:]]+).*$#\1#p' | head -n 1)
  if [[ -z "$kind" ]]; then
    echo "ERROR: MR body 缺少 /kind" >&2
    return 1
  fi
  case "$title_type:$kind" in
    feat:feat|feat:feature|fix:fix|fix:bug|docs:docs|perf:perf|style:style|chore:chore|revert:revert|refactor:refactor|ci:ci|test:test|build:build) ;;
    *)
      echo "ERROR: MR title type '$title_type' 与 /kind '$kind' 不一致" >&2
      return 1
      ;;
  esac
  if ! printf '%s\n' "$body" | grep -Eq 'Fixes[[:space:]]+#'; then
    echo "ERROR: MR body 缺少 Fixes # 段" >&2
    return 1
  fi
  if ! printf '%s\n' "$body" | grep -Eqi 'test|测试|验证'; then
    echo "ERROR: MR body 缺少测试/验证说明" >&2
    return 1
  fi
  if ! printf '%s\n' "$body" | grep -Eqi 'interface|接口'; then
    echo "ERROR: MR body 缺少接口变化说明" >&2
    return 1
  fi
  if ! printf '%s\n' "$body" | grep -Eq '\[[xX]\]'; then
    echo "ERROR: MR body 缺少已完成的自检项 [x]" >&2
    return 1
  fi
  : "$repo"
}

commit_signoff() {
  if [[ -n "${YR_SIGNOFF:-}" ]]; then
    printf '%s\n' "$YR_SIGNOFF"
    return
  fi

  local name="${YR_SIGNOFF_NAME:-$(git config user.name 2>/dev/null || true)}"
  local email="${YR_SIGNOFF_EMAIL:-$(git config user.email 2>/dev/null || true)}"
  if [[ -z "$name" || -z "$email" ]]; then
    echo "ERROR: set YR_SIGNOFF_NAME/YR_SIGNOFF_EMAIL or git config user.name/user.email." >&2
    exit 2
  fi
  printf 'Signed-off-by: %s <%s>\n' "$name" "$email"
}

extract_repo_path_from_remote_url() {
  local remote_url="$1"
  remote_url="${remote_url%.git}"
  remote_url="${remote_url#ssh://}"
  remote_url="${remote_url#https://}"
  remote_url="${remote_url#http://}"
  remote_url="${remote_url#git@}"
  remote_url="${remote_url#oauth2:}"
  remote_url="${remote_url#*@}"
  case "$remote_url" in
    gitcode.com:2222/*) remote_url="${remote_url#gitcode.com:2222/}" ;;
    gitcode.com:*) remote_url="${remote_url#gitcode.com:}" ;;
    gitcode.com/*) remote_url="${remote_url#gitcode.com/}" ;;
  esac
  printf '%s\n' "$remote_url"
}

current_origin_repo_path() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || true)
  if [[ -z "$remote_url" ]]; then
    return 1
  fi
  extract_repo_path_from_remote_url "$remote_url"
}

load_yr_dev_config
