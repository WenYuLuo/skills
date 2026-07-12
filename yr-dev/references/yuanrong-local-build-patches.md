# YuanRong 本地构建 patch 层

本参考用于 openYuanRong/YuanRong 本地 ARM/Linux 编译时，在网络稳定前置已经应用后，处理已知 build-support 兼容问题。它是**本地稳定构建层**，不是产品功能变更；后续应按独立 build-support patch upstream 化。

## 适用边界

优先只在以下条件同时满足时使用：

1. 已确认编译源是 `yuanrong` superproject 及其 submodule 的明确 commit；
2. 已应用 `build-network-robustness.md` 中的网络/cache/env 前置；
3. 错误可稳定复现，不是一次下载超时；
4. 当前 upstream 尚未包含等价修复。

已验证问题附近 commit：

```text
yuanrong superproject: 0d8184c75813d17bbfbc077302e0689af23b43ce
functionsystem: cb9fa7774c607487ba76b671e7539656afbb6b91
```

失效判断：如果当前源码 commit 已更新，或 patch apply 失败，先检查 upstream 是否已经包含等价修复；不要强行套旧 patch。优先用 `git log`、`git blame`、`git diff` 判断是否已有同类变更。

## 1. functionsystem GCC11 / C++17 兼容

### 症状

在本地 ARM/Linux 编译 `functionsystem` 或 top-level `make all` 时，`functionsystem/vendor` 子构建失败，典型错误：

```text
std::string_view is only available from C++17 onwards
‘string_view’ is not a member of ‘absl’
```

临时改过 vendor C++ 标准后，可能继续在主源码阶段遇到 GCC11 warning-as-error：

```text
-Werror=range-loop-construct
```

### 根因

在 `functionsystem@cb9fa777...` 附近，vendor CMake release flags 使用 C++14，但 absl/protobuf/re2 组合需要 C++17；同时 GCC11 会把部分 range-loop 复制 warning 变成 error。

### 本地稳定 patch 方向

优先使用或重做等价于以下 upstream 单提交的补丁：

```text
commit: 1a8b6319dd07d5df30cba8cfeaaf979350e03b9e
message: build: make functionsystem compile cleanly with GCC 11
```

该提交的有效内容应覆盖：

- `vendor/vendor_utils.cmake`：thirdparty C++ 标准从 C++14 调整到 C++17；
- `functionsystem/CMakeLists.txt`：在 `-Werror` 体系下处理 `range-loop-construct`；
- 必要的源级 `const auto &` range-loop 修正。

不要 merge 整个 `origin/build/gcc11-compat` 分支；它可能包含非目标历史。只摘取或重做单个 build-support patch。

### 检查命令

```bash
git -C functionsystem log --oneline --decorate --all --grep 'GCC 11' --
git -C functionsystem branch -r --contains 1a8b6319dd07d5df30cba8cfeaaf979350e03b9e || true
git -C functionsystem show --stat --oneline 1a8b6319dd07d5df30cba8cfeaaf979350e03b9e || true
```

如果当前源码已经包含 `vendor_utils.cmake` C++17 和 `range-loop-construct` 处理，不要重复 patch。

## 2. setuptools / pkg_resources 环境漂移

### 症状

`functionsystem` 构建已通过、Bazel 主构建也通过后，`yuanrong` package 阶段失败：

```text
ModuleNotFoundError: No module named 'pkg_resources'
```

常见上下文：同一容器里先前步骤把 `setuptools` 升级到较新版本，后续旧 wheel 打包路径仍依赖 `pkg_resources`。

### 本地稳定处理

优先方案是隔离 Python build env，避免某个子组件升级全局 Python 环境污染后续 package。若暂时无法改构建脚本，可在进入 `yuanrong` package 前恢复兼容版本：

```bash
python3 -m pip install 'setuptools==58.1.0' wheel packaging cloudpickle==3.1.2
python3 - <<'PY'
import pkg_resources, setuptools
print('pkg_resources_ok', setuptools.__version__)
PY
```

然后再执行 package 阶段。

注意：如果直接重新跑 full `make all`，前面的 `functionsystem` 步骤可能再次升级 setuptools，导致同样问题复现。因此该处理必须发生在 `functionsystem` 之后、`yuanrong` package 之前，或使用真正隔离的 Python env。

### upstream 化方向

- 在构建脚本中隔离 functionsystem Python env；或
- 在 package 阶段显式约束兼容 setuptools；或
- 升级 wheel 打包逻辑，移除旧 `pkg_resources` 依赖。

## 3. Python wheel 复制时序 / 残留产物

### 症状

split wheel package 阶段出现：

```text
cp: skipping file '.../api/python/dist/<wheel>.whl', as it was replaced while being copied
```

### 判别

先不要误判为源码编译失败。确认同一个 wheel 是否可单独复制且 sha256 一致：

```bash
rm -f output/<wheel-name>.whl
cp -v api/python/dist/<wheel-name>.whl output/
shasum -a 256 api/python/dist/<wheel-name>.whl output/<wheel-name>.whl
```

如果单独复制成功且 sha256 一致，说明 wheel 本身有效，问题更可能是打包脚本时序、glob 扫到残留、或构建后处理仍在替换文件。

### 本地稳定处理

- 每轮 `SETUP_TYPE` 前清理：`rm -rf build/ dist/ *.egg-info`；
- 每轮只复制本轮刚生成的确切 wheel；
- 失败后可只续跑未完成的 wheel package，不必重跑已通过的 components/Bazel；
- 不要把该错误归因到网络或产品源码。

### upstream 化方向

构建脚本应避免用宽泛 `dist/*whl` 在文件仍可能变化时复制；可改为先定位本轮生成的唯一 wheel、复制到临时文件再原子 rename，或严格串行化 wheel 生成和复制。

## 4. zip 等构建工具前置

`frontend` build 需要 `zip`。如果标准编译镜像未内置，top-level build 可能在 frontend 阶段失败。

本地稳定处理：在 build wrapper/preflight 中检查并安装/提示：

```bash
command -v zip >/dev/null || apt-get update && apt-get install -y zip
```

upstream 化方向：把 `zip` 纳入标准编译镜像，或在官方 build preflight 中明确检查并报可操作错误。

## 5. 使用原则

- 这些 patch/动作必须作为 build-support 层记录和执行，不得和 frontend/proxy 产品功能混在同一个 diff。
- 每次使用都记录：源码 commit、是否包含 upstream 等价修复、应用的 patch、命令、日志、输出件 sha256。
