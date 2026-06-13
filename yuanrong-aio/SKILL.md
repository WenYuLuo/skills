---
name: yuanrong-aio
description: Use to validate openYuanRong cases (SDK invoke/actor/put-get, sandbox container create+traefik routing) in a self-contained single-container AIO image — either the C++ baseline stack or the Rust-rewrite stack. Covers launching, running cases, swapping/compiling functionsystem binaries, and the readiness/cgroup gotchas. For local case verification, NOT the remote 3-node cluster (that is yr-process-smoke).
---

# yuanrong-aio: validate openYuanRong cases in a single-container AIO

Two self-contained AIO images, one per functionsystem stack. Each bundles, in one
privileged container: in-container dockerd + containerd, functionsystem
(master/proxy/agent/runtime_manager/meta_service), runtime-launcher, traefik, the
Python `yr` SDK, and the runtime image — a full control plane you can invoke against.

| Image | Stack | Built from |
| --- | --- | --- |
| `yuanrong-aio:cpp` | C++ `feature/sandbox` (authoritative baseline) | C++ functionsystem bins |
| `yuanrong-aio:rust` | Rust `rust-rewrite` (drop-in rewrite) | Rust bins in the openyuanrong wheel |

The two stacks are **decoupled** — same external behavior, different functionsystem
binaries. Pick by what you are validating: `cpp` for the oracle, `rust` for the rewrite.

**Containers are disposable** — `yr-aio.sh up` recreates a fresh one from the image in
~1 command (≈1–2 min to ready). Never treat a long-lived container as the source of
truth; the **images** are. If an image itself is missing, rebuild it: the build chain
(base → controlplane → aio) and the Rust-wheel repack recipe live in
`~/workspace/code/yr-rust/aio-verify/README.md` (§"镜像构建溯源") and
`~/workspace/code/yr-rust/aio-build/` (build scripts + evidence). `yuanrong-aio:cpp`
comes from the C++ `feature/sandbox` AIO build; `yuanrong-aio:rust` from the same chain
with the 4 Rust functionsystem bins repacked into the openyuanrong wheel.

All commands go through `scripts/yr-aio.sh` (set `SKILL_DIR` to this skill's dir, or
call it by path). Inside a container the cluster front door is **`127.0.0.1:8888`**
(traefik → frontend `8889`).

## Quickstart

```bash
S=~/workspace/skills/skills/yuanrong-aio/scripts/yr-aio.sh

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

The wheel installs the 7 bins under
`/opt/uv/python/cpython-3.10-linux-aarch64-gnu/lib/python3.10/site-packages/yr/inner/functionsystem/bin/`
(`function_master function_proxy function_agent runtime_manager domain_scheduler meta_service iam_server`).

```bash
# replace one binary built on the host, then re-deploy with it:
$S swap yrv-rust function_proxy /path/to/new/function_proxy

# or mount a host staging dir at run time, then swap from inside:
docker run -d --name yrv-rust --privileged --cgroupns host \
  -v /host/bins:/staging yuanrong-aio:rust
$S swap yrv-rust function_proxy /staging/function_proxy
```

To **compile inside** the container, mount the source tree and build there, then
`swap` the produced binary. The functionsystem Rust workspace builds with
`cargo build --release --bin <name>`; the C++ tree builds via its own `build.sh`.

`swap` and `restart` both do a `docker restart` to apply — supervisord here has no
control socket, so a `docker restart` (which re-runs the deploy with whatever bins
are in the bin dir) is the reliable way to make a new binary effective.

## Gotchas (each cost real debugging time)

- **Readiness:** after `up`/`restart`, the cluster needs ~30–120s. `127.0.0.1:8888`
  returns **502 Bad Gateway** while the backend frontend (`8889`) is still starting —
  do NOT treat a 502/any-response as ready. `yr-aio.sh wait` gates on "8889 answering
  AND 8888 not 502". A case run too early fails with `init ... 502 Bad Gateway`.
- **`--cgroupns host` is required.** Without it the in-container runc fails:
  `cannot enter cgroupv2 "/sys/fs/cgroup/docker" ... invalid state`. Two privileged
  AIOs sharing host cgroups can also clash — prefer one live AIO at a time, or expose
  different host ports and tear down idle ones.
- **Sandbox route check:** a registered sandbox port returns **502** through traefik
  (route matched, container backend) vs **404** for an unregistered path — 502 is the
  success signal here.
- **Two python paths:** the bin dir is reachable via both the `cpython-3.10` symlink
  and the `cpython-3.10.13` real dir; use the `3.10` symlink path (stable across patch).

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
baseline). See `~/workspace/code/yr-rust/aio-verify/README.md` for the human runbook
and image-build provenance.
