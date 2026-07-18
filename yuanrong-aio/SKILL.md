---
name: yuanrong-aio
description: Use to validate openYuanRong SDK, FaaS, and sandbox cases in one local privileged AIO container, using a current local image or the C++/Rust compatibility aliases. Covers fresh-container launch, readiness, dynamic split-wheel paths, binary swapping, nested dockerd/runc, and macOS/Apple Silicon image checks. For single-container validation, not local multi-node smoke or the remote cluster.
---

# yuanrong-aio: validate openYuanRong cases in a single-container AIO

An AIO image bundles, in one privileged outer container: functionsystem processes,
runtime-launcher, traefik, the Python `yr` SDK, an in-container dockerd/containerd,
and the nested runtime image. Use a current locally built image directly, or the
compatibility aliases below when those historical images are available.

| `up` selector | Default image | Purpose |
| --- | --- | --- |
| `cpp` | `${YR_AIO_CPP_IMAGE:-yuanrong-aio:cpp}` | C++ baseline compatibility alias |
| `rust` | `${YR_AIO_RUST_IMAGE:-yuanrong-aio:rust}` | Rust-rewrite compatibility alias |
| any image tag | that exact tag | Current local build, for example `yr-local-aio:latest` |

When comparing C++ and Rust, keep images decoupled and judge them through the same cases.

**Containers are disposable** — `yr-aio.sh up` recreates a fresh one from the image in
~1 command (≈1–2 min to ready). Never treat a long-lived container as the source of
truth; the **images** are. Build the current source through
`deploy/sandbox/docker/build-images.sh` (base → controlplane → runtime → AIO), then run
the final image from a fresh container.

All commands go through `scripts/yr-aio.sh` (set `SKILL_DIR` to this skill's dir, or
call it by path). Inside a container the cluster front door is **`127.0.0.1:8888`**
(traefik → frontend `8889`).

## Quickstart

```bash
SKILL_DIR=/absolute/path/to/yuanrong-aio
S="$SKILL_DIR/scripts/yr-aio.sh"

$S up yr-local-aio:latest yr-local-aio-e2e  # current local image
$S up rust                 # launch yuanrong-aio:rust as container "yrv-rust", wait until READY
$S smoke yrv-rust          # canonical SDK case: init + stateless invoke + actor + put/get + negative
$S case  yrv-rust ./my.py  # run your own python case (import yr; yr.init("127.0.0.1:8888"); ...)
$S sandbox yrv-rust        # sandbox container create + traefik route check + delete
$S down  yrv-rust          # tear down

$S up cpp                  # same, against the C++ baseline (container "yrv-cpp")
```

A case is ordinary Python (see `cases/hello.py`, `cases/sdk_smoke.py`):

```python
import yr
from yr.config import Config
conf = Config(server_address="127.0.0.1:8888", is_driver=True, auto=False)
conf.in_cluster = False
yr.init(conf)

@yr.invoke
def add_one(x): return x + 1
print(yr.get(add_one.invoke(41)))   # 42
yr.finalize()
```

## Swapping / rebuilding a functionsystem binary

The script discovers the active Python and functionsystem path inside the container.
Current split wheels install bins under `yr/functionsystem/bin`; legacy full wheels may
use `yr/inner/functionsystem/bin`. Never hard-code the CPython minor/patch path.

```bash
# replace one binary built on the host, then re-deploy with it:
$S swap yrv-rust function_proxy /path/to/new/function_proxy

# or mount a host staging dir at run time, then swap from inside:
docker run -d --name yrv-rust --privileged --cgroupns host \
  -v /host/bins:/staging yuanrong-aio:rust
$S swap yrv-rust function_proxy /staging/function_proxy
```

**The AIO image has NO toolchain** (no cargo/gcc/go/cmake/bazel — runtime only).
Compilation happens in a **separate compile container** with matching architecture and
build ABI, then `swap` the produced binary into the AIO:

```bash
docker exec "$COMPILE_CONTAINER" bash -lc \
  'cd /workspace/yuanrong/functionsystem && cargo build --release --bin function_proxy'
$S swap yrv-rust function_proxy /path/to/target/release/function_proxy
```

Build (compile container) and run (AIO) are decoupled — the AIO stays a small runtime
image; `swap` bridges them. (C++ stack: build via the tree's `build.sh`, then swap.)

On macOS/Apple Silicon, keep that boundary strict: an Ubuntu 20.04 compile image is
for producing artifacts, not for runtime acceptance. Validate the resulting wheels and
binaries in the target Ubuntu 22.04/AIO image. A `libbrpc.so` error such as undefined
`pthread_mutex_init` in the compile image is usually a runtime/glibc mismatch, not proof
that the artifact itself is bad. The full environment checklist is in
`../yr-dev/references/macos-apple-silicon-aio-build.md`.

`swap` and `restart` both do a `docker restart` to apply — supervisord here has no
control socket, so a `docker restart` (which re-runs the deploy with whatever bins
are in the bin dir) is the reliable way to make a new binary effective.

## Gotchas (each cost real debugging time)

- **macOS shell:** `/bin/bash` is commonly Bash 3.2 and has no `mapfile`. Run
  `/bin/bash --version` and `bash -n deploy/sandbox/docker/build-images.sh` before a
  long image build. Host-facing scripts must use a Bash-3-compatible `while IFS= read -r`
  loop, or be invoked with an explicitly installed newer Bash.
- **Architecture:** the outer AIO image, nested runtime image, runtime-launcher, and
  downloaded tools such as Traefik must all match. Dockerfiles should consume BuildKit
  `TARGETARCH`, not hard-code `linux_amd64`. Check with
  `docker image inspect IMAGE --format '{{.Architecture}}'` before debugging startup.
- **Nested dockerd storage:** Docker Desktop can reject `overlay2` inside the privileged
  AIO with `failed to mount overlay: invalid argument`. The entrypoint is expected to
  retry with `vfs`; if `docker info` inside the AIO becomes ready with `vfs`, this is not
  a YuanRong failure. Keep `--privileged --cgroupns host`.
- **Readiness:** after `up`/`restart`, the cluster needs ~30–120s. `127.0.0.1:8888`
  returns **502 Bad Gateway** while the backend frontend (`8889`) is still starting —
  do NOT treat a 502/any-response as ready. `yr-aio.sh wait` gates only on the public
  front door returning `8888=200`; frontend may bind the node IP rather than localhost,
  so `127.0.0.1:8889` is not a portable readiness probe.
- **`--cgroupns host` is required.** Without it the in-container runc fails:
  `cannot enter cgroupv2 "/sys/fs/cgroup/docker" ... invalid state`. Two privileged
  AIOs sharing host cgroups can also clash — prefer one live AIO at a time, or expose
  different host ports and tear down idle ones.
- **Sandbox route check:** a registered sandbox port returns **502** through traefik
  (route matched, container backend) vs **404** for an unregistered path — 502 is the
  success signal here.
- **Python paths vary:** image Python versions and uv patch-directory names vary. Resolve
  paths from `Path(yr.__file__).parent`; prefer split-wheel paths and fall back to legacy
  `yr/inner` only when the image actually contains them.

## Local image integrity gates

Before accepting a locally built AIO image, check all of these:

1. The runtime image installs all split wheels required by the selected build, including
   `openyuanrong_runtime-*.whl`; the runtime service path is `yr/runtime/service`, not
   `yr/inner/runtime/service`.
2. Even when `YR_RUNTIME_IMAGE` names a custom build image, the tar embedded into AIO is
   saved with the fixed tag `aio-yr-runtime:latest`, because `services.yaml` and the
   launcher look up that name.
3. The nested image is actually loaded: `docker exec AIO docker image inspect
   aio-yr-runtime:latest` succeeds.
4. Acceptance runs from a newly built image and fresh container. A hot-patched running
   container is diagnostic evidence only.

Useful checks:

```bash
unzip -l output/openyuanrong_runtime-*.whl | grep 'yr/runtime/service'
docker image inspect "$AIO_IMAGE" --format '{{.Architecture}}'
docker exec "$AIO_CONTAINER" docker image inspect aio-yr-runtime:latest
docker inspect "$AIO_CONTAINER" --format 'oom={{.State.OOMKilled}} status={{.State.Status}}'
```

### Go host/plugin ABI gate

`goruntime`, `faasfrontend.so`, `faasscheduler.so`, and `faasmanager.so` share Go package
ABI. If shared Go packages, the Go toolchain, tags, linker flags, or `CGO_CFLAGS` change,
rebuild and repackage them as one set with the same environment. Rebuilding only frontend
can produce `plugin was built with a different version of package go.uber.org/multierr`;
rebuilding `goruntime` alone can then make an older scheduler plugin fail instead.

When assembling `pattern/pattern_faas`, merge frontend output and `go` FaaS output. Do
not replace the whole directory with frontend output, or `faasscheduler`/`faasmanager`
will disappear. The final fresh-container log gate must reject any
`plugin was built with a different version` message before SDK/FaaS/sandbox E2E is judged.

## Execution model — process vs container backend (IRON RULE)

Single-container AIO has one outer node/control plane: `yr start --master`, functionsystem,
frontend, meta service, traefik, and runtime-launcher run directly in that container. Only
functions whose service variant has `rootfs:` launch as nested runc containers through the
inner dockerd. `yr-smoke-aio` creates multiple outer AIO containers when multi-node behavior
is required.

The runtime backend is chosen **per function** by `services.yaml`:
- A python function variant **with a `rootfs:` block** (e.g. `py310`/`py39` in the stock
  image, `imageurl: aio-yr-runtime`) → **CONTAINER backend**: every instance is a *nested
  docker container* (~2–4 s to launch). This exists only for the **sandbox/traefik routing**
  tests. It is **far too slow for the functionsystem correctness/concurrency suites** —
  `task_invoke` (1000 invokes), nested invoke, batch, etc. overflow the 60 s runtime
  *connect-back* window and hang. These hangs are an **environment artifact, NOT a rust bug**
  (the same cases pass in seconds on the process-mode remote).
- A variant **without `rootfs:`** (e.g. `default`/`py311`) → **PROCESS backend**: the agent
  forks the runtime process (ms-level), same as remote.

**Rule:** the test driver's Python version selects the matching service variant. To run the
**functionsystem actor/invoke suites**, deploy with a **process-mode
`services.yaml`** — strip the `rootfs:`+`bootstrap:` blocks from the variant the driver maps
to, making it process mode like `default`. Then build the AIO image on top and run.
Only use the container backend for the sandbox-routing case. Never diagnose container-backend
"connect-back timed out / hang" as a rust bug — switch to process mode and re-judge.

## What each case proves

- `smoke` (`cases/sdk_smoke.py`): SDK init, stateless `@yr.invoke`, stateful
  `@yr.instance` actor, object `yr.put`/`yr.get` round-trip, exception propagation.
- `sandbox`: frontend `/api/sandbox/create` → real runc container via runtime-launcher,
  port-forward registered into traefik, `DELETE` cleanup.

## Relation to other skills

- `yr-process-smoke` = remote 3-node **process-mode** cluster smoke over a bastion (build
  via buildkite, deploy, run actor suites). This skill is the **local single-container**
  path for quick case validation — no remote hosts, no buildkite.
- `yr-dev` = repo/build/GitCode reference for working on the functionsystem source.

## Provenance

Built and verified 2026-06: both images pass the SDK smoke (all 5 checks) and the
sandbox create/route/delete e2e from a fresh container. The Rust image additionally
backs the rust-rewrite black-box parity result (full cpp ST 111/112, same as the C++
baseline).

The macOS/Apple Silicon local-build gates above were reverified 2026-07 with a fresh
ARM64 AIO image: SDK 5/5, FaaS 5/5, and sandbox create/delete passed; a matched sandbox
route returning 502 remained the expected routing signal.
