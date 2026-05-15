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
  create-pr <repo> <branch> <title> [body]               Create MR (branch must be pushed)
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
    local json=$(jq -n --arg t "$title" --arg h "$branch" --arg b "$body" \
        '{title: $t, head: $h, base: "master", body: $b}')
    gitcode_post "repos/$repo/pulls" "$json" | jq '{iid: .iid, title: .title, url: .web_url}'
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

case "${1,,}" in
    list)    shift; cmd_list "$@" ;;
    show)    shift; cmd_show "$@" ;;
    diff)    shift; cmd_diff "$@" ;;
    commits) shift; cmd_commits "$@" ;;
    create-pr) shift; cmd_create_pr "$@" ;;
    issues)  shift; cmd_issues "$@" ;;
    issue)   shift; cmd_issue "$@" ;;
    create-issue) shift; cmd_create_issue "$@" ;;
    comment-issue) shift; cmd_comment_issue "$@" ;;
    *) usage ;;
esac
