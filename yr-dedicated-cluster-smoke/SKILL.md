---
name: yr-dedicated-cluster-smoke
description: Use when running the openYuanrong process-mode actor/ray smoke with YOUR OWN release package on the dedicated 3-node cluster in Huawei Cloud cn-southwest-2 (192.168.0.128/152/117, master EIP 101.245.87.142). Self-contained — deploy your 7 wheels, start, install the test framework, run the python/java/cpp/ray level-0 suites, and judge by the official analysis JSON, with every gotcha (SSH/Clash, libprotoc, pathlib backport, parallel etcd start, dash-vs-bash, maven mirror) inline.
---

# Smoke on the Dedicated openYuanrong Cluster

Everything you need to take **your own release package** → deployed on the dedicated Guiyang cluster → python/java/cpp/ray level-0 actor smoke → official pass/fail tally. No other skill or context required. Bundled scripts are in `scripts/` next to this file — set `SKILL_DIR` to this directory.

**Reference green (build 20260625, level-0):** python **79/82** (the 3 `test_sandbox_tunnel_*` fail only on a test-repo/runtime version mismatch), java 26/26, cpp 57/57, ray ~21/23.

## The cluster (fixed facts)

| Node | Internal IP | hostname | role | EIP |
|---|---|---|---|---|
| master / test host | `192.168.0.128` | test02-ylp (node1) | runs the suites, frontend/scheduler | **`101.245.87.142`** (100 Mbit/s) |
| member | `192.168.0.152` | test02-ylp-5a34 (node2) | etcd + runtime | — |
| member | `192.168.0.117` | test02-ylp-84bc (node3) | etcd + runtime | — |

- Region/account: Huawei Cloud `cn-southwest-2`; VPC `5064d3b1…`, subnet `e5d8c661…`, AZ `cn-southwest-2e`, flavor `x1.16u.32g`, Ubuntu 24.04, python `3.11` at `/usr/local/bin/python3.11`, site-packages `/usr/local/lib/python3.11/site-packages`.
- Workspace `/home/disk/yr-workspace` (on the 500G data disk mounted at `/home`). Test framework `$W=/home/workspace/openyuanrong/OpenYR_Actor_Smoke_Process_X86`.

## Step 0 — Access (do once)

You need an **authorized SSH private key**. Two keys are accepted as `root`: `~/.ssh/id_rsa_minhui` and `~/.ssh/yr-smoke-key.pem`. **Get one from the cluster owner** (or have your public key appended to `/root/.ssh/authorized_keys` on all 3 nodes). Then add SSH aliases — the whole runbook uses `yrm`/`yrn2`/`yrn3`:

```bash
cat >> ~/.ssh/config <<'EOF'
Host yrm
  HostName 101.245.87.142
  User root
  IdentityFile ~/.ssh/yr-smoke-key.pem
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
Host yrn2
  HostName 192.168.0.152
  User root
  IdentityFile ~/.ssh/yr-smoke-key.pem
  ProxyJump yrm
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
Host yrn3
  HostName 192.168.0.117
  User root
  IdentityFile ~/.ssh/yr-smoke-key.pem
  ProxyJump yrm
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
ssh yrm 'hostname; hostname -I'   # expect test02-ylp + 192.168.0.128
```

> **`kex_exchange_identification: Connection closed` on `ssh yrm`?** Your laptop's proxy (Clash Verge TUN, fake-ip `198.18.0.0/16`) is swallowing SSH to the CN EIP — `route -n get 101.245.87.142` shows `utun4`. Add to the Clash Merge profile `prepend-rules` and **force a core reload** (editing the file alone does NOT reload):
> ```yaml
> - IP-CIDR,101.245.87.142/32,DIRECT,no-resolve
> - IP-CIDR,1.95.0.0/16,DIRECT,no-resolve
> - IP-CIDR,101.245.0.0/16,DIRECT,no-resolve
> ```
> ```bash
> curl -X PUT --unix-socket /tmp/verge/verge-mihomo.sock 'http://localhost/configs?force=true' \
>   -d '{"path":"<…/clash-verge-rev/clash-verge.yaml>","force":true}'
> ```

## Step 1 — Point at YOUR package

A process-mode deploy needs **7 wheels** + (for java/cpp/ray) the **tarball**: 6 Python/runtime wheels plus `openyuanrong_cpp_sdk`. From an openeuler daily-build mirror dir (`…/x86_64/<date>/`) pick the **cp311** wheels; functionsystem is `py3-none`; sdk = `openyuanrong_datasystem_sdk` cp311; **never use `openyuanrong_full`** (it ships the Go CLI). Set URLs (or local file paths) — example for a daily build:

```bash
B='https://build-logs.openeuler.openatom.cn:38080/temp-archived/openeuler/openYuanrong/yr_daily/x86_64/20260625'
VERSION=9.9.9
WHEEL_openyuanrong="$B/openyuanrong-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
WHEEL_runtime="$B/openyuanrong_runtime-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
WHEEL_functionsystem="$B/openyuanrong_functionsystem-$VERSION-py3-none-manylinux_2_34_x86_64.whl"
WHEEL_datasystem="$B/openyuanrong_datasystem-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
WHEEL_faas="$B/openyuanrong_faas-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
WHEEL_sdk="$B/openyuanrong_datasystem_sdk-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
WHEEL_cpp_sdk="$B/openyuanrong_cpp_sdk-$VERSION-cp311-cp311-manylinux_2_34_x86_64.whl"
TARBALL="$B/openyuanrong-$VERSION.tar.gz"
```
(For a buildkite jcl build instead, resolve the OBS URLs from the build's `meta_data` `obs-urls.*`. The nodes can `curl` the openeuler mirror directly — cert trusted, fast in-region.)

## Step 2 — Deploy on all 3 nodes

```bash
for h in yrm yrn2 yrn3; do
  # 2a. install the 7 wheels (downloads on-node; pip --no-deps --force-reinstall). Big downloads:
  #     run inside a background-capable shell — do NOT let a 2-min foreground timeout kill it.
  ssh $h "WHEEL_openyuanrong='$WHEEL_openyuanrong' WHEEL_runtime='$WHEEL_runtime' \
    WHEEL_functionsystem='$WHEEL_functionsystem' WHEEL_datasystem='$WHEEL_datasystem' \
    WHEEL_faas='$WHEEL_faas' WHEEL_sdk='$WHEEL_sdk' WHEEL_cpp_sdk='$WHEEL_cpp_sdk' bash -s" < "$SKILL_DIR/scripts/node_install.sh"
  # 2b. runtime-path symlinks (wheel installs python at yr/main, cpp at yr/cpp):
  ssh $h 'python3.11 -' < "$SKILL_DIR/scripts/apply_patches.py"
  # 2c. CRITICAL for fresh daily builds: the protobuf .so ships inside site-packages/yr/ without an
  #     $ORIGIN rpath -> `yr` won't import (`ImportError: libprotoc.so.25.5.0`). Register it:
  ssh $h 'echo /usr/local/lib/python3.11/site-packages/yr > /etc/ld.so.conf.d/yr.conf; ldconfig'
  ssh $h 'yr --version'   # must print "yr version: <VERSION>", not an ImportError
done
```

`config.toml`/`services.yaml`/`metrics.json` in `/home/disk/yr-workspace` are **already correct** for this cluster (etcd `128/152/117`, per-node `node1/2/3` labels). Only touch them if you change the topology.

## Step 3 — Start the cluster (ALL 3, IN PARALLEL)

The daemon kills etcd after a ~20s quorum wait; **sequential** starts (worse via ProxyJump) stagger the nodes past that window → no quorum → all exit. Fire all 3 at once:

```bash
TS=$(date +%H%M%S)
# Clean by full argv patterns, not only `pkill -x`: Linux comm truncates long names such as
# datasystem_worker, so `pkill -x datasystem_worker` can leave the old 31501 process alive.
CLEAN='pkill -KILL -f "[y]r -c /home/disk/yr-workspace/config.toml start --master" 2>/dev/null || true; \
  pkill -KILL -f "[f]unction_master" 2>/dev/null || true; \
  pkill -KILL -f "[f]unction_proxy" 2>/dev/null || true; \
  pkill -KILL -f "[f]unction_agent" 2>/dev/null || true; \
  pkill -KILL -f "[m]eta_service" 2>/dev/null || true; \
  pkill -KILL -f "[d]atasystem_worker" 2>/dev/null || true; \
  pkill -KILL -f "[e]tcd --" 2>/dev/null || true; \
  pkill -KILL -f "[y]r_runtime_main.py|[R]untimeServer|[r]untime_manager|[g]oruntime" 2>/dev/null || true; \
  sleep 1'
for h in yrm yrn2 yrn3; do
  ssh $h "$CLEAN; cd /home/disk/yr-workspace && export MY_ENV=myenv LD_LIBRARY_PATH=:/testEnv PYTHONPATH=:/testpythonpayh && \
    setsid bash -c 'yr -c /home/disk/yr-workspace/config.toml start --master > yr-start-$TS.log 2>&1' </dev/null >/dev/null 2>&1" &
done; wait
sleep 30
ssh yrm "grep -m1 'All components are healthy' /home/disk/yr-workspace/yr-start-$TS.log"   # authoritative
ssh yrm 'E=$(python3.11 -c "import site;print(site.getsitepackages()[0])")/yr/third_party/etcd/etcdctl; \
  $E --endpoints=http://192.168.0.128:32379,http://192.168.0.152:32379,http://192.168.0.117:32379 endpoint health'  # 3 healthy
```

## Step 4 — Install the test framework for YOUR version (master only)

Needed because java/cpp use the **workspace SDK** (`$W/output/openyuanrong`), which must match your tarball. (Python uses site-packages, so a python-only run can skip 4 if the framework already exists — but still do 4d.)

> **Stale-package contamination guard (real #133 failure mode):** `auto_install_test_framework.sh`
> and the workspace can silently reuse old package artifacts already present under
> `/home/disk/yr-workspace` or `$W/output` (for example `openyuanrong-9.9.9*`),
> replacing your target package after you thought the 7 wheels were installed.
> Before and after Step 4, remove old wheel/tarball/output artifacts for non-target
> versions, then reinstall the target 7 wheels on all 3 nodes if the framework
> install touched site-packages. Do not trust master-only `pip show`.
>
> ```bash
> ssh yrm "rm -f /home/disk/yr-workspace/openyuanrong-9.9.9* /home/disk/yr-workspace/openyuanrong*9.9.9*.whl; \
>   rm -f \$W/output/openyuanrong-9.9.9* \$W/output/openyuanrong*9.9.9*.whl"
> # After framework install, verify every node:
> for h in yrm yrn2 yrn3; do
>   ssh "$h" 'python3.11 - <<PY
> import importlib.metadata as m
> for p in ["openyuanrong","openyuanrong-runtime","openyuanrong-functionsystem","openyuanrong-datasystem","openyuanrong-faas","openyuanrong-datasystem-sdk","openyuanrong-cpp-sdk"]:
>     print(p, m.version(p))
> try:
>     print("openyuanrong-sdk", m.version("openyuanrong-sdk"))
> except Exception:
>     print("openyuanrong-sdk ABSENT")
> PY'
> done
> ```
>
> If the framework output is wrong, restore it explicitly from the target tarball:
>
> ```bash
> ssh yrm "rm -rf \$W/output/openyuanrong; tar -xzf /home/disk/yr-workspace/openyuanrong-$VERSION.tar.gz -C \$W/output"
> ```

```bash
ssh yrm "curl -fsSL -o /home/disk/yr-workspace/openyuanrong-$VERSION.tar.gz '$TARBALL'"     # 4a. stage tarball
ssh yrm 'cat > /root/.m2/settings.xml <<XML
<settings><mirrors><mirror><id>aliyun</id><mirrorOf>*</mirrorOf><url>https://maven.aliyun.com/repository/public</url></mirror></mirrors></settings>
XML'                                                                                         # 4b. maven mirror (Central is unusably slow from CN); `apt-get install -y maven` if mvn missing
ssh yrm "cd \$W/OpenYuanRongTest/FunctionSystemTest/scripts/shell; rm -rf \$W/output/openyuanrong; \
  bash auto_install_test_framework.sh -w \$W -v $VERSION"                                     # 4c. bash, NOT sh (Ubuntu sh=dash)
#   Expect 'Framework is installed and configured.' Re-apply symlinks (install reinstalled site-packages):
ssh yrm 'python3.11 -' < "$SKILL_DIR/scripts/apply_patches.py"
# 4d. MANDATORY: the framework requirements.txt installs the obsolete `pathlib` backport, which shadows
#     stdlib pathlib and CRASHES every runtime spawned on the master (code:1007 faulty / code:4005 timeout)
#     -> ~20 python cases fail. Remove it (no cluster restart needed; runtimes spawn fresh per call):
ssh yrm 'python3.11 -m pip uninstall -y pathlib >/dev/null 2>&1; rm -f /usr/local/lib/python3.11/site-packages/pathlib.py; \
  python3.11 -c "import pathlib;assert \"site-packages\" not in pathlib.__file__; from yr import init; print(\"runtime import OK\")"'
# 4e. auto_install writes config.ini with the WRONG master IP -> repoint to .128:
ssh yrm 'sed -i "s/192\.168\.0\.173/192.168.0.128/g; s/192\.168\.0\.[0-9]\+:22773/192.168.0.128:22773/" /root/.yr/config.ini; \
  grep -E "server_address|master_addr" /root/.yr/config.ini | head -2'
```

### Step 4g — C++ level-0 environment prerequisites (required before C++ full smoke)

The C++ actor level-0 suite assumes a few cluster-side resources that are not guaranteed by a fresh package deploy. Without these, a correct C++ package can fail as:

- `NumaInvokeTest.cpp_numa_invoke_numa_pack`: `NUMA affinity can't be satisfied`
- `AddAffinityBasic.cpp_preffered_resource_label_exists` / `cpp_required_resource_label_exists`: no node has label key `only`
- `GetEnvTest.test_runtimeenv_working_dir_001`: `cannot find shared library file`
- `GetEnvTest.cpp_yr_workdir_instanceid_4`: `/home/snuser/<instance>` expectation not met

Apply this before starting/restarting the cluster for C++ full smoke:

```bash
for h in yrm yrn2 yrn3; do
  ssh "$h" 'bash -s' <<'REMOTE'
set -euo pipefail
TS=$(date +%Y%m%d-%H%M%S)
cp -a /home/disk/yr-workspace/config.toml /home/disk/yr-workspace/config.toml.pre-cpp-l0-env-$TS
cp -a /usr/local/lib/python3.11/site-packages/yr/cli/config.toml.jinja /usr/local/lib/python3.11/site-packages/yr/cli/config.toml.jinja.pre-cpp-l0-env-$TS
python3.11 - <<'PY'
from pathlib import Path
import socket
p=Path('/home/disk/yr-workspace/config.toml')
s=p.read_text()
if socket.gethostname() == 'test02-ylp':
    s=s.replace('INIT_LABELS = \'\'\'{"name":"node1","role":"server","number":"odd"}\'\'\'',
                'INIT_LABELS = \'\'\'{"name":"node1","role":"server","number":"odd","only":"true"}\'\'\'')
if 'numa_collection_enable' not in s:
    s=s.replace('enable_separated_redirect_runtime_std = true\ncustom_resources',
                'enable_separated_redirect_runtime_std = true\nnuma_collection_enable = true\ncustom_resources')
else:
    s=s.replace('numa_collection_enable = false', 'numa_collection_enable = true')
p.write_text(s)
j=Path('/usr/local/lib/python3.11/site-packages/yr/cli/config.toml.jinja')
j.write_text(j.read_text().replace('numa_collection_enable = false', 'numa_collection_enable = true'))
PY
mkdir -p /home/disk/yr_deploy/lib /home/snuser
chmod 755 /home/disk/yr_deploy /home/disk/yr_deploy/lib /home/snuser
# If the C++ suite has already built/copied libuser_common_func.so, put it in the runtimeEnv working_dir too.
if [ -f /home/disk/yr-workspace/libuser_common_func.so ]; then
  cp -f /home/disk/yr-workspace/libuser_common_func.so /home/disk/yr_deploy/lib/
  chmod 755 /home/disk/yr_deploy/lib/libuser_common_func.so
fi
REMOTE
done
```

After the C++ suite's ansible copy step rebuilds `/home/disk/yr-workspace/libuser_common_func.so`, refresh the working-dir copy if needed:

```bash
for h in yrm yrn2 yrn3; do
  ssh "$h" 'mkdir -p /home/disk/yr_deploy/lib /home/snuser; cp -f /home/disk/yr-workspace/libuser_common_func.so /home/disk/yr_deploy/lib/ 2>/dev/null || true; chmod 755 /home/disk/yr_deploy/lib /home/snuser /home/disk/yr_deploy/lib/libuser_common_func.so 2>/dev/null || true'
done
```

Then restart all three nodes in parallel (Step 3) and verify live agents include `--numa_collection_enable=true`.


# 4h. Java SDK libgflags self-check (needed before Java smoke): some 20260625-style tarball installs
#     can leave workspace yr-api-sdk.jar internally inconsistent: LoadUtil requires libgflags.so.2.2.2
#     but native/x86_64/so.properties omits it -> Java 0/26 with
#     "InvalidPropertiesFormatException: the hash is empty for libgflags.so.2.2.2". Check first:
ssh yrm 'J=$W/output/openyuanrong/runtime/sdk/java/yr-api-sdk-'"$VERSION"'.jar; \
  unzip -p "$J" native/x86_64/so.properties | grep -q "^libgflags.so.2.2.2=" || echo "MISSING_LIBGFLAGS_IN_JAR"'
#     If missing, rebuild/replace the SDK jar from a corrected package, or as a temporary environment
#     hotfix add output/openyuanrong/runtime/service/java/lib/libgflags.so.2.2.2 into native/x86_64/
#     and append its sha256 to so.properties; keep the original jar backup and record this as a hotfix.
#     First verify the tarball/workspace has the REAL target file, not only a broken symlink:
#       ls -l $W/output/openyuanrong/runtime/service/java/lib/libgflags.so*
#       tar -tzf /home/disk/yr-workspace/openyuanrong-$VERSION.tar.gz | grep libgflags
#     If the tarball only contains libgflags.so.2.2 -> libgflags.so.2.2.2 but omits
#     libgflags.so.2.2.2 itself, do NOT borrow a .so from an older build for black-box
#     evidence; fix/rebuild the package and rerun Java.
#     IMPORTANT: Maven-based Java smoke uses /root/.m2/.../yr-api-sdk-1.0.0.jar, not only the
#     workspace output jar. After hotfixing the workspace jar, copy/sync the same fixed jar to:
#       /root/.m2/repository/com/yuanrong/yr-api-sdk/1.0.0/yr-api-sdk-1.0.0.jar
#     Otherwise Java can remain 0/26 even when $W/output/openyuanrong/.../yr-api-sdk-*.jar is fixed.

## Step 5 — Run the suites

Run EXACTLY via the stock `run_<lang>_actor_test.sh` (they call `wwww -l 0` = level-0). Use the bundled `run_lang.sh` (already `TWS=192.168.0.128`, invokes the test script with **`bash`**). Suites take 10–30 min; run in background + poll.

```bash
scp "$SKILL_DIR/scripts/run_lang.sh" yrm:/home/disk/yr-workspace/
ssh yrm 'bash /home/disk/yr-workspace/run_lang.sh python run_python_actor_test.sh'
ssh yrm 'rm -rf /tmp/yr-jni; bash /home/disk/yr-workspace/run_lang.sh java run_java_actor_test.sh'   # java BEFORE cpp; clear JNI cache or java falsely fails 0/N
ssh yrm 'bash /home/disk/yr-workspace/run_lang.sh cpp run_cpp_actor_test.sh'                          # cpp deletes *.so incl java's libcross.so -> run cpp last
# ray-adapter (separate batch the actor smoke excludes):
ssh yrm 'W=/home/workspace/openyuanrong/OpenYR_Actor_Smoke_Process_X86; cd $W/OpenYuanRongTest/FunctionSystemTest/cases/python-actor; \
  export YR_SERVER_ADDRESS=192.168.0.128:22773 YR_DS_ADDRESS=192.168.0.128:31501 YR_MASTER_ADDRESS=192.168.0.128:22770 \
         YR_IN_CLUSTER=true MY_ENV=myenv LD_LIBRARY_PATH=:/testEnv PYTHONPATH=:/testpythonpayh; \
  wwww -l 0 -w ./ -t function -a x86_64 -i test_ray --plugin-name pytest > /home/disk/yr-workspace/actor-ray-$(date +%H%M%S).log 2>&1'
```

## Step 6 — Judge (official analysis JSON, case granularity)

```bash
ssh yrm 'f=/home/workspace/openyuanrong/OpenYR_Actor_Smoke_Process_X86/Python-Actor-Smoke-Test-Analysis-JSON.json; \
  python3.11 -c "import json;d=json.load(open(\"$f\"));print(\"total=%s success=%s failure=%s\"%(d[\"total_cases\"],d[\"success_cases\"],d[\"failure_cases\"]));[print(\"FAIL:\",c.get(\"name\")) for v in d.values() if isinstance(v,list) for c in v if str(c.get(\"result\",c.get(\"status\",\"\"))).lower() in (\"fail\",\"failed\",\"failure\",\"error\")]"'
```
Use `success_cases/total_cases` from `$W/<Python|Java|Cpp>-Actor-Smoke-Test-Analysis-JSON.json` (level-0, case granularity) — NOT `run_lang.sh`'s task ok/err or shell exit. `run_lang.sh` can return nonzero solely because uploading JSON to `http://192.168.0.128:5000/api/upload` failed after tests completed. It also counts files and includes python `-k` substring pollution. On a python task failure, check the failing func was actually a selected `@level:0` case; drop prefix-pollution `_failure` hits.


### Known non-product failures seen on the dedicated cluster

Record these before opening Rust FunctionSystem bugs:

- Buildkite #61 / test repo 20260629: `test_actor.py::test_caching_actors` can be the only Python failure because the test expects `RuntimeError` text matching `not initialized`, while the installed Python SDK raises `runtime not enable, please call yr.init() first` before any cluster/FS call. Reproduce with no cluster and no `yr.init()` to classify as SDK/test-version skew unless a C++ A/B disproves it.
- Buildkite #61 / Ray adapter: `test_ray_node_affinity.py::test_node_affinity_scheduling_strategy_001` can fail at its first `logging.info(...)` with `NameError: name 'logging' is not defined`. The file has local `import logging` in other functions but no module-level import and no import inside this function; this is a test-script scope bug before Ray/FunctionSystem behavior.

## Step 7 — Collect (optional; actor-*.log are reaped, grab promptly)

```bash
for h in yrm yrn2 yrn3; do
  ssh $h 'SD=$(ls -dt /tmp/yr_sessions/2026* | head -1); tar czf /tmp/yrlogs.tar.gz --warning=no-file-changed \
    --exclude="*/rocksdb/*" --exclude="*/third_party/etcd/*" "$SD/logs" 2>/dev/null; du -h /tmp/yrlogs.tar.gz'
  scp $h:/tmp/yrlogs.tar.gz ./node-$h-fs.tar.gz
done
ssh yrm 'tar czf /tmp/testlogs.tar.gz /tmp/test_logs 2>/dev/null'; scp yrm:/tmp/testlogs.tar.gz ./test_logs.tar.gz
```

## Gotchas (every one cost real time — read before blaming the build)

| Symptom | Cause | Fix |
|---|---|---|
| `ssh yrm` → `kex_exchange_identification: Connection closed` (nc :22 connects) | laptop Clash TUN swallows SSH to the CN EIP | Step 0 TUN fix (DIRECT rule + force core reload) |
| `yr start`/`yr --version` → `ImportError: libprotoc.so.25.5.0` | protobuf `.so` in `site-packages/yr/` not on loader path | Step 2c `ldconfig` |
| ~20 python cases fail `code:1007 instance faulty` / `code:4005 Get object timeout`; `runtime-*.out` shows `ImportError: cannot import name 'Sequence' from 'collections'` | framework `requirements.txt` installed the obsolete `pathlib` backport, shadowing stdlib → runtimes crash on the master | Step 4d `pip uninstall -y pathlib` |
| Cluster never healthy; etcd peers `connection refused`; daemons exit ~20s | sequential/staggered starts miss the 20s quorum window | Step 3 — start all 3 in PARALLEL |
| `set: Illegal option -o pipefail` / `[[: not found` | Ubuntu `sh` = dash | run with `bash`, never `sh` |
| Java SDK build crawls at kB/s | Maven Central slow from CN | Step 4b aliyun mirror |
| java 0/N | stale `/tmp/yr-jni` JNI cache | `rm -rf /tmp/yr-jni` before java (Step 5) |
| `test_sandbox_tunnel_*` → `TypeError: create() got unexpected kwarg 'upstream'` | the on-box test repo is for an older runtime version (skew) | refresh `$W/OpenYuanRongTest` to the repo matching YOUR runtime version; NOT an env fix |
| master downloads ~10× slower than members | master egress via its EIP bandwidth; members via VPC NAT | raise EIP bandwidth, or download on a member + scp internally |
| long step dies at ~2 min (agent) | foreground command timeout | run big downloads/suites detached / in a background-capable shell |

| Java/Cpp cannot start: `cmake`, `zip`, `NUMA_LIB`, or `ansible` missing | master/test host lacks full Java/Cpp toolchain | `apt-get install -y cmake zip unzip libnuma-dev ansible`; if Ansible Python deps are broken, reinstall `python3-jinja2 python3-markupsafe python3-yaml`. |
| Cpp artifact copy cannot reach nodes or points at `192.168.0.173/4/31` | test framework Ansible inventory still has stale cloned-node IPs | Patch both `opensource-3nodes-x86_64-blue-smoke` inventory files to `192.168.0.128/152/117`; generate an internal key on master and authorize it on all nodes. |
| clean restart leaves old fixed-port processes or old sessions respawn | killed child components only; parent `yr -c ... start --master` supervisor survived | kill the parent `yr` supervisor plus child components, verify no remaining FS/DS/runtime/etcd processes, then start all nodes in parallel. |
| Java 0/26 + `the hash is empty for libgflags.so.2.2.2` | workspace `yr-api-sdk-*.jar` native metadata missing `libgflags.so.2.2.2`, while `LoadUtil` requires it | Fix/rebuild SDK jar; temporary hotfix is to add `runtime/service/java/lib/libgflags.so.2.2.2` into `native/x86_64/` and append sha256 to `so.properties`, then `rm -rf /tmp/yr-jni` before rerun. |
| C++ only fails `NumaInvokeTest.cpp_numa_invoke_numa_pack`, while ordinary scheduling works | `function_agent` started with `--numa_collection_enable=false`; master plugin is enabled but agents publish no NUMA resources | Step 4g: add `numa_collection_enable = true` and restart all 3 nodes. |
| C++ only fails `AddAffinityBasic.*resource_label_exists` | no node has `INIT_LABELS` key `only`, but these cases require it | Step 4g: add `"only":"true"` to node1/master `INIT_LABELS` and restart. |
| C++ only fails `GetEnvTest.test_runtimeenv_working_dir_001` / `cpp_yr_workdir_instanceid_4` | `/home/disk/yr_deploy/lib` lacks `libuser_common_func.so`, or `/home/snuser` is missing | Step 4g: create the dirs on all nodes and copy `libuser_common_func.so` into `/home/disk/yr_deploy/lib`. |

| install/deploy mysteriously misses C++ SDK files or node_install fails with an unset cpp sdk variable | the process deploy actually needs 7 wheels, not 6 | include `WHEEL_cpp_sdk=openyuanrong_cpp_sdk-...whl` in Step 1/2. |
| historical baseline package URL returns `HTTP 403 AccessDenied` from OBS | daily/Buildkite OBS URLs may expire, become private, or require credentials even if an old runbook/env file records them | do not silently switch to a random daily package; first look for a long-lived mirror/cache with the same source commit + 7 wheels + tarball + sha256, or record a package-availability blocker. |
| remote cleanup command produces no start log and no process after `pkill -f "yr -c ... start"; ... yr -c ... start` | the `pkill -f` pattern can match the current remote shell argv because the later start command is present in the same command line, killing the shell before start | split cleanup and start into two separate `ssh` commands, or upload/run a remote script file whose argv does not contain the future start command. |
| fresh start still binds old ports (especially `31501`) after `pkill -x datasystem_worker` | Linux process `comm` truncates names longer than 15 chars, so exact-name kill misses `datasystem_worker` | use Step 3 broad `pkill -f '[d]atasystem_worker'` cleanup. |
| fresh start binds `22770/22772/22773/8403` even after cleanup | orphan Rust FS processes live under `/functionsystem/bin/function_*`; old cleanup pattern `/functionsystem/function_master` misses the inserted `bin/` path | use Step 3 broad process-name patterns `[f]unction_master`, `[f]unction_proxy`, `[f]unction_agent`; verify with `ss -ltnp` before restart. |
| etcd fails immediately with `member ... has already been bootstrapped` | a failed/retried start reused a partially bootstrapped `/tmp/yr_sessions/<ts>/third_party/etcd` data dir | kill components, remove the failed `/tmp/yr_sessions/<ts>` and `/tmp/yr_sessions/latest`, then start all nodes in parallel again. |
| `run_lang.sh` exits 1 but official JSON says all cases pass | post-test JSON upload to `192.168.0.128:5000` failed | treat official analysis JSON / collie summary as the verdict, not wrapper shell exit. |
| Ray `test_node_affinity_scheduling_strategy_001` fails immediately with `NameError: logging` | current test file lacks module/local `import logging` for that function | test-script bug before FS/Ray logic; document or refresh test repo before blaming Rust. |

**Diagnostic discipline:** if a package is green on another cluster but fails here, suspect the **environment** (almost always the pathlib backport or a stale workspace SDK), not "build gaps." Read the official analysis JSON for exact case names, then the per-runtime `runtime-*.out` (not just pytest `test_logs`) for the crash. A broad spread of unrelated cases all failing `1007`/`4005` = one shared poisoned-runtime cause, not N product bugs.

## Related
- **building-yr-smoke-ecs** — how this cluster was provisioned from scratch (whole-image clone + all setup gotchas).
- **yr-process-smoke** — the original runbook for the shared bastion cluster (`1.95.199.126`) + package-build details.
