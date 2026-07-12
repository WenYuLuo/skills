#!/usr/bin/env bash
# gitcode.sh - 轻量 GitCode API 封装
# 依赖: curl, jq
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=yr-dev-common.sh
source "$SCRIPT_DIR/yr-dev-common.sh"

usage() {
    cat <<EOF
Usage: gitcode.sh <command> [args]

Commands:
  list <repo> [--state open|closed|merged] [--limit N]   List MRs
  show <repo> <iid>                                      Show MR details
  diff <repo> <iid>                                      Show MR file changes
  commits <repo> <iid>                                   Show MR commits
  create-pr <repo> <branch> <title> [body] [--base BRANCH] [--head OWNER:BRANCH] [--assignees USERS]
                                                         Create MR (branch must be pushed)
  check-pr <repo> <iid> [--base REF]                     Validate commits/title/body and comment /check-pr
  issues <repo> [--state open|closed|all] [--limit N]    List issues
  issue <repo> <number>                                  Show issue
  create-issue <repo> <title> [body]                     Create issue
  comment-issue <repo> <number> <body>                   Add issue comment

Repos: yuanrong, datasystem(ds), functionsystem(fs), frontend(fe), runtime(rt), ray
       or full path like openeuler/yuanrong

Config: run scripts/init-config.sh, export GITCODE_TOKEN, or set YR_DEV_CONFIG.
EOF
    exit 1
}

cmd_list() {
    local repo=$(resolve_repo "$1"); shift
    local state="open" limit=10
    while [ $# -gt 0 ]; do
        case "$1" in
            --state) state="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gitcode_get "repos/$repo/pulls?state=$state&per_page=$limit" \
        '.[] | "!\(.iid) [\(.state)] \(.title)  @\(.head.user.login)  \(.head.ref)->\(.base.ref)"'
}

cmd_show() {
    local repo=$(resolve_repo "$1")
    local iid="$2"
    gitcode_get "repos/$repo/pulls/$iid" \
        '{iid: .iid, title: .title, state: .state, author: .head.user.login, branch: (.head.ref + " -> " + .base.ref), additions: .additions, deletions: .deletions, url: .web_url, body: .body}'
}

cmd_diff() {
    local repo=$(resolve_repo "$1")
    local iid="$2"
    gitcode_get "repos/$repo/pulls/$iid/files" \
        '.[] | "+\(.additions) -\(.deletions) \(.status) \(.filename)"'
}

cmd_commits() {
    local repo=$(resolve_repo "$1")
    local iid="$2"
    gitcode_get "repos/$repo/pulls/$iid/commits" \
        '.[] | "\(.sha[0:8]) \(.commit.message | split("\n")[0])"'
}

cmd_create_pr() {
    local repo=$(resolve_repo "$1")
    local branch="$2"
    local title="$3"
    local body="${4:-}"
    shift 4
    local base="master" head_override="" assignees=""
    validate_yr_subject "$title" "MR title"
    validate_yr_mr_body "$repo" "$title" "$body"
    while [ $# -gt 0 ]; do
        case "$1" in
            --base) base="$2"; shift 2 ;;
            --head) head_override="$2"; shift 2 ;;
            --assignees) assignees="$2"; shift 2 ;;
            *) echo "ERROR: unknown option $1" >&2; exit 1 ;;
        esac
    done
    local base_ref="upstream/$base"
    git rev-parse --verify "$base_ref" >/dev/null 2>&1 || base_ref="origin/$base"
    git rev-parse --verify "$base_ref" >/dev/null 2>&1 || base_ref="$base"
    validate_yr_commit_range "$base_ref"
    local head="$branch"
    if [[ -n "$head_override" ]]; then
        head="$head_override"
    else
        local origin_repo
        origin_repo=$(current_origin_repo_path || true)
        if [[ -n "$origin_repo" && "$origin_repo" != "$repo" ]]; then
            head="${origin_repo%%/*}:$branch"
        fi
    fi
    local json
    json=$(jq -n --arg t "$title" --arg h "$head" --arg base "$base" --arg b "$body" \
        '{title: $t, head: $h, base: $base, body: $b}')
    if [[ -n "$assignees" ]]; then
        json=$(printf '%s\n' "$json" | jq --arg assignees "$assignees" '. + {assignees: $assignees}')
    fi
    local response iid
    response=$(gitcode_post "repos/$repo/pulls" "$json")
    iid=$(printf '%s\n' "$response" | jq -r '.iid // .number // empty')
    if [[ -n "$iid" ]]; then
        gitcode_post "repos/$repo/pulls/$iid/comments" '{"body":"/check-pr"}' >/dev/null
    fi
    printf '%s\n' "$response" | jq '{iid: (.iid // .number), title: .title, url: (.web_url // .html_url)}'
}

cmd_check_pr() {
    local repo="$1" iid="$2"; shift 2
    "$SCRIPT_DIR/preflight-pr.sh" "$repo" --iid "$iid" --comment-check-pr "$@"
}

cmd_issues() {
    local repo; repo=$(resolve_repo "$1"); shift
    local state="open" limit=10
    while [ $# -gt 0 ]; do
        case "$1" in
            --state) state="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gitcode_get "repos/$repo/issues?state=$state&per_page=$limit" \
        '.[] | "#\(.number) [\(.state)] \(.title)  \(.html_url // .url // "")"'
}

cmd_issue() {
    local repo; repo=$(resolve_repo "$1")
    local number="$2"
    gitcode_get "repos/$repo/issues/$number" \
        '{number, title, state, url: (.html_url // .url), body}'
}

cmd_create_issue() {
    local repo; repo=$(resolve_repo "$1")
    local title="$2"
    local body="${3:-}"
    local json; json=$(jq -n --arg title "$title" --arg body "$body" '{title:$title, body:$body}')
    gitcode_post "repos/$repo/issues" "$json" | jq '{number, title, url: (.html_url // .url)}'
}

cmd_comment_issue() {
    local repo; repo=$(resolve_repo "$1")
    local number="$2"
    local body="$3"
    local json; json=$(jq -n --arg body "$body" '{body:$body}')
    gitcode_post "repos/$repo/issues/$number/comments" "$json" | jq '{id, body, url: (.html_url // .url)}'
}

[ $# -lt 1 ] && usage

cmd=$(yr_lower "$1")
case "$cmd" in
    list)    shift; cmd_list "$@" ;;
    show)    shift; cmd_show "$@" ;;
    diff)    shift; cmd_diff "$@" ;;
    commits) shift; cmd_commits "$@" ;;
    create-pr) shift; cmd_create_pr "$@" ;;
    check-pr) shift; cmd_check_pr "$@" ;;
    issues)  shift; cmd_issues "$@" ;;
    issue)   shift; cmd_issue "$@" ;;
    create-issue) shift; cmd_create_issue "$@" ;;
    comment-issue) shift; cmd_comment_issue "$@" ;;
    *) usage ;;
esac
