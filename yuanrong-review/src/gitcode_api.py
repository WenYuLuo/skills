"""
GitCode API 封装模块
提供与 GitCode API 的交互功能
"""

import requests
from typing import List, Dict, Optional, Any
from dataclasses import dataclass
from urllib.parse import urljoin


@dataclass
class PullRequest:
    """PR 数据类"""
    number: int
    title: str
    state: str
    user: str
    created_at: str
    updated_at: str
    html_url: str
    body: Optional[str] = None


@dataclass
class PRFile:
    """PR 文件变更数据类"""
    filename: str
    status: str  # added, removed, modified
    additions: int
    deletions: int
    patch: Optional[str] = None
    previous_filename: Optional[str] = None


@dataclass
class PRComment:
    """PR 评论数据类"""
    id: int
    user: str
    body: str
    created_at: str
    path: Optional[str] = None
    position: Optional[int] = None


class GitCodeAPI:
    """GitCode API 客户端"""

    def __init__(self, access_token: str, base_url: str = "https://gitcode.com/api/v5"):
        self.token = access_token
        self.base_url = base_url.rstrip('/')
        self.headers = {
            "private-token": access_token,
            "Accept": "application/json",
            "Content-Type": "application/json"
        }

    @staticmethod
    def _pr_number(data: Dict) -> int:
        return data.get("number") or data.get("iid")

    @staticmethod
    def _pr_user(data: Dict) -> str:
        user = data.get("user") or data.get("author") or {}
        head = data.get("head") or {}
        head_user = head.get("user") or {}
        return user.get("login") or head_user.get("login") or ""

    @staticmethod
    def _pr_url(data: Dict) -> str:
        return data.get("html_url") or data.get("web_url") or data.get("url") or ""

    @staticmethod
    def _pr_created_at(data: Dict) -> str:
        return data.get("created_at") or data.get("created") or ""

    @staticmethod
    def _pr_updated_at(data: Dict) -> str:
        return data.get("updated_at") or data.get("updated") or ""

    @staticmethod
    def _file_patch(data: Dict) -> Optional[str]:
        patch = data.get("patch")
        if isinstance(patch, dict):
            return patch.get("diff")
        return patch

    def _get(self, endpoint: str, params: Optional[Dict] = None) -> Any:
        """发送 GET 请求"""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        response = requests.get(url, headers=self.headers, params=params)
        response.raise_for_status()
        return response.json()

    def _post(self, endpoint: str, data: Dict) -> Any:
        """发送 POST 请求"""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        response = requests.post(url, headers=self.headers, json=data)
        response.raise_for_status()
        return response.json()

    def get_pulls(self, owner: str, repo: str, state: str = "open",
                  per_page: int = 10, page: int = 1) -> List[PullRequest]:
        """获取 PR 列表"""
        endpoint = f"/repos/{owner}/{repo}/pulls"
        params = {"state": state, "per_page": per_page, "page": page}
        data = self._get(endpoint, params)

        return [
            PullRequest(
                number=self._pr_number(pr),
                title=pr["title"],
                state=pr["state"],
                user=self._pr_user(pr),
                created_at=self._pr_created_at(pr),
                updated_at=self._pr_updated_at(pr),
                html_url=self._pr_url(pr),
                body=pr.get("body")
            )
            for pr in data
        ]

    def get_pull(self, owner: str, repo: str, number: int) -> PullRequest:
        """获取单个 PR 详情"""
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}"
        data = self._get(endpoint)

        return PullRequest(
            number=self._pr_number(data),
            title=data["title"],
            state=data["state"],
            user=self._pr_user(data),
            created_at=self._pr_created_at(data),
            updated_at=self._pr_updated_at(data),
            html_url=self._pr_url(data),
            body=data.get("body")
        )

    def get_pull_files(self, owner: str, repo: str, number: int) -> List[PRFile]:
        """获取 PR 文件变更"""
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}/files"
        data = self._get(endpoint)

        return [
            PRFile(
                filename=f["filename"],
                status=f.get("status") or "modified",
                additions=f["additions"],
                deletions=f["deletions"],
                patch=self._file_patch(f),
                previous_filename=f.get("previous_filename")
            )
            for f in data
        ]

    def get_pull_comments(self, owner: str, repo: str, number: int) -> List[PRComment]:
        """获取 PR 评论"""
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}/comments"
        data = self._get(endpoint)

        return [
            PRComment(
                id=c["id"],
                user=(c.get("user") or c.get("author") or {}).get("login", ""),
                body=c["body"],
                created_at=c.get("created_at", ""),
                path=c.get("path"),
                position=c.get("position")
            )
            for c in data
        ]

    def post_comment(self, owner: str, repo: str, number: int,
                     body: str, path: Optional[str] = None,
                     position: Optional[int] = None) -> PRComment:
        """提交评论"""
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}/comments"
        data = {"body": body}

        if path and position is not None:
            data["path"] = path
            data["position"] = position

        response = self._post(endpoint, data)

        return PRComment(
            id=response["id"],
            user=(response.get("user") or response.get("author") or {}).get("login", ""),
            body=response["body"],
            created_at=response.get("created_at", ""),
            path=response.get("path"),
            position=response.get("position")
        )

    def post_review_comment(self, owner: str, repo: str, number: int,
                             body: str, commit_id: str, path: str,
                             position: int) -> Dict:
        """
        提交行级 review 评论

        Args:
            commit_id: 要评论的 commit SHA
            path: 文件路径
            position: diff 中的行位置（从1开始）
        """
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}/comments"
        data = {
            "body": body,
            "commit_id": commit_id,
            "path": path,
            "position": position
        }

        return self._post(endpoint, data)

    def get_pull_commits(self, owner: str, repo: str, number: int) -> List[Dict]:
        """获取 PR 的 commits"""
        endpoint = f"/repos/{owner}/{repo}/pulls/{number}/commits"
        return self._get(endpoint)
