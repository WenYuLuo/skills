# Rust FunctionSystem E2E and A/B Validation

Use this reference when validating Rust replacements, Rust FunctionSystem ST/E2E, source replacement, or A/B comparisons.

## Core Rule

Establish a C++ baseline before fixing Rust failures.

If the C++ baseline passes under the same process, Rust failures should be treated as Rust FunctionSystem replacement issues by default. Do not modify frontend, runtime, test assertions, or other non-Rust behavior unless new evidence shows the same non-Rust root cause affects the C++ baseline.

## Buildkite Trigger

Default Rust x86 E2E:

```bash
yr-bk trigger rust-x86 --watch --collect
```

Override Rust inputs:

```bash
yr-bk trigger rust-x86 \
  --fs-repo https://gitcode.com/<owner>/yuanrong-functionsystem.git \
  --fs-branch <branch> \
  --image swr.cn-southwest-2.myhuaweicloud.com/yuanrong-dev/compile-ubuntu2004-rust:<tag> \
  --watch --collect
```

The trigger sets Buildkite env values:

- `ENABLE_RUST_FUNCTIONSYSTEM_ST=true`
- `FUNCTIONSYSTEM_REPO=<repo>`
- `FUNCTIONSYSTEM_BRANCH=<branch>`
- `RUST_BUILDER_IMAGE=<image>`
- `ENABLE_LINUX_ARM=false` unless overridden
- `ENABLE_SANDBOX_PACKAGE=false` unless overridden

## Evidence Collection

Always collect logs/artifacts before asking another AI or making code changes:

```bash
yr-bk collect <build-number>
```

Expected local shape:

```text
buildkite-artifacts/build-<number>/
├── build.json
├── jobs.tsv
├── artifacts.json
├── summary.md
├── job-logs/
└── artifacts/
```

## C++ Baseline

For baseline runs, use the same Buildkite path but point `FUNCTIONSYSTEM_REPO` and `FUNCTIONSYSTEM_BRANCH` at a C++ baseline branch. The step label may still say `Rust FunctionSystem E2E`; what matters is the replacement source used by env.

Baseline成立条件:

- Build All passes.
- FunctionSystem replacement step builds successfully.
- openYuanRong repackaging succeeds.
- `yr start` succeeds.
- Python ST/E2E reaches pytest and passes, or reaches stable business assertions.
- Logs and artifacts are saved locally.

Failures from PyPI/network/agent scheduling are not valid business baselines.

## A/B ST Design

Use dual environments:

- A: clean C++ control, unchanged package/deploy tree.
- B: same starting package shape, then replace only the agreed Rust artifacts.

Both sides use the canonical ST process under `yuanrong/test/st`:

```bash
bash test.sh -b -l cpp -f "$FILTER"
```

Use `bash test.sh -s -r` only as a debug helper when intentionally keeping one deployment alive. Do not chain debug deployment into acceptance runs.

## A/B Matrix

Track one row per case:

```text
case | A result | B result | difference category | reproducible | Rust status | cause / next lead
```

Difference categories:

- startup failure
- scheduling failure
- function execution exception
- timeout or hang
- result mismatch
- regression after a Rust fix

Cases failing in both A and B are not Rust-specific targets. Cases passing in A and failing in B are Rust convergence targets.

## Known yr.init Routing Context

If `yr.init` runs outside the cluster, it first connects to frontend. If it runs inside the cluster, it directly connects to function proxy. For `PUT /client/v1/lease` or `yr.init 404`, check actual ST location and `YR_FRONTEND_ADDRESS` / `YR_SERVER_ADDRESS` before assigning blame.
