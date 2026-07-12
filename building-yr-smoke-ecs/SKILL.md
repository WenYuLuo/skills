---
name: building-yr-smoke-ecs
description: Use when standing up a NEW dedicated openYuanrong process-mode smoke cluster on Huawei Cloud ECS (cn-southwest-2) from scratch or by cloning existing nodes — covers provisioning via the python SDK (whole-image clone vs stock-from-scratch), what must be installed, and the ordered gotchas (Clash TUN eating SSH, cloud-init disabled in clones, data-disk remount, libprotoc ldconfig, dash-vs-bash, maven mirror, parallel etcd start, EIP bandwidth) that each cost real time.
---

# Building a YuanRong Smoke ECS Cluster from Scratch

End-to-end runbook to create a **dedicated, self-owned** 3-node process-mode smoke cluster on Huawei Cloud ECS, so you can run the actor/ray smoke at high frequency without the shared bastion + fail2ban. Once built, run smoke with the **yr-process-smoke** skill ("Cluster B" section).

**Validated 2026-06-25:** cloned the shared Guiyang nodes → 3 owned ECS (`192.168.0.128/152/117`, master EIP `101.245.87.142`); cluster healthy, full python smoke ran end-to-end (official JSON 82 cases). Every gotcha below bit in that order.

## Prerequisites

- **Credentials:** `HW_AK`/`HW_SK` for the **account that owns the smoke nodes**. Persist once (the user's interactive `export` does NOT reach the agent shell):
  ```bash
  umask 077; printf 'HW_AK=...\nHW_SK=...\n' > ~/.hwcreds; chmod 600 ~/.hwcreds
  set -a; . ~/.hwcreds; set +a   # NEVER echo HW_SK
  ```
  **The smoke nodes were in `cn-southwest-2` (贵阳), NOT `cn-north-4`** (that's a different CCE perf account). Don't assume the region — find the nodes by listing ECS across regions and matching the private IP / hostname (`ListServersDetailsRequest`). A 403/401 per-region means that region isn't subscribed for this AK/SK.
- **SDK:** `pip3 install huaweicloudsdkcore huaweicloudsdkecs huaweicloudsdkims huaweicloudsdkcbr huaweicloudsdkvpc huaweicloudsdkevs huaweicloudsdkeip huaweicloudsdkkps`.
- Auth in python: `BasicCredentials(ak,sk)` + `<Svc>Region.value_of("cn-southwest-2")`.

## Decision: clone vs from-scratch

```
Have working source node(s) in the SAME account?
  └─ yes → CLONE via whole-image (recommended): byte-identical base env, zero rebuild.
  └─ no  → from-scratch: stock image + install python3.11-from-source env + 6 wheels.
```

**Clone is overwhelmingly better** — the hard-to-reproduce layer is the python base env that `pip install --no-deps` relies on. A **whole-machine image** (system disk + data disks) captures it exactly and is **API-only** (no SSH to the source node — important, since SSH to the shared nodes is itself blocked from a laptop, see Gotcha 1).

## Clone recipe (the validated path)

Source node `.31` (an etcd member; clone it, NOT the busy master — base env is identical, framework gets installed on the new master anyway). Inspect it first: `ListServerInterfaces` → subnet `net_id`; `ShowServer` → AZ, flavor, vpc_id, image; `ListServerBlockDevices` → disks. Here: AZ `cn-southwest-2e`, flavor `x1.16u.32g`, VPC `5064d3b1…`, subnet `e5d8c661…`, disks 40G system + **500G data**, SGs `defaultyuanrong`/`ip-route`/`openyuanrong-frontend`. Check quotas (`ShowServerLimits` for cores/instances; eip `ListQuotas`) before promising N nodes.

1. **Whole image (needs CBR):** create a CBR vault sized ≥ sum of disks associated to the source, then `ImsClient.create_whole_image(CreateWholeImageRequestBody(name, instance_id=<src>, vault_id))`. Poll `show_job` → `entities.image_id`, wait `status=active`. A system-disk-only image would MISS the 500G data disk (where workspace/configs live) — only whole-image is safe when blind to the FS layout.
2. **Keypair:** `KpsClient.create_keypair` → save private key to `~/.ssh/yr-smoke-key.pem` (0600) **once** (returned only once). Use it as `key_name` so you own access.
3. **CreatePostPaidServers** ×3 from the image into the SAME subnet/AZ/flavor, `security_groups`=the 3 SG ids, `key_name`, `extendparam.charging_mode=postPaid`. Poll each `show_server` → ACTIVE + private IP. Data disk auto-restores from the whole image.
4. **EIP:** `create_publicip` (e.g. `5_bgp`, **size ≥ 100 Mbit/s** — see Gotcha 8) bound to the master's NIC `port_id` via `update_publicip`. One EIP on the master is enough; reach the other two via ProxyJump on the internal subnet.

## What must be installed / fixed on the cloned nodes (in order)

Each is a real gotcha that blocked startup until fixed:

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 1 | **Every** SSH to any node EIP: `kex_exchange_identification: Connection closed` (TCP connects, no banner). github SSH fine, `nc host 22` connects. | **Laptop's Clash Verge TUN** (fake-ip `198.18.0.0/16`, `utun4`) swallows SSH to CN EIPs. Not the node, not fail2ban, not the image. | Add `IP-CIDR,<eip>/32,DIRECT,no-resolve` + `1.95.0.0/16` + `101.245.0.0/16` to the Clash **Merge** `prepend-rules`, then **force core reload**: `curl -X PUT --unix-socket /tmp/verge/verge-mihomo.sock 'http://localhost/configs?force=true' -d '{"path":"<clash-verge.yaml>","force":true}'`. Editing the file alone does NOT reload the running mihomo. |
| 2 | New keypair (`yr-smoke-key`) rejected; only the baked-in source key works | **cloud-init is DISABLED** in a manually-managed clone → key injection + any `user_data` never run | Use the **source node's existing key** (baked in `authorized_keys`) to get in; then append your pubkey manually (`ssh-keygen -y -f key.pem >> /root/.ssh/authorized_keys`). Don't rely on `user_data` / reinstall-with-cloudinit on such images. |
| 3 | `/home/disk/yr-workspace` empty; data disk `vdb` present but **not mounted** | Whole-image restore gives the data volume a **new UUID** → fstab (UUID-based) doesn't mount it | Find original mountpoint by content (here the disk root holds `disk/`,`yuanrong/`,`sn/` → it mounts at `/home`, so `/home/disk/...` resolves). `mount /dev/vdb1 /home`; persist: `echo "UUID=$(blkid -s UUID -o value /dev/vdb1) /home ext4 defaults 0 2" >> /etc/fstab`. |
| 4 | `yr start` → `ImportError: libprotoc.so.25.5.0: cannot open shared object file` (CLI can't even import) | Fresh daily-build wheels link protobuf 25.5 `.so` shipped **inside** `site-packages/yr/` but the build's `.so` lacks an `$ORIGIN` rpath; not on loader path | `echo /usr/local/lib/python3.11/site-packages/yr > /etc/ld.so.conf.d/yr.conf; ldconfig` on every node. ("not a symbolic link" warnings are harmless.) Then `yr --version` imports. |
| 5 | Framework/test scripts: `set: Illegal option -o pipefail`, `[[: not found` | **Ubuntu `sh` = dash.** The scripts are bash | Invoke with **`bash script.sh`**, never `sh`. (`run_lang.sh` uses `bash "$script"`; `auto_install_test_framework.sh` must be run with `bash`.) |
| 6 | Java SDK build (`auto_install`) crawls at 6–38 kB/s from `repo.maven.apache.org` | Maven Central is slow/unreliable from CN; mvn doesn't use the system proxy | `~/.m2/settings.xml` mirror → `https://maven.aliyun.com/repository/public`. Also `apt-get install -y maven` (clone of an etcd member lacks mvn; the master had it). JDK8 is already present. |
| 7 | Cluster never reaches "All components are healthy"; etcd peers `connection refused`; daemons exit ~20s | **Sequential** node starts (worse via ProxyJump latency) stagger the 3 etcds past the daemon's ~20s quorum wait → windows don't overlap | **Start all 3 `yr start --master` in PARALLEL** (background each ssh locally, then `wait`). Then etcd forms quorum in seconds. |
| 8 | Master downloads (wheels/tarball) ~10× slower than the other two nodes | Master goes out via its **EIP at the bandwidth you set** (10 Mbit/s default); the no-EIP nodes go via the VPC **NAT gateway** (much faster) | Set EIP bandwidth ≥ 100 Mbit/s (`update_bandwidth`), or download on a NAT node and scp internally. |

| 9 | Smoke runs but ~20 cases fail with `code:1007 … the instance is faulty because the function-agent or runtime-manager exits` / `code:4005 Get object timeout`; per-runtime `runtime-*.out` shows `ImportError: cannot import name 'Sequence' from 'collections'` in `pathlib.py` | The framework's `auto_install` `pip install -r requirements.txt` pulls the **obsolete PyPI `pathlib` backport** (v1.0.1) into `site-packages/pathlib.py`, shadowing stdlib pathlib; `from collections import Sequence` is invalid on py3.10+ → **every runtime spawned on the test host crashes on import** → instances faulty. Only cases whose instances land on that node fail (intermittent-looking). | **After every framework install: `pip uninstall -y pathlib; rm -f <site-packages>/pathlib.py`** on the test host (verify `python3.11 -c 'import pathlib;print(pathlib.__file__)'` → stdlib, and `python3.11 -c 'from yr import init'` → OK). No cluster restart needed (runtimes spawn fresh per invocation). |

Plus the standard yr-process-smoke deploy adaptations: re-apply runtime symlinks (`apply_patches.py`) after any wheel reinstall; re-IP `config.toml` etcd addresses + per-node `INIT_LABELS`/`custom_resources`; after a framework install, `config.ini` is written with the wrong master IP → `sed` it to the new master.

**Diagnosing case failures (don't trust the "known build gaps" excuse):** if the same build is green on another cluster, it's almost certainly the environment. Read the **official `*-Analysis-JSON.json`** for the exact failing case names, then the **per-runtime `runtime-*.out`** (not just the pytest `test_logs`) for the import/crash that kills the instance. A broad spread of unrelated cases failing (serialization + put/get + wait + …) all with `code:1007`/`4005` points at one shared cause (a poisoned runtime spawn), not N separate product bugs. Test-code `TypeError` (e.g. `create() got an unexpected keyword argument 'upstream'`) is a **test-repo vs runtime version skew** — the test repo copied from the 0.7.0 node doesn't match a 9.9.9 runtime; get the matching-version test repo, don't "fix" the env.

## Orchestration gotchas (agent-side)

- **Long steps die on the 2-min Bash timeout.** Downloading 350 MB of wheels ×3 or a 1 GB tarball exceeds it. Run such work inside a **`run_in_background` Bash** (keeps ssh alive, no timeout, notifies on completion) or `nohup` on the node with a self-contained script (env-passing through `setsid`/nested quotes is fragile — bake values into the script).
- **`pgrep -f "pip install"` self-matches** your own poller's ssh command line → false "RUNNING". Detect completion by a log sentinel (`INSTALL_COMPLETE`) or a fresh binary mtime, not by `pgrep -f` of a generic string.

## Verify

```bash
ssh yrm 'grep -m1 "All components are healthy" /home/disk/yr-workspace/yr-start-*.log'
ssh yrm '<sp>/yr/third_party/etcd/etcdctl --endpoints=http://N1:32379,http://N2:32379,http://N3:32379 endpoint health'  # 3 healthy
for h in yrm yrn2 yrn3; do ssh $h 'echo fm=$(pgrep -xc function_master) etcd=$(pgrep -xc etcd)'; done  # all 1
```
Then run a smoke round (yr-process-smoke skill) and judge by the official `*-Actor-Smoke-Test-Analysis-JSON.json`. Known rust-FS gaps in some daily builds (anti-affinity, `test_yr_resource`/`test_gang_suspend_1` 3002, `test_wait` partition) fail at case level and are **build** issues, not the new environment.

## Teardown / cost

3× `x1.16u.32g` + 40G+500G EVS each + 1 EIP are billed continuously in a shared team account. Delete with `DeleteServersRequest(delete_volume=True, delete_publicip=False)`; release the CBR vault + whole image when no longer cloning. The throwaway stock helper node (if built for Gotcha 1 diagnosis) is not needed once Clash is fixed.

## Related
- **yr-process-smoke** — run the actor/ray smoke (see its "Cluster B" section for this cluster's access).
- **scaling-huawei-cce-nodes** — the CCE (k8s) path; different from these standalone ECS.
- State of the built cluster is saved in `~/.yr-smoke-clone.json` (ids, IPs, EIP, vault, image).
