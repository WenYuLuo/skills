# Huawei Cloud YuanRong cluster catalog

This is a routing snapshot, not a live source of truth. Refresh with
`scripts/huawei-clusters` before using a cluster.

Last verified: 2026-07-21 20:20 Asia/Shanghai. Account domain: `hwstaff_wyc`.

## CCE clusters

| Region | Cluster | Version | Verified nodes | Intended use |
|---|---|---:|---:|---|
| `cn-east-3` | `akernel-cce-monitor-32x32-east3` | v1.33 | 21 | large akernel/performance and monitoring workloads |
| `cn-north-4` | `akernel-cce` | v1.33 | 2 | smaller akernel/performance work |
| `cn-southwest-2` | `akernel-guiyang-64c128g` | v1.34 | 2 | Guiyang 64-core/128-GiB akernel work |
| `cn-southwest-2` | `cicdv2` | v1.34 | 6 | heterogeneous CI/CD workloads |
| `cn-southwest-2` | `yuanrong-for-smoke-test` | v1.34 | 2 | CCE-based YuanRong smoke work |

At the verification time all five control planes were `Available` and all 33 nodes were `Active`.
The Shanghai cluster's default pool was fixed at 19/19 and reported `MaxNodeCountReached`; existing
nodes were healthy, but the pool had no automatic scale-out headroom.

## Dedicated process-mode ECS cluster

Use `yr-dedicated-cluster-smoke` for deployment and smoke testing.

| Role | ECS | Private IP | Public access |
|---|---|---|---|
| master | `yr-smoke-node-0001` | `192.168.0.128` | EIP `101.245.87.142` |
| worker | `yr-smoke-node-0002` | `192.168.0.152` | through master/ProxyJump |
| worker | `yr-smoke-node-0003` | `192.168.0.117` | through master/ProxyJump |

The three nodes are in `cn-southwest-2`, flavor `x1.16u.32g`. An ECS `ACTIVE` result does not prove
that YuanRong daemons, etcd quorum, or a deployed release are healthy; use the smoke skill's health
gates.

## Other recognizable ECS groups

The account also contained CCE worker VMs, CI compile hosts, personal compile hosts, and several
similarly named FaaS/process groups. Do not infer cluster membership from name prefixes alone.
Refresh with `--details`, then correlate CCE node UIDs, VPC/subnet, creation time, and the intended
workflow before using or changing them.

Known public entry points at the snapshot time included:

- `vpn` in `cn-southwest-2`: `1.95.162.207`
- `yuanrong-for-smoke-test` node: `1.95.219.169`
- dedicated process smoke master: `101.245.87.142`

Re-resolve these addresses live because EIPs can be rebound.
