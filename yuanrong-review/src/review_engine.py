"""
审查引擎模块
实现代码审查逻辑和 AI 审查流程
"""

import os
import re
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass
try:
    from .gitcode_api import GitCodeAPI, PRFile
    from .comment_formatter import CommentFormatter, ReviewComment, Severity
except ImportError:
    from gitcode_api import GitCodeAPI, PRFile
    from comment_formatter import CommentFormatter, ReviewComment, Severity


@dataclass
class ReviewContext:
    """审查上下文"""
    owner: str
    repo: str
    pr_number: int
    files: List[PRFile]
    style: str  # strict, normal, gentle


class ReviewEngine:
    """
    代码审查引擎

    实现自动化代码审查流程：
    1. 获取 PR 文件变更
    2. 分析代码问题
    3. 生成评论
    4. 提交行级评论
    """

    STYLE_CONFIGS = {
        "strict": {
            "min_severity": Severity.WARNING,
            "require_tests": True,
            "check_docs": True,
            "max_line_length": 80,
        },
        "normal": {
            "min_severity": Severity.WARNING,
            "require_tests": False,
            "check_docs": False,
            "max_line_length": 100,
        },
        "gentle": {
            "min_severity": Severity.CRITICAL,
            "require_tests": False,
            "check_docs": False,
            "max_line_length": 120,
        },
    }

    def __init__(self, api: GitCodeAPI):
        self.api = api
        self.formatter = CommentFormatter()

    def review_pr(self, owner: str, repo: str, pr_number: int,
                  style: str = "normal") -> List[ReviewComment]:
        """
        审查 PR

        Args:
            owner: 仓库所有者
            repo: 仓库名
            pr_number: PR 编号
            style: 审查风格 (strict, normal, gentle)

        Returns:
            评论列表
        """
        # 获取 PR 文件变更
        files = self.api.get_pull_files(owner, repo, pr_number)

        # 构建审查上下文
        context = ReviewContext(
            owner=owner,
            repo=repo,
            pr_number=pr_number,
            files=files,
            style=style
        )

        comments = []

        # 对每个文件进行审查
        for file in files:
            file_comments = self._review_file(file, context)
            comments.extend(file_comments)

        return comments

    def _review_file(self, file: PRFile, context: ReviewContext) -> List[ReviewComment]:
        """
        审查单个文件

        Args:
            file: 文件变更对象
            context: 审查上下文

        Returns:
            评论列表
        """
        comments = []
        style_config = self.STYLE_CONFIGS.get(context.style, self.STYLE_CONFIGS["normal"])

        # 根据文件类型进行不同的检查
        if file.filename.endswith('.py'):
            comments.extend(self._review_python_file(file, style_config))
        elif file.filename.endswith(('.js', '.ts', '.jsx', '.tsx')):
            comments.extend(self._review_js_file(file, style_config))
        elif file.filename.endswith(('.go',)):
            comments.extend(self._review_go_file(file, style_config))
        elif file.filename.endswith(('.java',)):
            comments.extend(self._review_java_file(file, style_config))
        elif file.filename.endswith(('Makefile', '.mk')):
            comments.extend(self._review_makefile(file, style_config))

        # 通用检查（所有文件类型）
        comments.extend(self._review_general(file, style_config))

        return comments

    def _review_python_file(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """审查 Python 文件"""
        comments = []

        if not file.patch:
            return comments

        # 检查行长度
        max_length = style_config.get("max_line_length", 100)
        for i, line in enumerate(file.patch.split('\n')):
            if line.startswith('+') and len(line) > max_length:
                comments.append(ReviewComment(
                    severity=Severity.SUGGESTION,
                    title=f"行长度超过 {max_length} 字符",
                    description=f"当前行长度为 {len(line)} 字符，建议换行或重构。",
                    file_path=file.filename,
                    line_number=i + 1
                ))

        # 检查缺少类型注解
        if 'def ' in file.patch and '->' not in file.patch:
            comments.append(ReviewComment(
                severity=Severity.SUGGESTION,
                title="建议添加类型注解",
                description="函数缺少返回类型注解，建议添加以提高代码可读性。",
                code_example="def function_name(param: str) -> int:"
            ))

        return comments

    def _review_js_file(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """审查 JavaScript/TypeScript 文件"""
        comments = []

        if not file.patch:
            return comments

        # 检查 console.log
        if 'console.log' in file.patch:
            comments.append(ReviewComment(
                severity=Severity.WARNING,
                title="发现 console.log 语句",
                description="生产代码中不应该包含 console.log，建议移除或使用日志库。"
            ))

        # 检查 var 关键字
        if re.search(r'\bvar\s+', file.patch):
            comments.append(ReviewComment(
                severity=Severity.SUGGESTION,
                title="建议使用 let 或 const 替代 var",
                description="var 有变量提升问题，建议使用 let 或 const。"
            ))

        return comments

    def _review_go_file(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """审查 Go 文件"""
        comments = []

        if not file.patch:
            return comments

        # 检查错误处理
        if '_,' in file.patch and 'err' not in file.patch:
            comments.append(ReviewComment(
                severity=Severity.WARNING,
                title="建议处理错误返回值",
                description="发现忽略返回值的写法，建议检查并处理错误。"
            ))

        return comments

    def _review_java_file(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """审查 Java 文件"""
        comments = []

        if not file.patch:
            return comments

        # 检查 System.out.println
        if 'System.out.println' in file.patch:
            comments.append(ReviewComment(
                severity=Severity.WARNING,
                title="建议使用日志框架",
                description="System.out.println 不适合生产环境，建议使用日志框架如 SLF4J。"
            ))

        return comments

    def _review_makefile(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """审查 Makefile"""
        comments = []

        if not file.patch:
            return comments

        # 检查缺失的依赖声明
        if 'functionsystem' in file.patch and 'datasystem' in file.patch:
            if 'functionsystem:' in file.patch and 'datasystem' not in file.patch.split('functionsystem:')[1].split('\n')[0]:
                comments.append(ReviewComment(
                    severity=Severity.CRITICAL,
                    title="缺少依赖声明导致竞态条件",
                    description="`functionsystem` 目标依赖 `datasystem` 的输出，但 Makefile 中没有声明这个依赖关系。这会导致并行构建时出现竞态条件。",
                    suggestion="添加明确的依赖声明",
                    code_example="functionsystem: datasystem",
                    language="makefile"
                ))

        return comments

    def _review_general(self, file: PRFile, style_config: Dict) -> List[ReviewComment]:
        """通用审查（适用于所有文件类型）"""
        comments = []

        if not file.patch:
            return comments

        # 检查行长度
        max_length = style_config.get("max_line_length", 100)
        for i, line in enumerate(file.patch.split('\n')):
            if line.startswith('+') and len(line) > max_length + 1:  # +1 for the '+'
                comments.append(ReviewComment(
                    severity=Severity.SUGGESTION,
                    title=f"行长度超过 {max_length} 字符",
                    description=f"当前行长度为 {len(line) - 1} 字符，建议换行或重构以提高可读性。",
                    file_path=file.filename,
                    line_number=i + 1
                ))

        # 检查是否有 TODO 但没有对应的 issue 链接
        if 'TODO' in file.patch and 'TODO(' not in file.patch:
            comments.append(ReviewComment(
                severity=Severity.SUGGESTION,
                title="建议为 TODO 添加 issue 链接",
                description="发现 TODO 注释，建议添加对应的 issue 链接以便追踪。",
                code_example="# TODO(#123): 描述要做什么"
            ))

        return comments


def create_pr_summary(total_files: int, total_comments: int,
                      critical: int, warnings: int, suggestions: int) -> str:
    """
    创建 PR 评审摘要

    Args:
        total_files: 审查的文件数
        total_comments: 总评论数
        critical: 严重问题数
        warnings: 警告数
        suggestions: 建议数

    Returns:
        摘要字符串
    """
    lines = [
        "## PR 评审摘要",
        "",
        f"审查了 **{total_files}** 个文件的变更，",
        f"共发现 **{total_comments}** 个问题：",
        "",
        f"| 严重程度 | 数量 |",
        f"|---------|------|",
        f"| 🔴 严重 | {critical} |",
        f"| ⚠️ 警告 | {warnings} |",
        f"| 💡 建议 | {suggestions} |",
        "",
    ]

    if critical > 0:
        lines.append("> ⚠️ **存在严重问题，建议优先处理**")
        lines.append("")

    lines.append("请查看详细评论，如有疑问欢迎讨论。")
    lines.append("")

    return "\n".join(lines)
