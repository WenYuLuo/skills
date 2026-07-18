# macOS / Apple Silicon 本地编译与 AIO 镜像验收

本参考固化在 Apple Silicon macOS + Docker Desktop 上，从源码编译 openYuanRong、构建
ARM64 AIO 镜像、再跑 SDK/FaaS/sandbox E2E 时最容易混淆的环境边界。它补充 `yr-dev`
的通用编译流程；AIO 的启动和用例命令仍以 `yuanrong-aio` 为准。

## 目录

- [1. 构建前先做环境闸门](#1-构建前先做环境闸门)
- [2. 架构必须端到端一致](#2-架构必须端到端一致)
- [3. 编译镜像不是运行镜像](#3-编译镜像不是运行镜像)
- [4. split wheel 与嵌套 runtime tag](#4-split-wheel-与嵌套-runtime-tag)
- [5. Docker Desktop 嵌套 dockerd](#5-docker-desktop-嵌套-dockerd)
- [6. Go runtime 与插件必须成套重编](#6-go-runtime-与插件必须成套重编)
- [7. 最终验收顺序](#7-最终验收顺序)

## 1. 构建前先做环境闸门

```bash
/bin/bash --version
docker info --format 'arch={{.Architecture}} memory={{.MemTotal}}'
docker system df
docker buildx version
```

- macOS 自带 `/bin/bash` 通常是 3.2，没有 `mapfile`。宿主机执行的脚本应使用
  `while IFS= read -r` 填充数组；否则明确使用安装的新 Bash。长编译前先跑
  `bash -n deploy/sandbox/docker/build-images.sh`。
- 全量 ARM64 编译和 AIO 镜像构建同时存在时，Docker Desktop 分配 16 GiB 是较实用
  的下限，24 GiB 更稳；通用文档中的 10 GiB 只是最低起点。磁盘至少预留 50 GiB，
  因为单个 AIO 镜像可超过 8 GiB，源码产物、嵌套镜像 tar 和 BuildKit cache 还会继续增长。
- 发生 `cc1plus` killed、Bazel server 退出时先查容器 OOM，再降并行度；不要先改源码：

  ```bash
  docker inspect CONTAINER --format 'oom={{.State.OOMKilled}} exit={{.State.ExitCode}}'
  ```

- 把源码、output 和下载/编译 cache 放在持久 bind mount 或命名 volume 中。Docker daemon
  重启后可以续编；同步源码时只覆盖预期文件，尤其不要用单个组件输出替换整个 assembly
  目录。

## 2. 架构必须端到端一致

Apple Silicon 默认目标应为 `arm64`。至少检查：编译镜像、AIO 外层镜像、嵌套 runtime
镜像、`runtime-launcher`、Traefik 和装入 wheel 的本地二进制。

```bash
docker image inspect "$COMPILE_IMAGE" --format '{{.Architecture}}'
docker image inspect "$AIO_IMAGE" --format '{{.Architecture}}'
file output/runtime-launcher
```

Dockerfile 下载平台工具时必须使用 BuildKit 的 `TARGETARCH`。如果旧 Dockerfile 写死
`traefik_*_linux_amd64.tar.gz`，ARM64 镜像虽然可能构建成功，却会在启动时得到
`exec format error`。当前 AIO Dockerfile 应按 `amd64|arm64` 生成下载 URL。

不要在 Apple Silicon 上看到失败就笼统判断“macOS 不兼容”。先区分：

| 症状 | 首先判断 |
| --- | --- |
| `mapfile: command not found` | 宿主 Bash 3.2 脚本兼容性 |
| `exec format error` | 镜像或下载二进制架构不一致 |
| `failed to mount overlay: invalid argument` | Docker Desktop 嵌套 dockerd 存储驱动 |
| `libbrpc.so` undefined `pthread_mutex_init` | 在编译镜像中误跑运行时，glibc/运行环境不匹配 |
| `plugin was built with a different version` | Go host/plugin ABI 不一致 |
| 请求落到 `/openyuanrong/.py` | FunctionMeta 的 module/class 元数据为空，属于产品/打包逻辑，不是 macOS |

## 3. 编译镜像不是运行镜像

Ubuntu 20.04 compile image 只负责生成产物。不要在那里把服务能否启动作为最终验收，
特别是 DataSystem/BRPC 等动态库；产物必须放进目标 Ubuntu 22.04/AIO runtime image 再判定。

合理流程是：

1. 在 compile image 完成 datasystem/functionsystem/frontend/go/runtime package；
2. 对 wheel 和 ELF 做静态完整性检查；
3. 构建目标架构 runtime/AIO image；
4. 从该镜像创建全新容器跑 readiness 和 E2E。

热替换容器只能用于快速定位。最终证据必须来自重新构建的镜像和 fresh container，避免
把容器内手工补丁误当成镜像已经包含的结果。

## 4. split wheel 与嵌套 runtime tag

启用 split wheel 后，AIO runtime image 至少要安装匹配的 base/SDK/runtime wheel；不能
只安装 `openyuanrong-*.whl` 和 SDK。运行时目录是：

```text
<site-packages>/yr/runtime/service
```

不是旧路径 `yr/inner/runtime/service`。构建前后可用以下闸门：

```bash
unzip -l output/openyuanrong_runtime-*.whl | grep 'yr/runtime/service'
docker run --rm "$RUNTIME_IMAGE" python -c '
from pathlib import Path
import yr
p = Path(yr.__file__).parent / "runtime/service"
assert p.is_dir(), p
print(p)
'
```

`services.yaml` 和 runtime launcher 固定查找 `aio-yr-runtime:latest`。即使通过
`YR_RUNTIME_IMAGE` 指定自定义构建名，保存进 AIO 的 tar 前也必须额外打固定 tag：

```bash
docker tag "${YR_RUNTIME_IMAGE}:latest" aio-yr-runtime:latest
docker save aio-yr-runtime:latest -o output/aio-yr-runtime.tar
```

fresh AIO 启动后确认嵌套镜像确实存在：

```bash
docker exec "$AIO_CONTAINER" docker image inspect aio-yr-runtime:latest
```

## 5. Docker Desktop 嵌套 dockerd

AIO 中运行 dockerd 需要：

```text
--privileged --cgroupns host
```

Docker Desktop 上，外层文件系统不一定允许内层 dockerd 使用 `overlay2`。典型日志是
`failed to mount overlay: invalid argument`。入口脚本应先尝试 `overlay2`，失败后清理旧
进程并改用 `vfs`；如果 `docker info` 随后成功，这属于预期环境降级，不是 YuanRong
代码错误。不要为了消除这一行预期日志去修改业务组件。

## 6. Go runtime 与插件必须成套重编

Go `plugin` 要求宿主和插件所依赖包的构建身份一致。以下文件应视为同一个 ABI 集合：

- `goruntime`
- `faasfrontend.so`
- `faasscheduler.so`
- `faasmanager.so`

只重编 frontend，常见失败是：

```text
plugin was built with a different version of package go.uber.org/multierr
```

只把 `goruntime` 再重编一次，又可能让旧 scheduler/manager 插件失败。只要改过共享 Go
包、Go toolchain、build tags、ldflags 或安全编译参数，就应在同一源码树、同一个 Go
版本/GOROOT、同一 `GOWORK`/`GOTOOLCHAIN` 和同一 `CGO_CFLAGS` 下重编整个集合。

产物 assembly 也要合并而不是替换：frontend 产出 `faasfrontend`，`yuanrong/go` 产出
`faasscheduler` 和 `faasmanager`。把 frontend 的 `pattern_faas` 整目录覆盖过去会静默删掉
后两者，最终表现为 master 重启或 FaaS 超时。

打包前至少检查：

```bash
find output/pattern/pattern_faas -maxdepth 2 -type f \
  \( -name 'faasfrontend.so' -o -name 'faasscheduler.so' -o -name 'faasmanager.so' \) \
  -print
```

最终 fresh-container 日志中不得出现：

```text
plugin was built with a different version
```

## 7. 最终验收顺序

1. 从最终 image 新建容器，保留 `--privileged --cgroupns host`；
2. 等 frontend 后端就绪，不能把 Traefik 502 当 ready；
3. 检查 `OOMKilled=false`、外层/嵌套镜像均为目标架构；
4. 跑 SDK invoke/actor/put-get/异常传播；
5. 跑 FaaS 端到端；
6. 跑 sandbox create/delete，路由已注册但无 HTTP 后端时 502 是预期信号；
7. 扫描 Go plugin ABI、`exec format error`、OOM 和 runtime image lookup 错误。

通过这组闸门后，才能把失败归因到产品逻辑；在此之前优先按上面的环境症状表收敛。
