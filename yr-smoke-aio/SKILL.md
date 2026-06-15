---
name: yr-smoke-aio
description: Use to stand up a self-contained LOCAL multi-node openYuanRong cluster (master + data-plane workers, each a privileged AIO container with in-container dockerd/runc runtimes) and run the Python actor SMOKE suite against the Rust-rewrite functionsystem — build the image (AIO base + current rust binaries built via yr-dev), deploy the cluster, pull/refresh cases, run isolated, collect pass/fail. For cluster smoke verification with fast local iteration; complements yuanrong-aio (single-container simple commands) and yr-process-smoke (remote 3-node cluster).
---

# yr-smoke-aio: local multi-node openYuanRong cluster smoke

Stand up a faithful **multi-node** openYuanRong cluster on one machine — 1 master + N data-plane
workers, each a privileged AIO container (in-container dockerd + containerd, functionsystem,
runtime-launcher, traefik, the `yr` SDK, runtime image) — then run the real Python actor smoke
cases against it. Lets you reproduce remote 3-node behaviours and validate Rust functionsystem
fixes with **minutes-level** iteration (compile ~40-90s via yr-dev, redeploy ~1-2min) instead of the
~55min remote fat-wheel build.

`scripts/yr-smoke-aio.sh` is the orchestrator (run with no args for usage).

## Dependencies (honest)
- **GitCode token** — one token covers both the smoke **cases** (OpenYuanRongTest) and the **rust
  source** (`yuanrong-functionsystem @ rust-rewrite-sandbox`) you build the binaries from (via yr-dev).
- **Two Docker images** (NOT pulled by a token):
  - AIO **base** image (default `yuanrong-aio:rust`, ~4GB) — the full single-container stack.
  - A **compile** image (default `compile-ubuntu2004-rust:arm64`) — cargo + protoc, arch/glibc-matched.
  - If you DON'T have them, `build-image`/`build-bins` print build guidance. The base can be built
    from the monorepo `deploy/sandbox/docker/build-images.sh` (the aio target) or loaded from a
    shared tarball; the full wheel build may need network not always available, so a prebuilt
    base tarball is the easy path. (The compile image is yr-dev's concern; any arm64 ubuntu:22.04 + rustup + protobuf-compiler works.)
- Network for `pip` (numpy/pydantic/fastapi/xlwt…) is assumed.

**Compilation is NOT this skill's job.** Build the 4 binaries (function_master/proxy/agent +
domain_scheduler) with the **yr-dev** skill (network-stable Cargo build in the compile image,
`.yr-cache`, dynamic env per `yr-dev/references/build-network-robustness.md`), then feed
`<rust-src>/target/release` to `build-image`. **Consistency rule:** the compile image and AIO base
must share arch + OS + glibc + python (verified: arm64 / Ubuntu 22.04.5 / glibc 2.35 / cpython-3.10)
so binaries run unchanged in the AIO. **Language replacement** — when fixing any bug/feature in the
rust binaries, mirror the C++ baseline (openYuanRong `feature/sandbox`), don't invent.

## Workflow
```bash
S=scripts/yr-smoke-aio.sh
# 0. (yr-dev) compile the 4 binaries from your rust-rewrite-sandbox checkout -> <src>/target/release
#    function_master / function_proxy / function_agent / domain_scheduler
# 1. bake the 4 binaries + smoke config into an image FROM the AIO base
$S build-image ~/src/yuanrong-functionsystem/target/release  yuanrong-aio:rust  yr-smoke-aio:local
# 2. deploy master + 2 workers (3-node)
$S up          yr-smoke-aio:local  3
# 3. pull the smoke cases (set YR_SMOKE_CASES_REPO to your repo url, or edit fetch-cases)
$S fetch-cases <GITCODE_TOKEN>  ~/yr-smoke-cases
# 4. load cases + deps + driver config.ini into the master
$S prepare     ~/yr-smoke-cases/FunctionSystemTest/cases/python-actor
# 5. run the suite isolated (optional pytest filename filter), get pass/fail summary
$S run                                                   # all; or:  $S run 'test_yr_resource|test_actor'
$S status      # node_count + containers
$S down        # teardown
```
Driver wiring (what `prepare` writes to `~/.yr/config.ini` + `/home/sn/.yr/config.ini`, `[python]`):
`server_address=<master-ip>:22773` (proxy gRPC), `master_addr=<master-ip>:22770` (master gRPC),
`datasystem_address=<master-ip>:31501`, `in_cluster=true`. The SDK derives master HTTP :8480 itself.

## Gotchas (each one cost a debugging cycle — keep them)
1. **docker cp drops the +x bit.** Worker `start-yuanrong.sh` MUST be executable; `up` chmods the HOST
   file before `docker cp` (cp preserves source mode). Never `docker exec chmod` between `create` and
   `start` — the container isn't running yet, exec fails, the bit stays off, supervisord reports
   `command not executable` → `yuanrong-master FATAL` → the worker silently never joins.
2. **Disable the faas function_scheduler** (`--enable_function_scheduler false`, baked into start-master.sh).
   It needs a cluster-specific `init_scheduler_args.json`; the bundled one is a placeholder and an
   enabled scheduler with a mismatched config loops/exits → drags the whole deploy down. Actor smoke
   doesn't use it.
3. **Env inheritance into runc runtimes.** Deploy-time env (MY_ENV/LD_LIBRARY_PATH/PYTHONPATH) only
   reaches actors if (a) it's exported before `yr start` (done in start-*.sh) AND (b) the rust
   `--enable_inherit_env true` path is honored in the CONTAINER backend. The container backend
   (`runtime_manager/runtime_ops.rs::start_container_instance`) historically only folded `req.env_vars`
   and skipped the process-env inheritance the process-mode `executor::build_runtime_env` does — fix it
   to mirror process-mode (then getenv/label-dependent cases pass).
4. **Per-node custom_resources/labels** must match what the cases assert (node_tag1/2/3, name/role/
   number/only) — see start-master.sh / the worker template; mirror the remote `do_deploy.sh`.
5. **Test isolation.** Run each test FILE in its own pytest process (`run` does). Actor runtimes can
   linger as inner runc containers and accumulate → resource pressure → false timeouts. `run` cleans
   leftover inner containers every 10 files and re-checks node_count; tighten to per-file if you see
   borderline flakiness.

## Known boundaries
- `test_ray_*` (Ray-adaptor) need the framework's `ray_adapter` module (not in the case dir / not
  bundled) — set that up separately or skip with a filter.
- **anti-affinity / gang**: the rust scheduler doesn't yet wire `schedule_affinity` → `AffinityContext`
  (the label-affinity filter/scorer plugins exist+registered but get an empty context), so REQUIRED
  anti-affinity / gang co-scheduling don't spread across nodes. That's rust scheduler feature-debt
  (mirror C++ `parse_helper.cpp::ParseAffinityFromCreateOpts` + the scheduler_framework), not an
  environment issue. resources/spread/affinity-colocation cases do pass.
- AIO uses **containerized (runc) runtimes** vs the remote **process-mode** — a known model difference;
  most cases align once env/labels are wired (gotcha #3/#4), the rest is scheduler debt above.
