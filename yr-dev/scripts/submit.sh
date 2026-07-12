#!/usr/bin/env bash
# submit.sh - 提交代码并推送（自动处理 Signed-off-by 和分支创建）
# 依赖: git, jq
# 用法:
#   submit.sh "fix(docs): 修复xxx"              # 在当前分支提交
#   submit.sh "fix(docs): 修复xxx" new-branch   # 创建新分支并提交
#   submit.sh --amend "fix(docs): 修正xxx"       # 修正上一次提交
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"

# 检查是否在 git 仓库内
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: 不在 git 仓库内" >&2; exit 1
fi

# 检查是否有未暂存的更改
has_changes() {
    ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null
}

# 确保远程是最新的
echo ">>> git fetch ..."
git fetch --quiet 2>/dev/null || true

# 处理分支
if [ $# -ge 2 ] && [ "${1:0:1}" != "-" ]; then
    # 第二个参数是新分支名
    BRANCH="$2"
    if git show-ref --verify refs/heads/"$BRANCH" >/dev/null 2>&1; then
        echo ">>> 切换到已有分支: $BRANCH"
        git checkout "$BRANCH"
    else
        echo ">>> 创建并切换到新分支: $BRANCH"
        git checkout -b "$BRANCH"
    fi
    MSG="$1"
elif [ "$1" = "--amend" ]; then
    MSG="${2:-}"
    # 用上一个 commit message 但允许覆盖
    if [ -z "$MSG" ]; then
        MSG=$(git log -1 --format="%s%n%n%b" | sed '/^$/d')
    fi
    echo ">>> 修正上一次提交 (amend)"
else
    MSG="$1"
fi

validate_yr_subject "$(printf '%s\n' "$MSG" | head -n 1)" "commit subject"

# 自动追加 Signed-off-by（如果还没有）
FULL_MSG="$MSG"
if ! echo "$FULL_MSG" | grep -qF "Signed-off-by:"; then
    SIGNOFF=$(commit_signoff)
    FULL_MSG="$MSG

$SIGNOFF"
fi
validate_yr_commit_message "$FULL_MSG" "new commit"

# 执行提交
if [ "$1" = "--amend" ]; then
    git commit --amend -m "$FULL_MSG"
else
    if has_changes; then
        git add -A
    fi
    git commit -m "$FULL_MSG" || {
        echo "ERROR: 提交失败，可能没有可提交的更改" >&2; exit 1
    }
fi

# 推送
BRANCH_NAME=$(git branch --show-current)
REMOTE=$(git remote get-url origin 2>/dev/null | sed 's|.*gitcode.com/||' | sed 's|\.git||')
echo ">>> 推送 $BRANCH_NAME 到 origin ..."
if git push -u origin "$BRANCH_NAME" 2>&1; then
    echo ">>> 推送成功"
else
    echo ">>> 推送失败，请检查 webhook 校验（Signed-off-by 格式）"
    exit 1
fi
