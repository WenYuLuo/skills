# YuanRong Compile Image Workflow

Use this reference when asked how to create, update, validate, or publish YuanRong compile images.

## Current Strategy

Prefer an overlay image over a full toolchain rebuild:

1. Start from a known-good compile image.
2. Replace only the tool that must change, for example CMake.
3. Validate tool versions in the Dockerfile.
4. Build/push with `docker buildx`.

This avoids repeatedly downloading and rebuilding Python, Go, JDK, Bazel, Node.js, and other large toolchain parts.

## Key Image Inputs

- Registry: `swr.cn-southwest-2.myhuaweicloud.com`
- Namespace example: `yuanrong-dev`
- Image example: `compile-ubuntu2004`
- Rust builder image example: `swr.cn-southwest-2.myhuaweicloud.com/yuanrong-dev/compile-ubuntu2004-rust:v20260507_x86_64`

## Minimal Overlay Dockerfile Pattern

```dockerfile
ARG BASE_IMAGE=swr.cn-southwest-2.myhuaweicloud.com/yuanrong-dev/compile-ubuntu2004:v20260427_obs_sdk
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG CMAKE_VERSION=3.31.10

ENV CMAKE_HOME=/opt/buildtools/cmake
ENV PATH=/opt/buildtools/cmake/bin:${PATH}

RUN set -e; \
    if [ "$TARGETARCH" = "amd64" ]; then CMAKE_ARCH="x86_64"; else CMAKE_ARCH="aarch64"; fi; \
    tmp_dir="$(mktemp -d)"; \
    cd "$tmp_dir"; \
    curl -fsSL \
      "https://openyuanrong.obs.cn-southwest-2.myhuaweicloud.com/thirdparty/github.com/Kitware/CMake/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz" \
      -o cmake.tar.gz; \
    tar -xzf cmake.tar.gz -C /opt/buildtools; \
    rm -rf /opt/buildtools/cmake; \
    mv "/opt/buildtools/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}" /opt/buildtools/cmake; \
    ln -sf /opt/buildtools/cmake/bin/cmake /usr/local/bin/cmake; \
    cmake --version | grep -q "version ${CMAKE_VERSION}"; \
    rm -rf "$tmp_dir"
```

## Buildx Build/Push

```bash
cd ci/ubuntu
docker login swr.cn-southwest-2.myhuaweicloud.com

IMAGE_NAME=swr.cn-southwest-2.myhuaweicloud.com/yuanrong-dev/compile-ubuntu2004 \
TAG=vYYYYMMDD_toolchange \
PLATFORMS=linux/amd64,linux/arm64 \
PUSH=true \
./build.sh
```

Important SWR compatibility flags:

```bash
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
docker buildx build \
  --platform "$PLATFORMS" \
  -t "$IMAGE_NAME:$TAG" \
  -f Dockerfile.ubuntu2004 \
  --provenance=false \
  --sbom=false \
  --push .
```

Huawei SWR may reject OCI attestations with `400 Bad Request`; keep `--provenance=false --sbom=false`.

## Local Smoke Checks

Use the bundled helper:

```bash
yr-bk image check "$IMAGE"
yr-bk image smoke "$IMAGE"
```

Expected smoke output should include versions for Rust/Cargo when using Rust builder images, plus GCC and CMake.

## When Updating Buildkite

After publishing an image, pass it explicitly first:

```bash
yr-bk trigger rust-x86 --image "$IMAGE" --watch --collect
```

Only change default config after the image has a successful Buildkite run or a clearly understood failure unrelated to the image.
