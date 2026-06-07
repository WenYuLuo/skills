---
name: yr-dev
description: Use when working on openYuanrong repositories and needing project-specific development, build, and GitCode workflow reference
---

# yr-dev: openYuanrong 开发辅助

协助 openYuanrong 项目开发的参考信息与工具。

## GitCode 平台

- **API Base**: `https://gitcode.com/api/v5`
- **认证**: `private-token` header
- **Token**: 通过 `GITCODE_TOKEN` 或 `config/gitcode.env.local` / `~/.config/yr-dev/gitcode.env` 配置，禁止写进 skill 或 commit。

### 配置

```bash
cd yr-dev
scripts/init-config.sh
```

`init-config.sh` 会生成两个文件：

- `config/gitcode.env.local` — 本地迁移副本，便于私下拷贝到其它机器
- `~/.config/yr-dev/gitcode.env` — 默认运行时配置

GitHub 只保留 `config/gitcode.env.example`，真实配置文件必须被 `.gitignore` 排除。

### 仓库

| 短名 | 仓库 | 说明 |
|------|------|------|
| yuanrong | openeuler/yuanrong | 运行时 + dashboard |
| datasystem | openeuler/yuanrong-datasystem | 数据系统 |
| functionsystem | openeuler/yuanrong-functionsystem | 函数系统 |
| frontend | openeuler/yuanrong-frontend | API 网关 |

### 提交规范

```
type(scope): 简短描述

详细说明（可选）

Signed-off-by: Name <email>
```

- **type**: `fix` `feat` `docs` `style` `refactor` `test` `chore` `perf` `ci` `build` `revert`
- **scope**: `(xxx)` 或 `[xxx]`，可选，如 `(python sdk)` `[scheduler]`
- **Signed-off-by**: 必填，格式 `<name> <email>`
- hook 正则: `^(fix|feat|docs|...)(\([^)]+\)|\[[^\]]+\])?:.+[\s\S]*Signed-off-by:.+<.+@.+>`

> ⚠️ **CLA 硬性规则（务必遵守，否则 CLA 检查必挂）**：commit message 里**只能有一行 `Signed-off-by:`，且必须是 CLA 已签署的 `<name> <email>`**（本仓库用 `Signed-off-by: luozhancheng <luozhancheng@huawei.com>`）。
> - **绝对不要**加 `Co-authored-by:`（如 `Co-authored-by: Claude ...` / `Copilot ...`）或任何第二个署名 —— 这些会引入非 CLA 签署人，导致 CLA 协议检查不通过。
> - AI（Claude Code / Copilot 等）默认会自动追加 `Co-Authored-By:`，**在本仓库必须关掉/删掉**。
> - 提交命令（author 用 gmail、signoff 用 huawei 是历史验证可过的组合）：
>   ```bash
>   git -c user.name=luozhancheng -c user.email=luozhancheng@gmail.com \
>     commit --author="luozhancheng <luozhancheng@gmail.com>" -m "feat(x): ...
>
>   Signed-off-by: luozhancheng <luozhancheng@huawei.com>"
>   ```
> - 若已误推带 `Co-authored-by` 的提交：`git filter-branch -f --msg-filter 'sed "/^Co-authored-by:/d" | cat -s' <base>..HEAD` 重写后 `git push --force-with-lease`。
> - 用本 skill 的 `submit.sh` / `create-pr.sh` 时，它们的 `commit_signoff` 默认取 `git config user.email`（常是 gmail，CLA 会挂）。**务必设** CLA 邮箱：
>   ```bash
>   export YR_SIGNOFF_NAME=luozhancheng
>   export YR_SIGNOFF_EMAIL=luozhancheng@huawei.com   # 或写入 ~/.config/yr-dev/gitcode.env
>   ```
>   （或直接 `export YR_SIGNOFF="Signed-off-by: luozhancheng <luozhancheng@huawei.com>"`）

### MR 创建

```bash
API="https://gitcode.com/api/v5/repos/openeuler/yuanrong/pulls"
curl -s -X POST "$API" \
  -H "Content-Type: application/json" \
  -H "private-token: TOKEN" \
  -d '{"title":"...","head":"branch-name","base":"master","body":"..."}'
```

创建后 webhook 校验会检查 Signed-off-by，不通过则 push 或 upstream PR 创建会被拒绝。

### Fork → upstream PR 规则

- GitCode API 创建 fork → upstream PR 时，`head` 需要传 `owner:branch`，例如 `luozhancheng:fix/tenant-ref-ds-context`
- 如果当前仓库 `origin` 是 fork，而目标 `repo` 是 upstream，脚本应自动把 `head` 组装为 `origin-owner:branch`
- `assignees` 用 **GitCode 用户名**，不是邮箱
- `Signed-off-by: Name <email>` 写在 **commit message** 里；邮箱用于 signoff，不用于 assignee
- 对 openYuanRong upstream（如 `openeuler/yuanrong` / `openeuler/yuanrong-functionsystem`）实测中，缺少 `Signed-off-by` 时 API 可能返回 `pre receive hook check failed`

### GitCode 常用 API

```bash
# 列出 PR（需要 jq）
TOKEN="$GITCODE_TOKEN"
curl -s -H "private-token: $TOKEN" \
  "https://gitcode.com/api/v5/repos/openeuler/yuanrong/pulls?state=open&per_page=10" | jq '.[] | {iid, title, state, head: .head.ref, base: .base.ref}'

# 查看 PR diff
curl -s -H "private-token: $TOKEN" \
  "https://gitcode.com/api/v5/repos/openeuler/yuanrong/pulls/{iid}/files" | jq '.[] | {filename, additions, deletions, status}'

# 查看 PR commits
curl -s -H "private-token: $TOKEN" \
  "https://gitcode.com/api/v5/repos/openeuler/yuanrong/pulls/{iid}/commits" | jq '.[] | {sha: .sha[0:8], message: .commit.message}'
```

Issue API 也走同一个 token：

```bash
curl -s -X POST "https://gitcode.com/api/v5/repos/{owner}/{repo}/issues" \
  -H "Content-Type: application/json" \
  -H "private-token: $GITCODE_TOKEN" \
  -d '{"title":"...","body":"..."}'
```

## 文档

- **在线文档**: https://docs.openyuanrong.org/zh-cn/latest/index.html
- **编译指南**: `docs/contributor_guide/source_code_build.md`
- **安装指南**: `docs/deploy/installation.md`
- **单节点部署**: `docs/deploy/deploy_processes/single-node-deployment.md`
- **生产部署**: `docs/deploy/deploy_processes/production/deploy.md`

## 编译

### 环境要求

- openEuler 22.03 LTS (x86_64 或 aarch64)
- 4核+ CPU，10GB+ 内存，50GB+ 磁盘
- 工具链: JDK 8, Maven 3.9.11, Go 1.24.1, CMake 3.22, Python 3.9/3.10/3.11, Bazel 6.5.0, Ninja 1.12.0

### 编译顺序

datasystem → functionsystem → frontend → yuanrong/go → runtime/package

推荐源码目录布局采用“以 `yuanrong` 为中心”的真目录结构，避免后续手工搬运产物：

```text
WORKROOT/
└── yuanrong/
    ├── datasystem/
    ├── functionsystem/
    └── frontend/
```

### 编译 datasystem

```bash
git clone -b master https://atomgit.com/openeuler/yuanrong-datasystem.git
cd yuanrong-datasystem
bash build.sh -X off -G on -i on -j 8
```

产物 `output/`:
- `yr-datasystem-v0.7.0.tar.gz` — SDK + 二进制，运行时编译依赖
- `openyuanrong_datasystem-*.whl` — pip 安装包

### 编译 functionsystem

```bash
# 准备依赖：将 datasystem 产物拷贝到 functionsystem 的 vendor 目录
mkdir -p yuanrong-functionsystem/vendor/src
cp yuanrong-datasystem/output/yr-datasystem-*.tar.gz \
   yuanrong-functionsystem/vendor/src/yr-datasystem.tar.gz

cd yuanrong-functionsystem
./run.sh build -j 8   # 编译
./run.sh pack           # 打包
```

注意：
- 优先使用仓库公开入口 `./run.sh build` 和 `./run.sh pack`。
- `VendorList.csv` 中 `datasystem` 依赖是 `file://localhost/vendor/src/yr-datasystem.tar.gz`，因此
  **先把 datasystem 打出的 `yr-datasystem-*.tar.gz` 复制到 `vendor/src/yr-datasystem.tar.gz`**
  属于标准编译前置，不是临时兜底。
- 如果 `./run.sh build` 卡在 vendor 下载（例如 `RemoteDisconnected`、连接被远端中断），
  **优先直接重试同一条官方命令**，不要因为一次下载失败就改流程或手动绕过 vendor 下载。
  Apple Silicon 本地 arm64 实测中，这类下载错误重复执行后可以自然通过。
- 不要把 `run.sh` 内部转发到的 `python3 ./scripts/executor/make_functionsystem.py ...` 当作对外标准构建命令直接使用，除非是在专门调试 `run.sh` 包装层本身。
- Mac Docker / Ubuntu 容器中如果 `function_proxy` 链接失败并出现
  `libgrpc.so: undefined reference to symbol 'inflateEnd'`、
  `libz.so: error adding symbols: DSO missing from command line`，优先不要改源码；
  这是默认 GNU ld 对 grpc→zlib 间接 DSO 依赖解析较严格，且项目内 `--linker auto`
  可能没有真正传到最终 link 命令。先用现有 `--cmake_args` 强制 gold：

  ```bash
  ./run.sh build -j 8 \
    --cmake_args \
    CMAKE_CXX_LD_FLAGS="-fuse-ld=gold -Wl,--threads -Wl,--thread-count=7" \
    CMAKE_C_LD_FLAGS="-fuse-ld=gold -Wl,--threads -Wl,--thread-count=7"
  ```

  验证点：`functionsystem/build/build.ninja` 的目标 `FLAGS` 应包含 `-fuse-ld=gold`；
  成功日志包含 `Build function-system successfully`。

产物 `output/`:
- `yr-functionsystem-v0.0.0.tar.gz` — 函数系统包（bin/config/deploy/lib）
- `metrics.tar.gz` — 可观测包（**独立于 functionsystem tar.gz**，含 include/lib，运行时编译依赖）
- `metrics/` — metrics.tar.gz 的解压目录
- `functionsystem/` — 函数系统文件目录

### 编译运行时

```bash
# 准备 datasystem 产物
mkdir -p yuanrong/datasystem/output
cp yuanrong-datasystem/output/yr-datasystem-*.tar.gz yuanrong/datasystem/output/
tar -zxf yuanrong/datasystem/output/yr-datasystem-*.tar.gz -C yuanrong/datasystem/output/ --strip-components=1

# 准备 metrics（来自独立 metrics.tar.gz，不是 functionsystem 发布包内）
tar -zxf yuanrong-functionsystem/output/metrics.tar.gz -C yuanrong/

# 先编 frontend
cd yuanrong/frontend
bash build.sh

# 回到顶层仓，先编 dashboard/faas
cd yuanrong
bash go/build.sh

cd yuanrong
bash build.sh -P
```

产物 `output/`:
- `yr-runtime-v0.0.1.tar.gz` — 运行时发布包
- `openyuanrong_sdk-*.whl` — SDK whl（仅含 yrcli）
- `openyuanrong-*.whl` / `openyuanrong-*.tar.gz` — 完整安装包（通过 `-P` 生成）

### 编译注意事项

- `-j` 并发度建议按机器资源动态选择。默认先尝试 `-j8`
- 如果顶层 `yuanrong/build.sh -P` 阶段出现 Bazel server 异常退出、`Socket closed` 或长编后不稳定，再降到 `-j4 -m 8192`
- 编译需访问外网下载三方件（如 opentelemetry），国内可能较慢
- build.sh 和 run.sh 会自动 `source /etc/profile.d/buildtools.sh`
- `bash build.sh -X off` 禁用异构编译，一般开发不需要
- `frontend` 和 `yuanrong/go` 的构建脚本里有 `go install ...@latest` 风险；如果网络不稳或工具已存在，优先改成“仅当命令缺失时才安装”
- `yuanrong/build.sh -P` 在恢复场景下建议支持外部 `BUILD_BASE` / `OUTPUT_BASE`，这样可以切换到新的 Bazel output base 继续，而不是被坏掉的 server 元数据卡死

## 安装部署

### pip 安装（官方包）

```bash
pip install https://openyuanrong.obs.cn-southwest-2.myhuaweicloud.com/release/0.7.0/linux/x86_64/openyuanrong-0.7.0-cp39-cp39-manylinux_2_34_x86_64.whl
```

### 单节点部署

```bash
yr start --master
yr status
yr stop
```

### 编译产物安装

```bash
pip install openyuanrong_sdk-*.whl
pip install openyuanrong-*.whl
export LD_LIBRARY_PATH=/path/to/python/site-packages/yr:/path/to/python/site-packages/yr/inner:/path/to/python/site-packages/yr/inner/runtime/service/python/yr:/path/to/python/site-packages/yr/inner/runtime/service/python/yr/datasystem/lib:$LD_LIBRARY_PATH
yr start --master
```


## 本地 ST / A-B 验证（0.8.0 经验）

### 标准 C++ ST 入口

优先在已准备好的**持久容器**内跑官方 `test.sh -b -l cpp`，不要先用 `-s -r` 当验收前置：

```bash
docker restart <container> >/dev/null
sleep 3

docker exec <container> bash -lc '
  source /etc/profile.d/buildtools.sh
  cd <workroot>/src/yuanrong/test/st
  bash test.sh -b -l cpp -f <gtest-filter>
'
```

常见 clean C++ smoke：

```bash
docker exec yr-e2e-master bash -lc '
  source /etc/profile.d/buildtools.sh
  cd /workspace/clean_0_8/src/yuanrong/test/st
  bash test.sh -b -l cpp -f ActorTest.CreateSuccessful
'
```

注意：

- `test.sh -b` 会自行部署集群并在同一 shell 流程内导出 `YR_SERVER_ADDRESS`、`YR_DS_ADDRESS`、`YR_MASTER_ADDRESS` 等；这些端口每次动态变化，不要手工记旧值。
- `test.sh -s -r` 只用于 debug：它会启动并保留集群，容易留下 deploy/端口状态。跑验收 `-b` 前先 `docker restart <container>`。
- gtest 负向 filter 用 `*-A:B:C` 形式，例如 `*-CollectiveTest.InvalidGroupNameTest`。

### Mac Docker / Ubuntu 本地构建与 ST 经验

- Docker Desktop 内存建议调到 12GB/16GB+ 后再跑 datasystem/functionsystem `-j8`。
- `functionsystem` 链接阶段若出现 grpc/zlib 间接 DSO 问题（例如 `inflateEnd`、`DSO missing from command line`），不要改源码；优先通过 `run.sh` 的 `--cmake_args` 强制 gold：

  ```bash
  ./run.sh build -j 8 \
    --cmake_args \
    CMAKE_CXX_LD_FLAGS="-fuse-ld=gold -Wl,--threads -Wl,--thread-count=7" \
    CMAKE_C_LD_FLAGS="-fuse-ld=gold -Wl,--threads -Wl,--thread-count=7"
  ```

- 若 C++ ST 链接/启动时遇到 `liblitebus.so` 的 `openpty` 未解析，根因通常是缺少 `libutil` 依赖传播；优先用正式重编/打包让相关 `.so` 带 `libutil.so.1` 的 DT_NEEDED。`LD_PRELOAD`、`/etc/ld.so.preload`、`patchelf` 到临时 output 副本只作为本地诊断/绕过，不视为源码修复。
- 如果 clean C++ ST 在 Mac Docker amd64 emulation 下能启动集群，但卡在 `StartRuntime` / `runtime_executor.cpp:GetCppBuildArgs` 后不出现 `execute final cmd`，先用 x86 Linux/WSL 或持久容器复测同一 `test.sh -b -l cpp` 命令，再判断是否为项目代码问题。

## 脚本

所有脚本位于 skill 目录的 `scripts/`，仅依赖 `curl`、`jq`、`git`，无需 Python。第一次使用先运行 `scripts/init-config.sh`。

### gitcode.sh — GitCode API 查询

```bash
gitcode.sh list yuanrong --limit 5              # 列出 open MR
gitcode.sh list yuanrong --state merged         # 列出已合入 MR
gitcode.sh show yuanrong 533                   # 查看 MR 详情
gitcode.sh diff yuanrong 533                   # 查看变更文件列表
gitcode.sh commits yuanrong 533                # 查看 MR 的 commits
gitcode.sh create-pr yuanrong fix/tenant-ref-ds-context \
  "fix[libruntime]: restore tenant context for returned-object DS incref" \
  "中文说明" --base feature/sandbox --assignees luozhancheng
gitcode.sh create-pr yuanrong fix/tenant-ref-ds-context \
  "fix[libruntime]: restore tenant context for returned-object DS incref" \
  "中文说明" --base feature/sandbox --head luozhancheng:fix/tenant-ref-ds-context
gitcode.sh issues yuanrong --limit 5           # 列出 issue
gitcode.sh issue yuanrong 123                  # 查看 issue
gitcode.sh create-issue yuanrong "title" "body"
gitcode.sh comment-issue yuanrong 123 "body"
```

### submit.sh — 提交代码（自动 Signed-off-by + 格式校验）

```bash
submit.sh "fix(docs): 修复编译文档"            # 当前分支提交
submit.sh "fix(docs): 修复编译文档" fix/xxx-doc  # 创建新分支并提交
submit.sh --amend "fix(docs): 修正描述"        # 修正上一次提交
```

自动检查 commit message 符合 `type(scope): 描述` 格式，自动追加 `Signed-off-by`，push 失败时提示 webhook 原因。

### create-pr.sh — 创建 MR 完整流程（一键）

```bash
create-pr.sh yuanrong "fix(docs): 修复编译文档" "详细说明"
create-pr.sh yuanrong "fix(docs): 修复编译文档" "" fix/docs-fix  # 指定分支名
create-pr.sh yuanrong "feat[cli]: 新增命令" "详细说明" "" feature/sandbox  # 指定目标分支
create-pr.sh yuanrong "fix[libruntime]: 恢复 returned-object 的租户上下文" \
  "中文说明" "" feature/sandbox --assignees luozhancheng
```

自动完成：创建分支 → git add → commit（含 Signed-off-by）→ push → 创建 MR，输出 MR URL。

- 若当前仓库 `origin` 是 fork、目标 repo 是 upstream，脚本会自动把 `head` 组装成 `owner:branch`
- 也可以通过 `--head` 显式指定源分支引用，通过 `--assignees` 传 GitCode 用户名

### sync-pr.sh — 同步 MR 变更到本地

```bash
sync-pr.sh yuanrong 533                # cherry-pick MR 的 commits 到当前分支
sync-pr.sh yuanrong 533 --branch        # 创建新分支再 cherry-pick
sync-pr.sh yuanrong 533 --files       # 只列出变更文件
```

用于将其他人的 MR 变更同步到本地仓库，方便本地调试或二次开发。

### review-pr.sh — 导出 MR diff 供审查

```bash
review-pr.sh yuanrong 533               # 输出完整 diff（可直接给 Claude 审查）
review-pr.sh yuanrong 533 --raw          # 输出 JSON（含 patch）
review-pr.sh yuanrong 533 --files       # 只输出文件列表
```

## 关键经验

1. **metrics 来源**: 独立的 `metrics.tar.gz`，不是 functionsystem 发布包内（基线验证确认）
2. **Python 路径**: install_tools.sh 创建 symlink，`/usr/local/bin/python3.x` → buildtools，所有 python 解析结果一致
3. **文档链路缺失**: 文档只覆盖"编译组件"和"官方 whl 部署"，`build.sh -P` 打包链路未文档化
4. **API 认证**: gitcode API 用 `private-token` header，不是 `access_token` 参数
5. **0.7.0 真实可运行链路**: 在官方结构和完整 wheel 形态下，bare `yr.init()` 的 Python 无状态/有状态示例可跑通；这一点可以作为和开发态 `master` 对比的基线
6. **函数服务不是同一最小环境**: `yr start --master` 拉起的是 job/runtime 链，不会自动提供 `frontend` / `meta_service` 的 HTTP 端点；函数服务示例需要额外的服务化部署路径
7. **GitCode fork 提 upstream PR 的硬性条件**: commit 必须带 `Signed-off-by`；`assignees` 传用户名，不能传邮箱

## 事件复盘文档

- `references/feature-sandbox-arm64-cpp-st-2026-05.md` — 本次 Apple Silicon arm64 `feature/sandbox` C++ ST 从构建、定位、修复到提 PR 的完整复盘

## Rust 替换验证原则

Rust FunctionSystem 替换验证的操作细节放在 `yr-buildkite`。在开发判断上遵守这些约束：

- 先建立 C++ baseline，再判断 Rust 替换问题。
- 如果 C++ baseline 在同一流程下通过，后续 Rust E2E 失败默认只定位 Rust FunctionSystem 替换链路。
- baseline 成立前，不为通过 Rust ST 去修改 frontend、runtime、测试断言或其它非 Rust 行为。
- A/B 对比应保留 case matrix：测试名、A 结果、B 结果、差异类别、复现性、当前 Rust 状态。

## 现成编译环境

历史本机容器 `yr-baseline-test`（基于 `openeuler:22.03-yr-compile`）曾保存完整编译产物：

```bash
docker start yr-baseline-test
docker exec -it yr-baseline-test bash
```

旧宿主机挂载目录示例：`$HOME/workspace/cicd_gitcode/docs_update/build_env/opt_openyuanrong/`。

这类路径是本机资产提示，不是跨机器安装要求；迁移后优先使用 `yr_test` 或 `yr-buildkite` 中的编译镜像流程重建。

## 公共资产

### yr_test

`$HOME/workspace/yr_test` 是本机的 Yuanrong 公共验证资产目录。

优先用途：

- 复用已验证的 `0.7.0` baseline
- 直接进入 `release_0_7_official/yuanrong` 开新分支验证特性
- 在固定 build/runtime 容器里挂载外部源码树重新编译

关键入口：

- 根说明：`$HOME/workspace/yr_test/README.md`
- 容器恢复：`$HOME/workspace/yr_test/handbook/CONTAINERS.md`
- 最小验证链：`$HOME/workspace/yr_test/handbook/VERIFY.md`
- 已知坑：`$HOME/workspace/yr_test/handbook/KNOWN_ISSUES.md`

推荐固定镜像 tag：

- `openeuler:22.03-yr-asset-0.7.0`
- `openeuler:22.03-yuanrong-garden`

### yr_vendor

`$HOME/workspace/code/yr_vendor` 是本机的 Yuanrong 本地依赖归档目录。

用途：

- 固化容易漂移或难下载的三方件
- 记录不同分支线依赖来源和版本
- 把“下载源问题”和“代码/构建问题”分开定位

关键入口：

- 说明：`$HOME/workspace/code/yr_vendor/README.md`
- 总清单：`$HOME/workspace/code/yr_vendor/manifests/yuanrong-deps.md`
- 当前 0.7.0 种子归档：`$HOME/workspace/code/yr_vendor/manifests/seed-release-0.7.0.md`
