---
name: yr-local-3vm
description: Use when preparing, operating, deploying to, validating, or troubleshooting a reusable local three-node openYuanRong process-mode development cluster, especially Lima VMs on macOS; keeps builds outside the runtime nodes and provides generic identity, health, deployment, E2E, fault, and evidence gates for any YuanRong project
---

# YuanRong Local 3VM

Operate a reusable local three-node openYuanRong process-mode cluster without binding it to a
specific feature repository, branch, package, or test suite.

## Responsibility boundary

Use this skill for:

- creating or restoring three local Linux VM nodes;
- node lifecycle, SSH/shell access, disk and dependency health;
- deploying one coherent release set to all nodes;
- starting a master and two workers in the required order;
- running a caller-provided smoke, E2E, fault, or performance command;
- collecting reproducible identity, logs, results, and cleanup evidence.

Do not use the three runtime nodes as the default compiler. Build and package with `yr-dev`, a
dedicated Linux builder, or the repository's official CI-equivalent build path. Feed immutable
release artifacts into this skill. Do not create a second build system or package overlay convention
inside the VMs. An isolated, ABI-matching Python environment is part of deployment when the release
wheel tags require it; record its interpreter and installer identities and keep it identical on all
nodes.

## Required inputs

Before changing node state, record:

| Input | Requirement |
| --- | --- |
| Nodes | Exactly three explicit VM names; never infer arbitrary running VMs |
| Roles | One master and two workers |
| Source identity | Repository URLs, branches and commits for the release being tested |
| Release identity | Package names, versions and SHA-256 values from one coherent build |
| Platform | VM architecture, OS, Python ABI and required shared-library ABI |
| Deployment entry | Existing project installer or package manager command |
| Start/stop entry | Existing openYuanRong CLI or repository runbook |
| Test entry | Existing smoke/E2E command and its machine-readable verdict |
| Evidence root | Caller-owned output directory outside this skill |

If the package platform does not match the nodes, stop with an identity blocker. Never borrow
binaries or wheels from another build merely to make the cluster start.

## Workflow

### 1. Establish topology

Export explicit node names and run the generic health probe:

```bash
export YR_LOCAL_3VM_NODES='yr-master yr-worker-1 yr-worker-2'
~/.codex/skills/yr-local-3vm/scripts/node-health.sh
```

The first node is the master unless the caller supplies a different role mapping. The script is
read-only: it checks Lima visibility, shell access, architecture, OS, disk, memory, Python, unique
node identity and all directed inter-node network paths.

If nodes do not exist, create them from one reviewed template with unique hostnames, addresses and
machine IDs. Cloning normally requires the source VM to be stopped. Do not clone a running node.

On macOS with Lima/VZ:

- keep `LIMA_HOME` short (for example `~/.lima-yr-local-3vm`); a deeply nested workspace path can
  exceed the Unix-domain socket path limit during clone or start;
- use Lima `user-v2` networking for inter-VM traffic; default `vzNAT` can give cloned VMs the same
  `eth0` address and is not a valid three-node topology;
- configure the network while the VM is stopped, then rerun `node-health.sh`; require three unique
  primary IPv4 addresses, three unique machine IDs and all six directed ping checks;
- treat the addresses as dynamic. Discover and record them after every VM restart instead of
  hard-coding addresses from an older run.

For an existing stopped VM, the relevant Lima edit is:

```bash
limactl edit --tty=false --set='.networks = [{"lima": "user-v2"}]' NODE
```

### 2. Verify build/runtime separation

Before deployment, prove:

- artifacts were produced outside the three runtime nodes;
- all components belong to the same build closure;
- checksums are recorded before copying;
- architecture and Python ABI match every node;
- the deployment does not depend on user-site packages or stale files from a previous run.

An incremental component build is valid when the project build graph proves closure. A hand-mixed
release assembled from unrelated builds is not valid.

Wheel tags are authoritative. Ubuntu 22.04 commonly exposes Python 3.10 while a release may contain
`cp39` wheels. In that case, install a managed Python 3.9 and an isolated venv on every node rather
than trying to force the wheel into Python 3.10. A minimal `uv venv` does not include `pip`; current
Python 3.9 YuanRong CLI code may fall back to `pip._vendor.tomli`, so install `pip` in the venv before
calling `yr`. Preserve the `uv` version, Python version and installer SHA-256 in evidence. The
diagnostic signature is:

```text
ModuleNotFoundError: No module named 'tomllib'
ModuleNotFoundError: No module named 'pip'
```

### 3. Pre-clean only known runtime state

Stop the existing cluster through its official stop command. Inspect disk use and process state.
Remove only caller-declared session, log, cache, install, or test paths. Never use broad deletion,
reset a VM, or remove an unknown directory as routine cleanup.

Preserve pre-clean evidence when diagnosing a failure. Environment cleanup must not erase the only
copy of product logs.

### 4. Deploy one exact release

Use the caller's existing deployment entry. Copy the same immutable artifact set to all nodes and
verify checksums after transfer and after installation. Record installed package versions and key
plugin/binary hashes.

Do not compile on one node and copy ad hoc outputs to the others. Do not combine an old runtime,
new frontend, unrelated FunctionSystem package, or mismatched SDK unless the test explicitly studies
that compatibility combination and labels it as such.

### 5. Start in dependency order

Start the master first, wait for its control-plane readiness, then start both workers in parallel.
Use the existing project command; do not reconstruct YuanRong's process graph manually when an
official launcher exists.

Lima may inject host proxy variables into each guest. Before `yr start`, `yr status` and SDK tests,
append all three node IPs to both `NO_PROXY` and `no_proxy`. Keep the proxy for external downloads;
only bypass it for loopback and cluster traffic. Otherwise even an etcd health check against the
master's own IP can be sent through the HTTP proxy and time out with gRPC `error reading server
preface: EOF`.

```bash
YR_CLUSTER_NO_PROXY="127.0.0.1,localhost,::1,.local,${YR_MASTER_IP},${YR_WORKER1_IP},${YR_WORKER2_IP}"
export NO_PROXY="${NO_PROXY:+${NO_PROXY},}${YR_CLUSTER_NO_PROXY}"
export no_proxy="$NO_PROXY"
```

After the master is healthy, prefer the complete worker join command printed by `yr start --master`.
It must carry `values.etcd.address`, `values.ds_master.ip/port` and
`values.function_master.ip/global_scheduler_port`. Do not use the `--master_address` shorthand until
the rendered worker config proves that `ds_worker.args.master_address` is non-empty. Affected CLI
versions discover FunctionSystem correctly but derive an empty DataSystem master address, causing:

```text
master_address is required in centralized mode
```

Readiness must prove more than process existence:

- control-plane endpoint responds;
- expected node and worker count converges;
- required data and function services are healthy;
- no node is using a stale master address or stale install root;
- package and live-process identities match the release manifest.

### 6. Run existing validation

Invoke a caller-provided process-mode smoke/E2E runner unchanged. Prefer its official JSON or
structured summary over grepping a convenient success string. Archive command, exit code,
start/end time, topology, package identity and per-node logs together.

Do not point an AIO/Frontend runner at the process-mode proxy. AIO SDK smoke commonly uses
`in_cluster=False` and Frontend HTTP on port `8888`; direct process mode requires
`in_cluster=True`, FunctionProxy gRPC on port `22773`, and DataSystem on port `31501`. The wrong
contract fails during `yr.init` with `bad version`. If no process-mode runner exists, create a small
adapter under the evidence root that preserves the original assertions and changes only connection
configuration; do not edit product source or claim that the AIO runner itself passed.

For a genuine multi-node verdict, add a distribution assertion rather than relying only on
`ReadyAgentsCount`. One deterministic pattern is to keep three Actors alive concurrently, each
requesting more than half of one node's CPU capacity, and have each return its hostname. Require
three distinct expected hostnames, then terminate the Actors and verify resources return to the
baseline.

For performance A/B, keep the same nodes, packages outside the intended difference, data, warm-up,
request count, concurrency and measurement method. Report throughput, p50/p95/p99, errors, CPU and
RSS; do not select only favorable metrics.

### 7. Fault tests

Inject one declared fault at a time after a healthy baseline. Record the exact node/process stopped,
the observation window and the recovery action. Verify both business behavior and cluster state.

Do not describe an unavailable VM, full disk, broken SSH session or package mismatch as a product
fault result.

### 8. Restore or stop

At the end, either restore the documented healthy baseline or stop all nodes. Report the final state.
Do not leave an ambiguous half-running cluster for the next task.

## Failure classification

Classify before modifying product code:

| Class | Examples | Response |
| --- | --- | --- |
| Node | VM stopped, SSH/shell failure, read-only filesystem, full disk | Repair or replace node, then rerun health gate |
| Package identity | Wrong architecture/ABI/version/hash | Obtain a matching coherent release; do not patch around it |
| Runtime environment | Missing shared library, polluted Python site, stale install root | Repair deployment/runtime environment and preserve evidence |
| Cluster orchestration | Wrong start order, proxying cluster traffic, stale/empty master address, partial worker convergence | Reuse official launcher, explicit join config and health gate |
| Test harness | Missing dependency, wrong test revision, AIO/process connection mismatch, invalid assertion | Align the existing runner contract; do not change product semantics |
| Product | Same failure reproduces on a healthy, identity-matched cluster | Diagnose the product code with targeted evidence |

Three unrelated suites failing with the same runtime startup error usually indicate one shared
environment or package problem, not three independent product defects.

## Evidence contract

Every run should leave a caller-owned directory containing at least:

```text
run/
├── command.txt
├── topology.txt
├── source-identity.txt
├── release-sha256.txt
├── preflight/
├── deploy/
├── cluster-health/
├── test/
├── node-logs/
├── exit-code.txt
└── verdict.json or verdict.txt
```

This skill owns no fixed artifact directory. The invoking project chooses the evidence root.

## Reuse rules

- Read `yr-dev` for build, package, cache and GitCode workflows.
- Use `yr-buildkite` only when the selected formal build or CI evidence comes from Buildkite.
- Use remote-cluster skills for remote or cloud three-node environments; do not silently treat them
  as this local cluster.
- Keep project-specific deploy/test commands in the calling repository. Promote only genuinely
  reusable node, identity, health and orchestration knowledge back into this skill.
- Keep the reusable VMs stopped rather than deleted after a successful run unless the caller asks
  for removal. Report the exact `LIMA_HOME` and final Lima inventory.
