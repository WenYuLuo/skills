#!/usr/bin/env bash
# review-pr.sh - 查看 MR 的完整 patch，方便 Claude 做代码审查
# 用法:
#   review-pr.sh yuanrong 533              # 输出完整 diff 供审查
#   review-pr.sh yuanrong 533 --raw        # 输出原始 JSON（含 patch）
#   review-pr.sh yuanrong 533 --files      # 只输出文件列表
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"
require_gitcode_token

REPO=$(resolve_repo "${1:-yuanrong}")
IID="$2"
MODE="diff"

for arg in "${@:3}"; do
    case "$arg" in
        --raw) MODE="raw" ;;
        --files) MODE="files" ;;
    esac
done

# 获取 MR 基本信息
MR_DATA=$(curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID")
echo "MR !${IID}: $(echo "$MR_DATA" | jq -r '.title')"
echo "分支: $(echo "$MR_DATA" | jq -r '.head.ref') -> $(echo "$MR_DATA" | jq -r '.base.ref')"
echo "作者: $(echo "$MR_DATA" | jq -r '.head.user.login')"
echo "变更: +$(echo "$MR_DATA" | jq -r '.additions') -$(echo "$MR_DATA" | jq -r '.deletions')"
echo ""

case "$MODE" in
    files)
        curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID/files" \
            | jq -r '.[] | "\(.status)\t+\(.additions)\t-\(.deletions)\t\(.filename)"'
        ;;
    raw)
        curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID/files" \
            | jq '.[] | {filename, status, additions, deletions, patch}'
        ;;
    *)
        curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID/files" \
            | jq -r '.[] | "diff --git a/\(.filename)\n\(.patch)"' \
            | sed 's/\\t/\t/g'
        ;;
esac
