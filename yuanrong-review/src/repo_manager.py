"""
仓库映射管理模块
管理 6 个子仓库的映射关系
"""

from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass


@dataclass
class Repository:
    """仓库数据类"""
    name: str  # 主名称
    full_name: str  # 完整名称 owner/repo
    aliases: List[str]  # 别名列表

    @property
    def owner(self) -> str:
        return self.full_name.split('/')[0]

    @property
    def repo(self) -> str:
        return self.full_name.split('/')[1]


class RepoManager:
    """
    管理 6 个子仓库的映射关系

    支持通过短名称或别名解析为完整仓库名
    """

    DEFAULT_REPOS = {
        "yuanrong": Repository(
            name="yuanrong",
            full_name="openeuler/yuanrong",
            aliases=["main", "core"]
        ),
        "ray-adapter": Repository(
            name="ray-adapter",
            full_name="openeuler/ray-adapter",
            aliases=["ray"]
        ),
        "frontend": Repository(
            name="frontend",
            full_name="openeuler/yuanrong-frontend",
            aliases=["fe", "ui"]
        ),
        "functionsystem": Repository(
            name="functionsystem",
            full_name="openeuler/yuanrong-functionsystem",
            aliases=["fs", "func"]
        ),
        "datasystem": Repository(
            name="datasystem",
            full_name="openeuler/yuanrong-datasystem",
            aliases=["ds", "data"]
        ),
        "runtime": Repository(
            name="runtime",
            full_name="openeuler/yuanrong-runtime",
            aliases=["rt"]
        ),
    }

    def __init__(self, custom_repos: Optional[Dict[str, Repository]] = None):
        """
        初始化仓库管理器

        Args:
            custom_repos: 可选的自定义仓库配置
        """
        self._repos = {}
        self._alias_map = {}

        # 加载默认仓库
        for repo in (custom_repos or self.DEFAULT_REPOS).values():
            self.add_repository(repo)

    def add_repository(self, repo: Repository) -> None:
        """
        添加仓库

        Args:
            repo: 仓库对象
        """
        self._repos[repo.name] = repo

        # 建立别名映射
        self._alias_map[repo.name] = repo.name
        for alias in repo.aliases:
            self._alias_map[alias] = repo.name

    def remove_repository(self, name: str) -> bool:
        """
        移除仓库

        Args:
            name: 仓库名称或别名

        Returns:
            是否成功移除
        """
        resolved = self._alias_map.get(name)
        if not resolved:
            return False

        repo = self._repos.get(resolved)
        if not repo:
            return False

        # 清理映射
        del self._repos[resolved]
        del self._alias_map[resolved]
        for alias in repo.aliases:
            if self._alias_map.get(alias) == resolved:
                del self._alias_map[alias]

        return True

    def resolve_repo(self, name_or_alias: str) -> Optional[Repository]:
        """
        将短名称或别名解析为仓库对象

        Args:
            name_or_alias: 仓库名称或别名

        Returns:
            仓库对象，如果未找到则返回 None
        """
        # 如果已经是完整名称格式 owner/repo
        if '/' in name_or_alias:
            parts = name_or_alias.split('/')
            if len(parts) == 2:
                return Repository(
                    name=parts[1],
                    full_name=name_or_alias,
                    aliases=[]
                )

        # 查找别名映射
        resolved = self._alias_map.get(name_or_alias)
        if resolved:
            return self._repos.get(resolved)

        return None

    def list_repositories(self) -> List[Repository]:
        """
        获取所有仓库列表

        Returns:
            仓库对象列表
        """
        return list(self._repos.values())

    def get_repository(self, name: str) -> Optional[Repository]:
        """
        获取指定仓库

        Args:
            name: 仓库名称

        Returns:
            仓库对象，如果不存在则返回 None
        """
        return self._repos.get(name)

    def is_valid_alias(self, name: str) -> bool:
        """
        检查名称是否是有效的仓库名称或别名

        Args:
            name: 待检查的名称

        Returns:
            是否是有效的名称
        """
        if '/' in name:
            return True
        return name in self._alias_map


# 全局仓库管理器实例
_repo_manager = None


def get_repo_manager() -> RepoManager:
    """获取全局仓库管理器实例"""
    global _repo_manager
    if _repo_manager is None:
        _repo_manager = RepoManager()
    return _repo_manager
