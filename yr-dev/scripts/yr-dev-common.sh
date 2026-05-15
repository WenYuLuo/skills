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

declare -Ag YR_REPOS=(
  [yuanrong]=openeuler/yuanrong
  [main]=openeuler/yuanrong
  [core]=openeuler/yuanrong
  [datasystem]=openeuler/yuanrong-datasystem
  [ds]=openeuler/yuanrong-datasystem
  [functionsystem]=openeuler/yuanrong-functionsystem
  [fs]=openeuler/yuanrong-functionsystem
  [func]=openeuler/yuanrong-functionsystem
  [frontend]=openeuler/yuanrong-frontend
  [fe]=openeuler/yuanrong-frontend
  [runtime]=openeuler/yuanrong-runtime
  [rt]=openeuler/yuanrong-runtime
  [ray-adapter]=openeuler/ray-adapter
  [ray]=openeuler/ray-adapter
)

resolve_repo() {
  local name="${1,,}"
  echo "${YR_REPOS[$name]:-$name}"
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

load_yr_dev_config
