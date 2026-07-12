# feature/sandbox Apple Silicon arm64 C++ ST 复盘（2026-05）

## 目的

沉淀这次 `feature/sandbox` 在 Apple Silicon 本地 arm64 Docker 环境中，从源码构建到 full C++ ST 跑绿、再拆分 PR 的完整经验。

这份文档保留：

- 事件背景与约束
- 关键失败签名与根因
- 证据目录与 PR 对应关系
- 哪些经验已沉淀进 `yr-dev` skill，哪些只适合保留在复盘文档里

## 背景与约束

- 目标：在本地 Apple Silicon arm64 Docker 环境中，让 `feature/sandbox` 的 C++ baseline 跑通并稳定通过 full C++ ST
- 约束：
  - 本地验证优先，不用远端结果代替本地结论
  - 每次失败都保留 `/tmp/deploy` 和完整日志
  - clean container / clean rerun 要有证据
  - 最终需要把可以上游的改动拆成独立 PR

## 最终结果

- `feature/sandbox` 本地 arm64 **full C++ ST 绿色且稳定**
- 额外 clean container 重跑后，结果可重复，不是概率性通过
- 相关修复已拆为：
  - `openyuanrong` 6 个 PR
  - `yuanrong-functionsystem` 3 个 PR

## 关键问题与结论

### 1. returned-object / datasystem tenant context

现象：

- `TaskTest.ExecWithDirectReturn` 卡死或失败
- returned object 走 DS global ref 增加时，tenant context 不稳定

结论：

- 正确修复不是手工改 object key
- 而是：
  - `InvokeAdaptor::HandleReturnedObject` 调 `IncreDSGlobalReference` 前恢复 tenant callback
  - `TaskSubmitter::HandleSuccessInvokeNotify` 调 `IncreDSGlobalReference` 前显式 `SetTenantId`

对应 PR：

- `openeuler/yuanrong !688`

### 2. package 产物保留了 staging symlink

现象：

- fresh container 中 `libyr-api.so` 找不到
- 包内 `.so` 实际指向构建容器 Bazel cache

结论：

- `scripts/package_yuanrong.sh` 复制 staging 产物时不能保留 symlink
- 需要用 `cp -aL`

对应 PR：

- `openeuler/yuanrong !689`

### 3. package 可选组件判断不是真正可选

现象：

- frontend/faas/dashboard 缺失时，本应跳过
- 实际上因为 `set -e` + `ls` 失败而提前退出

结论：

- 可选组件检测要显式容错，仅在文件存在时进入复制逻辑

对应 PR：

- `openeuler/yuanrong !690`

### 4. ST harness 端口导出不稳定

现象：

- `test/st/test.sh` 直接抓日志字段，可能拿到空值、旧值或未就绪端口

结论：

- 需要从 deploy 日志中显式提取 proxy / DS worker 端口，并等待端口落稳后再导出环境变量

对应 PR：

- `openeuler/yuanrong !691`

### 5. collective 仍使用旧 DS KV 语义

现象：

- collective case 在当前运行时 / DS 语义下不稳定

结论：

- `Set/Get/Del/wait` 需要对齐当前 KVManager API 语义
- group create 需要对短暂 `ERR_KEY_ALREADY_EXIST` 做有限重试

对应 PR：

- `openeuler/yuanrong !692`

### 6. top-level Bazel 的 arm64 兼容问题

现象：

- datasystem 外部依赖在 arm64 本地构建时踩到 msvc-only 输入、cython BUILD 和 proto 根路径问题

结论：

- `libsodium` / `libzmq` 排除 msvc 目录
- 本地化 `bazel/cython.BUILD`
- 修正 `datasystem_build.bzl` 的 etcd proto 根路径推导

对应 PR：

- `openeuler/yuanrong !693`

### 7. functionsystem GCC 11 / arm64 编译兼容

现象：

- vendor 三方仍用 C++14
- 主体代码若干 range-for 在 GCC 11 下被 `-Werror` 放大

结论：

- vendor 提升到 C++17
- 主体保留 `-Werror`，仅降低 `range-loop-construct`
- 明确的按值遍历改成按引用

对应 PR：

- `openeuler/yuanrong-functionsystem !291`

### 8. zero-valued resource 被误判为真实资源需求

现象：

- `gpu=0` 等 zero-valued 资源会被当成必须匹配
- 节点不声明该资源类型时被误判为资源不足

结论：

- 资源比较前先剔除值为 0 / empty 的资源项

对应 PR：

- `openeuler/yuanrong-functionsystem !292`

### 9. runtime signal 诊断信息不足

现象：

- `SIGSEGV` / `SIGILL` 等异常退出只显示 unknown error

结论：

- healthcheck 需要显式提取 signal name
- 优先拼接 runtime `.err` / `.out` 独立日志

对应 PR：

- `openeuler/yuanrong-functionsystem !293`

## 0.8.0 vs feature/sandbox 的判断

结论不是“0.8.0 写对了，sandbox 写坏了”，而是：

- tenant/ref 这类问题在 0.8.0 更像 latent bug
- 到 `feature/sandbox` 因返回对象处理链更复杂、线程边界更多、依赖语义更严格，才被稳定暴露

因此这类分析适合保留在复盘文档里，而不是直接塞进脚本。

## GitCode / PR 工作流经验

### 已确认规则

- upstream PR 创建对 commit message 中的 `Signed-off-by` 很敏感
- 缺 `Signed-off-by` 时，API 可能报：
  - `pre receive hook check failed`
- `assignees` 传 **用户名**
- 邮箱用于：
  - `Signed-off-by: Name <email>`

### 这次实测成立的 API 形式

```json
{
  "title": "...",
  "body": "...",
  "head": "luozhancheng:fix/tenant-ref-ds-context",
  "base": "feature/sandbox",
  "assignees": "luozhancheng"
}
```

目标接口：

```text
POST https://gitcode.com/api/v5/repos/openeuler/yuanrong/pulls
```

## 证据目录

关键证据位于：

- `/Users/lzc/workspace/code/yr-rust/sandbox-arm64/evidence/`

其中包括：

- baseline build
- full C++ ST
- failing cases 单跑
- rerun / stability 记录
- deploy tar 与 meta 信息

## 哪些应沉淀到 skill

适合沉淀到 `yr-dev` skill 的是：

- GitCode fork → upstream PR API 写法
- `Signed-off-by` / assignee 规则
- create-pr / gitcode helper 的参数约定
- 分支命名与 MR 标题风格

这些是“下次还能直接执行”的知识。

## 哪些应保留在 md

适合保留在本复盘 md 的是：

- 这次 case 的时间线
- 哪个问题对应哪个 PR
- 哪份证据在哪个目录
- 0.8.0 vs `feature/sandbox` 的根因分析

这些是“事件上下文与证明链”，不适合塞进脚本。
