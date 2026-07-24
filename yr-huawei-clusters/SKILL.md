---
name: yr-huawei-clusters
description: Inventory, select, access, and health-check openYuanRong clusters in Huawei Cloud across CCE and standalone ECS. Use when Codex needs the current Huawei Cloud cluster list, CCE control-plane/node/node-pool status, ECS cluster identification, a safe target recommendation, kubeconfig or SSH access planning, or routing to the dedicated YuanRong smoke-cluster workflows.
---

# YuanRong Huawei Clusters

Treat the live Huawei Cloud API as authoritative. Use
[references/clusters.md](references/clusters.md) only to identify likely regions and cluster intent;
refresh before reporting current availability, size, IPs, or health.

## Safety

- Start read-only. Do not resize, restart, stop, delete, upgrade, reconfigure, or create resources
  unless the user explicitly requests that mutation.
- Read credentials from `HW_AK` and `HW_SK`, or from a mode-0600 credentials file. Never echo,
  log, commit, or place credentials in command arguments or generated reports.
- Treat `Available` CCE control planes and `Active` nodes as infrastructure-level health only.
  Do not claim workload health without checking Kubernetes workloads or the relevant YuanRong test.
- Resolve exact regions and resource IDs before any mutation. A similarly named ECS is not enough.

## Inventory and health

Run the bundled command from this skill directory:

```bash
scripts/huawei-clusters --region cn-east-3 --region cn-north-4 --region cn-southwest-2
```

For a full IAM project scan, omit all `--region` options. Add `--details` to show ECS names and
addresses, or `--json` for machine-readable evidence. The wrapper installs the required Huawei
Cloud SDK into a user cache on first use; set `YR_HUAWEI_PYTHON` or
`YR_HUAWEI_PYPI_INDEX_URL` to override its Python or package index.

Credential lookup order is:

1. `HW_AK` and `HW_SK` environment variables.
2. `--credentials-file PATH`.
3. `HW_CREDENTIALS_FILE`.
4. `~/.config/huawei-cloud/yr.env`.

The credentials file must contain only:

```text
HW_AK=rotated-access-key
HW_SK=rotated-secret-key
```

Require mode `0600`; do not populate it with a credential that has already been exposed in chat,
logs, or source control.

When reporting inventory, include:

- query time and successfully verified regions;
- CCE cluster phase/version and Active node counts;
- node-pool capacity warnings such as `MaxNodeCountReached`;
- ECS totals by region, explicitly noting that CCE worker VMs are included in ECS totals;
- regions that could not be verified because of permission, endpoint, or TLS errors.

## Select and access a cluster

1. Read [references/clusters.md](references/clusters.md) for cluster intent and likely access path.
2. Refresh the target region with `scripts/huawei-clusters --region REGION --details`.
3. Match the task to the smallest suitable healthy cluster; explain capacity or isolation tradeoffs.
4. For CCE workload inspection, use a temporary kubeconfig only after the user requests workload-
   level access. Keep it outside the repository, restrict its permissions, and delete it when done.
5. For standalone ECS, verify the exact instance name, private IP, EIP, and SSH key before connecting.
   Prefer the existing SSH alias or `ProxyJump` path over copying private keys.

## Route specialized work

- Run release-package actor/ray smoke on the dedicated three-node ECS cluster with
  `../yr-dedicated-cluster-smoke/SKILL.md`.
- Create or clone a new dedicated Huawei ECS smoke cluster with
  `../building-yr-smoke-ecs/SKILL.md`.
- Use `../yr-process-smoke/SKILL.md` for the shared process-mode smoke path.

Read only the one specialized skill needed for the requested operation. Keep inventory and target
selection in this skill; keep deployment and smoke-test mechanics in the specialized child.
