# YuanRong 编译网络稳定性与可复用缓存

本参考用于 openYuanrong/YuanRong 本地或容器编译时，排查并稳定处理依赖下载问题。目标不是“碰运气多试几次”，而是把下载路径、缓存目录、可清理边界和不可改行为讲清楚。

## 默认边界

- **不改项目构建行为**：除非用户明确允许，不修改仓库构建脚本、`WORKSPACE`、`go install ...@latest`、`npm install` 等真实构建语义。
- **动态注入优先**：用环境变量、Bazel 参数、容器运行参数、预热缓存来增强稳定性。
- **调用者当前工作目录**：skill 生成的临时文件、缓存、下载清单、日志默认放在调用者当前工作目录下，例如 `./.yr-cache/`、`./network-experiment/`；不要写死成本机路径。
- **证据优先**：不要直接判断“华为云不行”。先区分宿主机网络、Docker NAT、容器 `--network host`、代理、以及具体工具本身的行为。

## 推荐的一次性动态环境

在启动编译容器或进入容器后，优先准备统一缓存根目录：

```bash
export YR_CACHE_DIR="${YR_CACHE_DIR:-$PWD/.yr-cache}"
mkdir -p \
  "$YR_CACHE_DIR/go/pkg/mod" \
  "$YR_CACHE_DIR/go-build" \
  "$YR_CACHE_DIR/npm" \
  "$YR_CACHE_DIR/bazel-distdir" \
  "$YR_CACHE_DIR/bazel-repository-cache" \
  "$YR_CACHE_DIR/datasystem-opensource" \
  "$YR_CACHE_DIR/functionsystem-vendor-cache" \
  "$YR_CACHE_DIR/cargo"

# Python / uv：不要依赖镜像内 pip.conf，可以动态覆盖。
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple
export PIP_TRUSTED_HOST=mirrors.aliyun.com
export PIP_DEFAULT_TIMEOUT=100
export UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple
export UV_HTTP_TIMEOUT=100

# Go：缓存 toolchain/module/build；不要默认禁用 toolchain auto。
export GOPATH="$YR_CACHE_DIR/go"
export GOMODCACHE="$YR_CACHE_DIR/go/pkg/mod"
export GOCACHE="$YR_CACHE_DIR/go-build"
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.org
export GONOSUMDB=*

# npm/dashboard：保持构建命令不变，只注入 registry/cache。
export npm_config_registry=https://registry.npmmirror.com
export npm_config_cache="$YR_CACHE_DIR/npm"
export npm_config_audit=false
export npm_config_fund=false

# Bazel：build.sh 已支持 BAZEL_REPOSITORY_CACHE；distdir 通过 BAZEL_OPTIONS 传入。
export BAZEL_REPOSITORY_CACHE="$YR_CACHE_DIR/bazel-repository-cache"
export BAZEL_OPTIONS="${BAZEL_OPTIONS:-} --distdir=$YR_CACHE_DIR/bazel-distdir"

# datasystem / functionsystem：把默认 /tmp 缓存搬到当前工作目录。
export DS_OPENSOURCE_DIR="$YR_CACHE_DIR/datasystem-opensource"
export FS_VENDOR_CACHE_DIR="$YR_CACHE_DIR/functionsystem-vendor-cache"

# Cargo：默认只固定 cargo home；target 缓存可能很大，按需开启。
export CARGO_HOME="$YR_CACHE_DIR/cargo"
# export CARGO_TARGET_DIR="$YR_CACHE_DIR/cargo-target"
```

启动编译容器时，国内镜像访问优先使用宿主网络验证/执行：

```bash
docker run --network host ...
```

如果必须通过代理诊断，优先只对单次实验传入 `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`，不要把 AI/国外代理默认强加给 apt、pip、Go、Bazel 等国内镜像路径。

## 根因与稳定策略

### 1. 华为云 / Docker 网络

经验结论：华为云镜像源并不等于“服务挂了”。宿主机直接访问通常正常；Docker 默认 NAT 路径可能出现间歇性 SSL/timeout。容器使用 `--network host` 后，国内镜像访问稳定性显著提高。

处理顺序：

1. 宿主机 curl 同一 URL。
2. 容器默认网络 curl 同一 URL。
3. 容器 `--network host` curl 同一 URL。
4. 必要时再测试代理路径。

若 `--network host` 明显稳定，优先把它作为编译容器运行方式，而不是修改项目源码或反复手工重试。

### 2. apt

编译镜像常见 apt 源为华为云 `ubuntu-ports`。apt 不是当前最主要瓶颈，但属于潜在风险。优先使用 `--network host` 提升容器访问稳定性；不要因为一次 apt 失败就改 Dockerfile 或全局换源。

### 3. pip / uv

镜像内可能已有华为云 `pip.conf`，但镜像会变，因此 skill 应动态传入 `PIP_INDEX_URL`/`UV_INDEX_URL`。实测阿里云 PyPI 在容器默认 NAT 下更快，可作为默认动态覆盖。

### 4. Go / toolchain / `@latest`

项目 `go.mod` 约束的是项目模块依赖；构建脚本中的 `go install xxx@latest` 是构建时工具安装，不受项目 `go.mod` 固定。`@latest` 可能触发工具版本漂移，甚至触发 Go toolchain 下载。

已知风险：

- `protoc-gen-go-grpc@latest` 曾解析到需要更高 Go 版本的版本，并触发 toolchain 下载。
- `functionsystem/vendor/src/etcd/go.mod` 可声明 `toolchain go1.24.9`；若镜像是 Go 1.24.1，默认 `GOTOOLCHAIN=auto` 会尝试下载对应 toolchain。

在“不改构建行为”前提下：

- 不要全局设置 `GOTOOLCHAIN=local`，否则本来依赖 auto 下载的路径会直接失败。
- 设置 `GOMODCACHE`/`GOCACHE`/`GOPATH` 到 `.yr-cache`，让 toolchain/module 下载可复用。
- 设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=sum.golang.org`，避免 `GOSUMDB=off` 导致 toolchain 校验失败。

若用户允许改变构建行为，才考虑把构建工具从 `@latest` 改成明确版本或“命令存在则不安装”。

### 5. Maven

Maven CLI 的全局 settings 可能已经配置华为云 mirror。用户级 `-s settings.xml` 不一定能覆盖全局 mirror；需要使用 `-gs` 指定全局 settings：

```bash
cat > "$YR_CACHE_DIR/maven-settings.xml" <<'XML'
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>aliyunmaven</id>
      <mirrorOf>*</mirrorOf>
      <name>Aliyun Maven</name>
      <url>https://maven.aliyun.com/repository/public</url>
    </mirror>
  </mirrors>
</settings>
XML

mvn -gs "$YR_CACHE_DIR/maven-settings.xml" ...
```

### 6. Bazel / `http_archive`

`WORKSPACE` 中大量 `http_archive` 先指向华为云 OBS，部分有非华为 fallback。Bazel 的动态注入不是“失败后自动切换”，而是提前把符合文件名和 sha256 的归档放入 `--distdir`，或让 `--repository_cache` 复用已经下载过的内容。

原则：

- 相同的依据是 `sha256`，不是“源站名字相同”。
- 官方上游归档如果 sha256 与 `WORKSPACE` 一致，就可作为等价预热文件。
- 下载到 `./.yr-cache/bazel-distdir` / `./.yr-cache/bazel-repository-cache`，便于后续清理。

### 7. `tools/download_dependency.sh` / runtime thirdparty

顶层 `build.sh` 在非 clean 且未设置 `SKIP_RUNTIME_DEPENDENCY_DOWNLOAD=1` 时，会在 Bazel 前执行 `tools/download_dependency.sh`。它通过 `tools/openSource.txt` 下载 runtime 三方件到源码树：

```text
yuanrong/thirdparty/
```

稳定策略：

- 不要默认删除 `yuanrong/thirdparty`，它本身就是昂贵下载缓存。
- 可动态指定已有缓存源：

  ```bash
  export THIRD_PARTY_CACHE="https://build-logs.openeuler.openatom.cn:38080/temp-archived/openeuler/openYuanrong/deps/"
  export RUNTIME_THIRD_PARTY_CACHE="https://build-logs.openeuler.openatom.cn:38080/temp-archived/openeuler/openYuanrong/runtime_deps/"
  ```

- 如果此阶段失败，先确认是 `openSource.txt` 哪个 URL、哪个工具失败，再决定是否预热，不要泛化成“Bazel 下载失败”。

### 8. datasystem

`make datasystem` 进入 `datasystem/build.sh`，再由 CMake/FetchContent 构建三方依赖。`datasystem/cmake/util.cmake` 支持：

```bash
export DS_OPENSOURCE_DIR="$PWD/.yr-cache/datasystem-opensource"
```

这会把默认 `/tmp/<hash>` 下的三方缓存搬到当前工作目录，便于复用和清理。第一次仍可能下载/编译；后续在版本、sha、构建参数不变时复用。

### 9. functionsystem

`make functionsystem` 调用 `functionsystem/run.sh build`，Python 构建入口会先执行：

1. `download_vendor(VendorList.csv, vendor/src)` 下载/解压源依赖；
2. `cache_manager.prepare_workspace()` 准备编译 vendor 缓存；
3. CMake/etcd 等实际编译。

重要：`FS_VENDOR_CACHE_DIR` 只改善后续编译缓存，**不能阻止首次 `vendor/src` 源下载**。如果 `functionsystem/vendor/src/<name>` 或 `vendor/output/Install/<name>` 已存在，下载器会跳过。

稳定策略：

```bash
export FS_VENDOR_CACHE_DIR="$PWD/.yr-cache/functionsystem-vendor-cache"
```

并保留：

```text
functionsystem/vendor/src/
functionsystem/vendor/output/
functionsystem/output/
```

如需改善首次下载，使用单独预热脚本读取 `functionsystem/vendor/VendorList.csv`，带 retry 和 sha256 校验下载并提前填充 `vendor/src/<name>`；这属于“构建前准备缓存”，不改变 `run.sh build` 命令。

### 10. frontend / dashboard

`make frontend` 主要执行 Go 构建和 `go install ...@latest`，不是 npm/pip/CMake/Bazel 主路径。风险主要是 Go `@latest` 与 toolchain 漂移，按 Go 缓存策略处理。

Dashboard 客户端存在 `package-lock.json`，其中 resolved URL 可指向 `registry.npmmirror.com`。在不改构建行为前提下，不把 `npm install` 改成 `npm ci`；只注入 npm registry/cache 环境变量。

### 11. Cargo / Rust

当前 Cargo 不是主要失败点。默认只设置 `CARGO_HOME` 到 `.yr-cache`。不要默认强制 crates mirror；如果 crates.io 失败，再临时写入 rsproxy sparse 配置：

```toml
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
```

### 12. Docker image build

`make image` 才进入 `deploy/sandbox/docker/build-images.sh`，不是 `make all` 主路径。Docker build 阶段的网络与编译容器内 env 是两套路径：镜像 pull、Dockerfile apt/pip/uv、GitHub release、download.docker.com 都需要单独验证。

策略：

- 先确认基础镜像和已存在镜像：`docker images | grep -E 'yr-|aio-yr|ubuntu'`。
- 保留 Docker build cache，除非明确磁盘回收。
- 若 Docker build 下载失败，用 BuildKit/普通 `docker build` 的网络参数单独诊断，不要以为编译容器 env 已覆盖 Dockerfile。

## 清理边界

优先清理当前工作目录下可重建缓存：

```bash
rm -rf ./.yr-cache
```

谨慎清理：

- `functionsystem/vendor/src`：源依赖缓存，删除后会重新下载 Gitee/OBS。
- `yuanrong/thirdparty`：runtime 三方件缓存，删除后 `tools/download_dependency.sh` 会重新下载。
- Docker build cache / images：可能会触发重新拉镜像和重新下载 Dockerfile 依赖。
- Docker volumes：先用 `docker system df -v` 确认名称和用途，只删除明确过期的 volume。

## 诊断口径

遇到下载失败时，先按工具归类：

- apt：系统包源，优先 `--network host`。
- pip/uv：动态 `PIP_INDEX_URL`/`UV_INDEX_URL`。
- Go：`GOMODCACHE`/`GOCACHE`/`GOPROXY`/`GOSUMDB`/toolchain。
- Maven：`mvn -gs` 才能覆盖全局 mirror。
- Bazel：`--distdir`/`--repository_cache`；以 sha256 证明等价。
- runtime thirdparty：`tools/download_dependency.sh` 和 `yuanrong/thirdparty`。
- datasystem：`DS_OPENSOURCE_DIR`。
- functionsystem：`vendor/src` 源下载与 `FS_VENDOR_CACHE_DIR` 编译缓存是两件事。
- npm：只注入 registry/cache，不改安装命令。
- Docker image：Docker build 网络单独诊断。

## 明确不要做

- 不要默认把国外 AI 代理配置进所有国内镜像下载。
- 不要用 `mvn -s` 误以为覆盖了全局 mirror；需要 `-gs`。
- 不要设置 `GOTOOLCHAIN=local` 作为全局默认。
- 不要把 `FS_VENDOR_CACHE_DIR` 误解成首次 vendor 源下载缓存。
- 不要默认删除 `functionsystem/vendor/src`、`yuanrong/thirdparty`、Docker build cache。
- 不要在“不能改构建行为”时把 `npm install` 改成 `npm ci`，或把 `go install ...@latest` 改成固定版本。
