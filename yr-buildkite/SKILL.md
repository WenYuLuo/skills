---
name: yr-buildkite
description: "Use when working with YuanRong Buildkite CI from local Codex: configure tokens, trigger Rust x86 E2E builds, watch build/job status, read logs, download artifacts, build or verify compile images, collect AI-ready evidence, or inspect optional Kubernetes/SWR/VPN diagnostics."
---

# yr-buildkite

Use this skill for local YuanRong Buildkite operations. Prefer the bundled `yr-bk` CLI instead of hand-writing Buildkite curl/jq commands.

## Setup

One-time install:

```bash
~/.codex/skills/yr-buildkite/install.sh
yr-bk init
```

Configuration uses at most two user-managed files:

```text
~/.config/yr-buildkite/config.env       # Buildkite token, defaults, optional SWR/VPN values
config/config.env.local                 # optional local migration copy, never commit
~/.config/yr-buildkite/kubekind.yaml    # optional kubeconfig for K8s diagnostics
```

`yr-bk init` creates both runtime config and the local migration copy, asks for Buildkite token, optionally copies kubeconfig, optionally configures SWR, then validates configured capabilities. Secrets are redacted by display commands. GitHub only carries `config/config.env.example`.

## Common workflows

Trigger Rust FunctionSystem x86 E2E:

```bash
yr-bk trigger rust-x86 --watch --collect
```

Observe existing build:

```bash
yr-bk status 325
yr-bk watch 325 --tail 80
yr-bk log 325 build-all --tail 100
```

Collect AI-ready evidence:

```bash
yr-bk collect 325
```

Artifacts:

```bash
yr-bk artifacts list 325
yr-bk artifacts download 325 --pattern 'artifacts/rust-fs-st/**/*'
```

Optional diagnostics:

```bash
yr-bk k8s agent-logs amd64
yr-bk vpn check
yr-bk image check swr.cn-southwest-2.myhuaweicloud.com/yuanrong-dev/compile-ubuntu2004-rust:v20260507_x86_64
```

Compile image creation and validation:

```bash
yr-bk image check IMAGE
yr-bk image smoke IMAGE
```

For build/push details, read `references/compile-image.md`.

Rust replacement E2E and A/B ST:

```bash
yr-bk trigger rust-x86 --fs-branch BRANCH --image IMAGE --watch --collect
```

For C++ baseline, Rust source replacement, and A/B matrix rules, read `references/rust-e2e-ab.md`.

## Important rules

- Treat Buildkite `failing` as active, not terminal.
- Terminal states are `passed`, `failed`, `canceled`, `blocked`, `skipped`, `not_run`.
- Never print Buildkite/GitCode/SWR tokens or WireGuard private keys.
- Do not require kubeconfig/SWR/VPN for normal Buildkite status/log/artifact commands.
- Use `yr-bk collect` before asking another AI to diagnose a failed build.

## References

For API details read `references/buildkite-api.md` only when needed.
For compile image production read `references/compile-image.md`.
For Rust FunctionSystem E2E, source replacement, C++ baseline, and A/B ST read `references/rust-e2e-ab.md`.
