#!/usr/bin/env bash
# sync-pr.sh - 同步 MR 变更到本地（cherry-pick 或 checkout diff）
# 依赖: git, curl, jq
# 用法:
#   sync-pr.sh yuanrong 533                  # 将 MR #533 的变更应用到当前分支
#   sync-pr.sh yuanrong 533 --branch        # 创建新分支并应用
#   sync-pr.sh yuanrong 533 --files         # 只列出变更文件，不应用
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"
require_gitcode_token

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: 不在 git 仓库内" >&2; exit 1
fi

REPO=$(resolve_repo "${1:-yuanrong}")
IID="$2"
BRANCH_FLAG=""
FILES_ONLY=false

for arg in "${@:3}"; do
    case "$arg" in
        --branch) BRANCH_FLAG=1 ;;
        --files) FILES_ONLY=true ;;
    esac
done

# 获取 MR commits 和 diff
echo ">>> 获取 MR !${IID} 信息 ..."
MR_DATA=$(curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID")
HEAD_SHA=$(echo "$MR_DATA" | jq -r '.head.sha')
BASE_SHA=$(echo "$MR_DATA" | jq -r '.base.sha')
TITLE=$(echo "$MR_DATA" | jq -r '.title')
SOURCE_BRANCH=$(echo "$MR_DATA" | jq -r '.head.ref')
SOURCE_REPO=$(echo "$MR_DATA" | jq -r '.head.repo.full_name // empty')
[ -n "$SOURCE_REPO" ] || SOURCE_REPO="$REPO"

echo "  MR:    !${IID} ${TITLE}"
echo "  分支:  ${SOURCE_BRANCH} (${HEAD_SHA:0:8}) -> $(echo "$MR_DATA" | jq -r '.base.ref')"
echo ""

# 列出变更文件
FILES=$(curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID/files" \
    | jq -r '.[] | .filename')

if $FILES_ONLY; then
    echo "变更文件:"
    echo "$FILES"
    exit 0
fi

echo "变更文件:"
echo "$FILES" | sed 's/^/  /'
echo ""

# 获取 commits 列表
COMMITS=$(curl -sf -H "private-token: $GITCODE_TOKEN" "$GITCODE_API_BASE/repos/$REPO/pulls/$IID/commits" \
    | jq -r '.[].sha')

COMMIT_COUNT=$(echo "$COMMITS" | wc -l)
echo "共 ${COMMIT_COUNT} 个 commit"

# 创建新分支（可选）
if [ -n "$BRANCH_FLAG" ]; then
    BRANCH_NAME="sync/${IID}-${TITLE:0:30}"
    BRANCH_NAME=$(echo "$BRANCH_NAME" | tr ' ' '-' | tr -cd 'a-zA-Z0-9_-')
    echo ">>> 创建分支: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME" || true
fi

# 通过远程 fetch + cherry-pick 应用变更
# 先 fetch 源分支的 commit
SOURCE_REMOTE="mr-${IID}-source"
ASKPASS_FILE=$(mktemp)

cat > "$ASKPASS_FILE" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
    *Username*) printf '%s\n' 'oauth2' ;;
    *Password*) printf '%s\n' "$GITCODE_TOKEN" ;;
    *) exit 1 ;;
esac
ASKPASS
chmod 700 "$ASKPASS_FILE"

cleanup_sync_remote() {
    git remote remove "$SOURCE_REMOTE" 2>/dev/null || true
    rm -f "$ASKPASS_FILE"
}

echo ">>> 添加临时 remote: $SOURCE_REMOTE"
git remote remove "$SOURCE_REMOTE" 2>/dev/null || true
trap cleanup_sync_remote EXIT
git remote add "$SOURCE_REMOTE" "https://gitcode.com/${SOURCE_REPO}.git"
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$ASKPASS_FILE" git fetch "$SOURCE_REMOTE" "$SOURCE_BRANCH" --quiet

# cherry-pick 每个 commit（按顺序）
echo ">>> Cherry-pick commits ..."
for SHA in $COMMITS; do
    echo "  cherry-pick $SHA ..."
    git cherry-pick "$SHA" --allow-empty-message --strategy=recursive 2>&1 || {
        echo "  cherry-pick 冲突，尝试解决..."
        # 列出冲突文件
        CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
        if [ -n "$CONFLICTS" ]; then
            echo "  冲突文件: $CONFLICTS"
            echo "  请手动解决冲突后执行: git cherry-pick --continue"
        fi
        exit 1
    }
done

# 清理临时 remote
echo ">>> 清理临时 remote"
git remote remove "$SOURCE_REMOTE" 2>/dev/null || true
rm -f "$ASKPASS_FILE"
trap - EXIT

echo ""
echo ">>> 完成! MR !${IID} 的变更已应用到当前分支"
