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
release artifacts into this skill. Do not create a second build system, package overlay convention,
Python environment, or test runner inside the VMs.

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
read-only: it checks Lima visibility, shell access, architecture, OS, disk, memory and Python.

If nodes do not exist, create them from one reviewed template with unique hostnames, addresses and
machine IDs. Cloning normally requires the source VM to be stopped. Do not clone a running node.

### 2. Verify build/runtime separation

Before deployment, prove:

- artifacts were produced outside the three runtime nodes;
- all components belong to the same build closure;
- checksums are recorded before copying;
- architecture and Python ABI match every node;
- the deployment does not depend on user-site packages or stale files from a previous run.

An incremental component build is valid when the project build graph proves closure. A hand-mixed
release assembled from unrelated builds is not valid.

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

Readiness must prove more than process existence:

- control-plane endpoint responds;
- expected node and worker count converges;
- required data and function services are healthy;
- no node is using a stale master address or stale install root;
- package and live-process identities match the release manifest.

### 6. Run existing validation

Invoke the caller-provided smoke/E2E runner unchanged. Prefer its official JSON or structured summary
over grepping a convenient success string. Archive command, exit code, start/end time, topology,
package identity and per-node logs together.

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
| Cluster orchestration | Wrong start order, stale master address, partial worker convergence | Reuse official launcher and health gate |
| Test harness | Missing dependency, wrong test revision, invalid assertion | Align the existing runner; do not change product semantics |
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
