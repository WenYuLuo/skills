"""
评论格式化模块
用于格式化评论内容，去除 AI 痕迹，使其看起来像用户自己的评审意见
"""

from typing import Optional, Dict, List
from dataclasses import dataclass
from enum import Enum


class Severity(Enum):
    """严重程度枚举"""
    CRITICAL = "critical"  # 阻塞性问题
    WARNING = "warning"  # 警告
    SUGGESTION = "suggestion"  # 建议


@dataclass
class ReviewComment:
    """评审评论数据类"""
    severity: Severity
    title: str
    description: Optional[str] = None
    suggestion: Optional[str] = None
    code_example: Optional[str] = None
    language: str = "python"
    file_path: Optional[str] = None
    line_number: Optional[int] = None


class CommentFormatter:
    """
    评论格式化器

    将 AI 生成的评论转换为自然的、看起来像人工撰写的评审意见
    去除 AI 痕迹，显示为用户自己的评审意见
    """

    SEVERITY_MARKERS = {
        Severity.CRITICAL: "🔴",
        Severity.WARNING: "⚠️",
        Severity.SUGGESTION: "💡",
    }

    SEVERITY_LABELS = {
        Severity.CRITICAL: "严重",
        Severity.WARNING: "警告",
        Severity.SUGGESTION: "建议",
    }

    # 自然语言变体，用于去除 AI 痕迹
    INTRO_VARIATIONS = [
        "",
        "发现一个问题：",
        "这里需要关注：",
        "注意到：",
        "建议调整：",
    ]

    CLOSING_VARIATIONS = [
        "",
        "请确认修改。",
        "如有疑问可以讨论。",
        "可以参考建议修改。",
    ]

    @classmethod
    def format_comment(cls, comment: ReviewComment, natural_style: bool = True) -> str:
        """
        格式化评论内容

        Args:
            comment: 评论数据对象
            natural_style: 是否使用自然语言风格（去除 AI 痕迹）

        Returns:
            格式化后的评论字符串
        """
        lines = []

        # 严重程度标记
        marker = cls.SEVERITY_MARKERS.get(comment.severity, "💡")
        label = cls.SEVERITY_LABELS.get(comment.severity, "建议")

        # 标题行
        lines.append(f"{marker} **{label}**: {comment.title}")
        lines.append("")

        # 描述
        if comment.description:
            if natural_style:
                lines.append(cls._naturalize_text(comment.description))
            else:
                lines.append(comment.description)
            lines.append("")

        # 建议修改
        if comment.suggestion or comment.code_example:
            lines.append(f"**建议修改**:")
            if comment.suggestion:
                lines.append("")
                lines.append(comment.suggestion)

            if comment.code_example:
                lines.append("")
                lines.append(f"```{comment.language}")
                lines.append(comment.code_example)
                lines.append("```")

            lines.append("")

        return "\n".join(lines)

    @classmethod
    def format_simple_comment(cls, severity: Severity, title: str,
                              description: Optional[str] = None) -> str:
        """
        快速格式化简单评论

        Args:
            severity: 严重程度
            title: 标题
            description: 描述

        Returns:
            格式化后的评论字符串
        """
        comment = ReviewComment(
            severity=severity,
            title=title,
            description=description
        )
        return cls.format_comment(comment)

    @classmethod
    def _naturalize_text(cls, text: str) -> str:
        """
        将文本转换为更自然的表达方式
        去除 AI 痕迹
        """
        # 移除常见的 AI 表达
        ai_patterns = [
            "作为AI",
            "作为人工智能",
            "我建议",
            "我建议您",
            "根据我的分析",
            "从我的角度来看",
        ]

        result = text
        for pattern in ai_patterns:
            result = result.replace(pattern, "")

        # 清理多余的空格
        result = " ".join(result.split())

        return result.strip()

    @classmethod
    def create_line_comment(cls, file_path: str, line_number: int,
                            severity: Severity, title: str,
                            description: Optional[str] = None,
                            suggestion: Optional[str] = None,
                            code_example: Optional[str] = None,
                            language: str = "python") -> ReviewComment:
        """
        创建行级评论

        Args:
            file_path: 文件路径
            line_number: 行号
            severity: 严重程度
            title: 标题
            description: 描述
            suggestion: 建议
            code_example: 代码示例
            language: 代码语言

        Returns:
            ReviewComment 对象
        """
        return ReviewComment(
            severity=severity,
            title=title,
            description=description,
            suggestion=suggestion,
            code_example=code_example,
            language=language,
            file_path=file_path,
            line_number=line_number
        )


def format_review_summary(comments: List[ReviewComment]) -> str:
    """
    格式化评审摘要

    Args:
        comments: 评论列表

    Returns:
        摘要字符串
    """
    total = len(comments)
    critical = sum(1 for c in comments if c.severity == Severity.CRITICAL)
    warnings = sum(1 for c in comments if c.severity == Severity.WARNING)
    suggestions = sum(1 for c in comments if c.severity == Severity.SUGGESTION)

    lines = [
        "## 评审摘要",
        "",
        f"共发现 **{total}** 个问题：",
        f"- 🔴 严重问题: {critical}",
        f"- ⚠️ 警告: {warnings}",
        f"- 💡 建议: {suggestions}",
        ""
    ]

    return "\n".join(lines)
