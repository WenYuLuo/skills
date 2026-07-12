#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  preflight-pr.sh <repo> --title TITLE --body-file FILE [--base REF]
  preflight-pr.sh <repo> --iid IID [--base REF] [--comment-check-pr]

Validates every local commit in BASE..HEAD, the MR title, and the MR template body.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
REPO=$(resolve_repo "$1"); shift
BASE="" TITLE="" BODY_FILE="" IID="" COMMENT_CHECK_PR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --iid) IID="${2:-}"; shift 2 ;;
    --comment-check-pr) COMMENT_CHECK_PR=true; shift ;;
    *) echo "ERROR: 未知参数: $1" >&2; usage ;;
  esac
done

if [[ -z "$BASE" ]]; then
  if git rev-parse --verify upstream/master >/dev/null 2>&1; then
    BASE=upstream/master
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then
    BASE=origin/master
  else
    BASE=master
  fi
fi

git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "ERROR: base ref 不存在: $BASE" >&2
  exit 1
}

validate_yr_commit_range "$BASE"

if [[ -n "$IID" ]]; then
  require_gitcode_token
  mr=$(gitcode_get "repos/$REPO/pulls/$IID" '.')
  TITLE=$(printf '%s\n' "$mr" | jq -r '.title')
  BODY=$(printf '%s\n' "$mr" | jq -r '.body // ""')
else
  [[ -n "$TITLE" && -n "$BODY_FILE" ]] || usage
  [[ -f "$BODY_FILE" ]] || { echo "ERROR: body file 不存在: $BODY_FILE" >&2; exit 1; }
  BODY=$(cat "$BODY_FILE")
fi

validate_yr_mr_body "$REPO" "$TITLE" "$BODY"

if $COMMENT_CHECK_PR; then
  [[ -n "$IID" ]] || { echo "ERROR: --comment-check-pr 需要 --iid" >&2; exit 1; }
  gitcode_post "repos/$REPO/pulls/$IID/comments" '{"body":"/check-pr"}' >/dev/null
  echo ">>> 已评论 /check-pr"
fi

echo ">>> PR preflight PASS: $REPO, base=$BASE, title=$TITLE"
