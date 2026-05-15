#!/usr/bin/env bash
# create-pr.sh - 创建 MR 完整流程（建分支、提交、推送、创建 MR）
# 依赖: git, curl, jq
# 用法:
#   create-pr.sh yuanrong "fix(docs): 修复xxx" "详细说明"  # 自动分支名
#   create-pr.sh yuanrong "fix(docs): 修复xxx" "详细说明" my-branch  # 指定分支名
#   create-pr.sh yuanrong "fix(docs): 修复xxx" "" my-branch master
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"
require_gitcode_token

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: 不在 git 仓库内" >&2; exit 1
fi

REPO_SHORT="${1:-yuanrong}"
REPO=$(resolve_repo "$REPO_SHORT")
TITLE="${2:-}"
BODY="${3:-}"
BRANCH_NAME="${4:-}"
BASE_BRANCH="${5:-master}"

if [ -z "$TITLE" ]; then
    echo "Usage: create-pr.sh <repo> <title> [body] [branch-name] [base-branch]" >&2
    echo "  repo: yuanrong|ds|fs|fe 或完整路径" >&2
    exit 1
fi

# 自动生成分支名
if [ -z "$BRANCH_NAME" ]; then
    # 从 title 生成: fix(docs): 修复编译 -> fix/docs-修复编译
    type_scope=$(echo "$TITLE" | sed -E 's/^([a-z]+)(\([^)]+\)|\[[^\]]+\]):.*/\1\2/' | tr '()[]' '/' | tr '[:upper:]' '[:lower:]')
    desc=$(echo "$TITLE" | sed -E 's/^[a-z]+(\([^)]+\)|\[[^\]]+\]): *//' | head -c 40 | tr ' ' '-' | tr -cd 'a-zA-Z0-9_-')
    BRANCH_NAME="${type_scope:-fix}/${desc}"
    # 简化连续分隔符
    BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
fi

echo "======================================="
echo "  Repo:   $REPO"
echo "  Branch: $BRANCH_NAME -> $BASE_BRANCH"
echo "  Title:  $TITLE"
echo "======================================="

# 创建并切换分支
echo ">>> git checkout -b $BRANCH_NAME origin/$BASE_BRANCH"
git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
if git show-ref --verify refs/heads/"$BRANCH_NAME" >/dev/null 2>&1; then
    git checkout "$BRANCH_NAME"
else
    git checkout -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
fi

# 提交所有更改
SIGNOFF=$(commit_signoff)
FULL_MSG="$TITLE"
if [ -n "$BODY" ]; then
    FULL_MSG="$FULL_MSG"$'\n\n'"$BODY"
fi
FULL_MSG="$FULL_MSG"$'\n\n'"$SIGNOFF"

git add -A
git commit -m "$FULL_MSG" || {
    echo "ERROR: 没有可提交的更改" >&2
    echo "提示: 先修改文件，然后再运行此脚本" >&2
    exit 1
}

# 推送
echo ">>> git push -u origin $BRANCH_NAME ..."
git push -u origin "$BRANCH_NAME" || {
    echo "ERROR: 推送失败，请检查 webhook（Signed-off-by）" >&2
    exit 1
}

# 创建 MR
echo ">>> 创建 MR ..."
MR_URL=$(curl -sf -X POST "$GITCODE_API_BASE/repos/$REPO/pulls" \
    -H "Content-Type: application/json" \
    -H "private-token: $GITCODE_TOKEN" \
    -d "$(jq -n --arg t "$TITLE" --arg h "$BRANCH_NAME" --arg b "$BASE_BRANCH" \
        --arg body "$BODY" '{title: $t, head: $h, base: $b, body: $body}')" \
    | jq -r '.web_url // "创建失败"')

echo ">>> MR 已创建: $MR_URL"
