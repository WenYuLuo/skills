# openYuanrong PR Review Skill

用于审查 openYuanrong 项目及其子仓库 Pull Request 的本地 Skill/CLI。

## 功能特性

- **管理 6 个子仓库**：支持通过短名称操作所有子仓库
- **GitCode API 配置**：通过 `YUANRONG_PAT`、`~/.config/yuanrong-review/config.yaml` 或 `config/config.yaml.local`
- **行级 Review 格式**：默认提交行级评论
- **安全默认值**：先用 `--dry-run` 生成草稿，只有明确要求时才提交外部评论

## 支持的仓库

| 序号 | 短名称 | 完整仓库名 | 别名 |
|------|--------|-----------|------|
| 1 | yuanrong | openeuler/yuanrong | main, core |
| 2 | ray-adapter | openeuler/ray-adapter | ray |
| 3 | frontend | openeuler/yuanrong-frontend | fe, ui |
| 4 | functionsystem | openeuler/yuanrong-functionsystem | fs, func |
| 5 | datasystem | openeuler/yuanrong-datasystem | ds, data |
| 6 | runtime | openeuler/yuanrong-runtime | rt |

## 命令用法

### 列出 PR

```bash
/yuanrong-review list [repo-name] [--state open|closed|all] [--limit N]
```

示例：
```bash
/yuanrong-review list                    # 列出默认仓库的 PR
/yuanrong-review list frontend --limit 5 # 列出 frontend 仓库的 5 个 PR
/yuanrong-review list fs --state all     # 列出 functionsystem 所有 PR
```

### 显示 PR 详情

```bash
/yuanrong-review show <repo-name>/<pr-number>
```

示例：
```bash
/yuanrong-review show yuanrong/448  # 显示 yuanrong 仓库 PR #448
/yuanrong-review show fs/23         # 显示 functionsystem 仓库 PR #23
```

### 审查 PR

```bash
/yuanrong-review review <repo-name>/<pr-number> [--style strict|normal|gentle] [--dry-run]
```

示例：
```bash
/yuanrong-review review yuanrong/448           # 以 normal 风格审查
/yuanrong-review review ds/15 --style strict   # 以 strict 风格审查
/yuanrong-review review runtime/10 --dry-run   # 试运行，不提交评论
```

审查风格：
- `strict`: 严格模式，检查所有可能的问题，包括代码风格
- `normal`: 标准模式，检查常见问题和潜在 bug
- `gentle`: 宽松模式，仅检查严重问题

### 管理仓库映射

```bash
/yuanrong-review repos [list|add|remove] [name] [url]
```

示例：
```bash
/yuanrong-review repos list                       # 列出所有仓库
/yuanrong-review repos add myrepo owner/repo    # 添加仓库
/yuanrong-review repos remove myrepo            # 移除仓库
```

## 配置

### 环境变量

- `YUANRONG_PAT`: GitCode Personal Access Token（必需）

### 配置文件

运行 `./install.sh` 会生成两个配置文件：

- `config/config.yaml.local`：本地迁移副本，便于私下拷贝到其它机器
- `~/.config/yuanrong-review/config.yaml`：默认运行时配置

GitHub 只保留 `config/config.yaml.template`，不要提交真实 token。

```yaml
api:
  base_url: "https://api.gitcode.com/api/v5"
  access_token: "${YUANRONG_PAT}"

defaults:
  owner: "openeuler"
  default_repo: "yuanrong"
  review_style: "normal"
```

## 评论格式

评论草稿采用统一格式：

```
🔴 **严重**: 问题标题

问题详细描述...

**建议修改**:
```python
# 代码示例
fixed_code_here()
```
```

严重程度标记：
- 🔴 **严重**: 阻塞性问题，必须修复
- ⚠️ **警告**: 可能影响功能或维护性的问题
- 💡 **建议**: 优化建议，非阻塞性

## 安装

从 skill 目录初始化配置并安装依赖：

```bash
./install.sh
```

## 开发

运行测试：

```bash
cd yuanrong-review
python -m pytest tests/
```

## 许可证

MIT License
