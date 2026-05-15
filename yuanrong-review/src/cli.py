#!/usr/bin/env python3
"""
yuanrong-review CLI 入口
实现 /yuanrong-review 命令的解析和执行
"""

import os
import sys
import argparse
import yaml
from typing import Optional, List, Dict, Any
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from gitcode_api import GitCodeAPI
    from repo_manager import RepoManager, Repository, get_repo_manager
    from review_engine import ReviewEngine, create_pr_summary
    from comment_formatter import Severity, ReviewComment
else:
    from .gitcode_api import GitCodeAPI
    from .repo_manager import RepoManager, Repository, get_repo_manager
    from .review_engine import ReviewEngine, create_pr_summary
    from .comment_formatter import Severity, ReviewComment


# 默认配置
DEFAULT_CONFIG = {
    "api": {
        "base_url": "https://api.gitcode.com/api/v5",
        "access_token": "${YUANRONG_PAT}",
    },
    "defaults": {
        "owner": "openeuler",
        "default_repo": "yuanrong",
        "review_style": "normal",
    }
}


def load_config() -> Dict[str, Any]:
    """加载配置文件"""
    candidates = []
    if os.environ.get("YUANRONG_REVIEW_CONFIG"):
        candidates.append(Path(os.environ["YUANRONG_REVIEW_CONFIG"]))
    candidates.append(Path.home() / ".config" / "yuanrong-review" / "config.yaml")
    candidates.append(Path(__file__).resolve().parent.parent / "config" / "config.yaml.local")

    config_path = next((path for path in candidates if path.exists()), None)
    if config_path:
        with open(config_path, 'r') as f:
            loaded = yaml.safe_load(f) or {}
            config = DEFAULT_CONFIG.copy()
            config.update(loaded)
            return config

    return DEFAULT_CONFIG


def get_access_token(config: Dict) -> str:
    """获取访问令牌"""
    # 优先从环境变量获取
    token = os.environ.get("YUANRONG_PAT")
    if token:
        return token

    # 从配置文件获取
    token = config.get("api", {}).get("access_token", "")
    if token.startswith("${") and token.endswith("}"):
        # 是环境变量引用
        env_var = token[2:-1]
        token = os.environ.get(env_var, "")

    if not token:
        raise ValueError(
            "无法获取访问令牌。请设置 YUANRONG_PAT、YUANRONG_REVIEW_CONFIG 或运行 install.sh。"
        )

    return token


def init_api(config: Optional[Dict] = None) -> GitCodeAPI:
    """初始化 GitCode API 客户端"""
    if config is None:
        config = load_config()

    token = get_access_token(config)
    base_url = config.get("api", {}).get("base_url", "https://api.gitcode.com/api/v5")

    return GitCodeAPI(access_token=token, base_url=base_url)


def cmd_list(args: argparse.Namespace) -> int:
    """list 命令：列出 PR"""
    try:
        api = init_api()
        config = load_config()
        defaults = config.get("defaults", {})

        # 解析仓库
        repo_input = args.repo or defaults.get("default_repo", "yuanrong")
        repo_manager = get_repo_manager()
        repo = repo_manager.resolve_repo(repo_input)

        if not repo:
            print(f"错误：无法识别仓库 '{repo_input}'", file=sys.stderr)
            return 1

        # 获取 PR 列表
        state = args.state or "open"
        limit = args.limit or 10

        pulls = api.get_pulls(
            owner=repo.owner,
            repo=repo.repo,
            state=state,
            per_page=limit
        )

        if not pulls:
            print(f"\n仓库 {repo.full_name} 没有 {state} 状态的 PR\n")
            return 0

        # 打印结果
        print(f"\n{'=' * 80}")
        print(f"  仓库: {repo.full_name}")
        print(f"  状态: {state}")
        print(f"{'=' * 80}\n")

        for pr in pulls:
            print(f"  #{pr.number} {pr.title}")
            print(f"      作者: {pr.user} | 创建于: {pr.created_at}")
            print(f"      链接: {pr.html_url}")
            print()

        print(f"共 {len(pulls)} 个 PR\n")
        return 0

    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1


def cmd_show(args: argparse.Namespace) -> int:
    """show 命令：显示 PR 详情"""
    try:
        api = init_api()

        # 解析 repo/pr-number 格式
        if '/' not in args.pr_spec:
            print("错误：请使用格式 'repo/pr-number'，例如 'yuanrong/448'", file=sys.stderr)
            return 1

        repo_input, pr_number_str = args.pr_spec.rsplit('/', 1)
        try:
            pr_number = int(pr_number_str)
        except ValueError:
            print(f"错误：无效的 PR 编号 '{pr_number_str}'", file=sys.stderr)
            return 1

        # 解析仓库
        repo_manager = get_repo_manager()
        repo = repo_manager.resolve_repo(repo_input)

        if not repo:
            print(f"错误：无法识别仓库 '{repo_input}'", file=sys.stderr)
            return 1

        # 获取 PR 详情
        pr = api.get_pull(repo.owner, repo.repo, pr_number)

        # 获取文件变更
        files = api.get_pull_files(repo.owner, repo.repo, pr_number)

        # 打印详情
        print(f"\n{'=' * 80}")
        print(f"  PR #{pr.number}: {pr.title}")
        print(f"{'=' * 80}\n")

        print(f"  状态: {pr.state}")
        print(f"  作者: {pr.user}")
        print(f"  创建: {pr.created_at}")
        print(f"  更新: {pr.updated_at}")
        print(f"  链接: {pr.html_url}")
        print()

        if pr.body:
            print("  描述:")
            print(f"  {pr.body[:500]}{'...' if len(pr.body) > 500 else ''}")
            print()

        print(f"  文件变更 ({len(files)} 个文件):")
        total_additions = 0
        total_deletions = 0

        for f in files:
            print(f"    {f.status:10} +{f.additions:4} -{f.deletions:4} {f.filename}")
            total_additions += f.additions
            total_deletions += f.deletions

        print(f"\n  总计: +{total_additions} -{total_deletions}")
        print()

        return 0

    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1


def cmd_review(args: argparse.Namespace) -> int:
    """review 命令：审查 PR 并提交评论"""
    try:
        api = init_api()

        # 解析 repo/pr-number 格式
        if '/' not in args.pr_spec:
            print("错误：请使用格式 'repo/pr-number'，例如 'yuanrong/448'", file=sys.stderr)
            return 1

        repo_input, pr_number_str = args.pr_spec.rsplit('/', 1)
        try:
            pr_number = int(pr_number_str)
        except ValueError:
            print(f"错误：无效的 PR 编号 '{pr_number_str}'", file=sys.stderr)
            return 1

        # 解析仓库
        repo_manager = get_repo_manager()
        repo = repo_manager.resolve_repo(repo_input)

        if not repo:
            print(f"错误：无法识别仓库 '{repo_input}'", file=sys.stderr)
            return 1

        style = args.style or "normal"
        dry_run = args.dry_run if hasattr(args, 'dry_run') else False

        print(f"\n正在审查 {repo.full_name} 的 PR #{pr_number}...")
        print(f"审查风格: {style}")
        if dry_run:
            print("(试运行模式，不会实际提交评论)")
        print()

        # 创建审查引擎
        engine = ReviewEngine(api)

        # 执行审查
        comments = engine.review_pr(
            owner=repo.owner,
            repo=repo.repo,
            pr_number=pr_number,
            style=style
        )

        if not comments:
            print("✅ 未发现明显问题，代码看起来不错！")
            return 0

        # 打印摘要
        summary = create_pr_summary(comments)
        print(summary)

        # 如果不是试运行，提交评论
        if not dry_run:
            print("正在提交评论到 GitCode...")

            # 获取 PR 的 commits 以获取最新的 commit_id
            commits = api.get_pull_commits(repo.owner, repo.repo, pr_number)
            if not commits:
                print("错误：无法获取 PR 的 commits", file=sys.stderr)
                return 1

            latest_commit = commits[-1]["sha"]

            submitted = 0
            for comment in comments:
                if comment.file_path and comment.line_number:
                    try:
                        api.post_review_comment(
                            owner=repo.owner,
                            repo=repo.repo,
                            number=pr_number,
                            body=CommentFormatter.format_comment(comment),
                            commit_id=latest_commit,
                            path=comment.file_path,
                            position=comment.line_number
                        )
                        submitted += 1
                    except Exception as e:
                        print(f"  提交评论失败 ({comment.file_path}:{comment.line_number}): {e}")

            # 提交总体评论
            try:
                api.post_comment(
                    owner=repo.owner,
                    repo=repo.repo,
                    number=pr_number,
                    body=summary
                )
                print(f"✅ 成功提交 {submitted} 条行级评论和 1 条总体评论")
            except Exception as e:
                print(f"⚠️ 提交总体评论失败: {e}")
                print(f"✅ 成功提交 {submitted} 条行级评论")
        else:
            print("\n试运行模式，以下评论不会被提交：\n")
            for i, comment in enumerate(comments, 1):
                print(f"--- 评论 {i} ---")
                print(CommentFormatter.format_comment(comment))
                print()

        return 0

    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


def cmd_repos(args: argparse.Namespace) -> int:
    """repos 命令：管理仓库映射"""
    try:
        repo_manager = get_repo_manager()

        action = args.action or "list"

        if action == "list":
            print("\n已配置的仓库映射:\n")
            print(f"{'名称':<15} {'完整名称':<35} {'别名'}")
            print("-" * 80)

            for repo in repo_manager.list_repositories():
                aliases_str = ", ".join(repo.aliases) if repo.aliases else "-"
                print(f"{repo.name:<15} {repo.full_name:<35} {aliases_str}")

            print()
            return 0

        elif action == "add":
            if not args.name or not args.url:
                print("错误：添加仓库需要提供名称和 URL", file=sys.stderr)
                print("用法: repos add <name> <owner/repo>", file=sys.stderr)
                return 1

            # 解析 full_name
            if '/' not in args.url:
                print(f"错误：仓库 URL 格式错误，应为 'owner/repo'", file=sys.stderr)
                return 1

            repo = Repository(
                name=args.name,
                full_name=args.url,
                aliases=[]
            )

            repo_manager.add_repository(repo)
            print(f"✅ 已添加仓库: {args.name} -> {args.url}")
            return 0

        elif action == "remove":
            if not args.name:
                print("错误：移除仓库需要提供名称", file=sys.stderr)
                print("用法: repos remove <name>", file=sys.stderr)
                return 1

            if repo_manager.remove_repository(args.name):
                print(f"✅ 已移除仓库: {args.name}")
                return 0
            else:
                print(f"❌ 未找到仓库: {args.name}")
                return 1

        else:
            print(f"错误：未知的操作 '{action}'", file=sys.stderr)
            return 1

    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1


def main():
    """主入口函数"""
    parser = argparse.ArgumentParser(
        prog="yuanrong-review",
        description="openYuanrong PR Review Tool"
    )

    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # list 命令
    list_parser = subparsers.add_parser("list", help="列出 PR")
    list_parser.add_argument("repo", nargs="?", help="仓库名称（可选）")
    list_parser.add_argument("--state", choices=["open", "closed", "all"],
                             help="PR 状态筛选")
    list_parser.add_argument("--limit", type=int, help="返回的最大数量")

    # show 命令
    show_parser = subparsers.add_parser("show", help="显示 PR 详情")
    show_parser.add_argument("pr_spec", help="PR 标识，格式：repo/pr-number")

    # review 命令
    review_parser = subparsers.add_parser("review", help="审查 PR")
    review_parser.add_argument("pr_spec", help="PR 标识，格式：repo/pr-number")
    review_parser.add_argument("--style", choices=["strict", "normal", "gentle"],
                               help="审查风格")
    review_parser.add_argument("--dry-run", action="store_true",
                               help="试运行，不提交评论")

    # repos 命令
    repos_parser = subparsers.add_parser("repos", help="管理仓库映射")
    repos_parser.add_argument("action", nargs="?", choices=["list", "add", "remove"],
                              help="操作类型")
    repos_parser.add_argument("name", nargs="?", help="仓库名称")
    repos_parser.add_argument("url", nargs="?", help="仓库完整名 (owner/repo)")

    # 解析参数
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    # 执行对应命令
    commands = {
        "list": cmd_list,
        "show": cmd_show,
        "review": cmd_review,
        "repos": cmd_repos,
    }

    handler = commands.get(args.command)
    if handler:
        return handler(args)

    return 1


if __name__ == "__main__":
    sys.exit(main())
