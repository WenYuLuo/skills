#!/usr/bin/env bash
# yr-smoke-aio: build a self-contained local multi-node openYuanRong AIO cluster and
# run the Python actor smoke suite against it. One privileged container per node
# (master + data-plane workers), each with in-container dockerd (runc runtimes).
#
#   yr-smoke-aio.sh build-bins  <rust-src> [compile-image]   # compile function_master/proxy/agent (arm64)
#   yr-smoke-aio.sh build-image <bins-dir> [base-image] [tag] # bake trio+config into a smoke image
#   yr-smoke-aio.sh up          [tag] [nodes]                # deploy master + (nodes-1) workers
#   yr-smoke-aio.sh fetch-cases <gitcode-token> [dest]       # clone/update the smoke case repo
#   yr-smoke-aio.sh prepare     <cases-dir>                  # load cases + deps + config.ini into master
#   yr-smoke-aio.sh run         [pytest-filter]              # isolated smoke run + pass/fail summary
#   yr-smoke-aio.sh status | down
#
# Env consistency: build-bins' compile image MUST match the AIO base (same arch + glibc;
# verified: arm64 / Ubuntu 22.04.5 / glibc 2.35 / cpython-3.10). A binary built there runs in the AIO.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$(cd "$HERE/../templates" && pwd)"
BIN_PATH='/opt/uv/python/cpython-3.10-linux-aarch64-gnu/lib/python3.10/site-packages/yr/inner/functionsystem/bin'
MASTER=yr-smoke-master
WPREFIX=yr-smoke-w
DEFAULT_TAG=yr-smoke-aio:local
DEFAULT_BASE=yuanrong-aio:rust
MASTER_INFO_FILE=/tmp/yr_sessions/latest/master.info

die(){ echo "ERROR: $*" >&2; exit 1; }

# --- compile the rust trio (function_master/proxy/agent) in a toolchain-matched container ---
cmd_build_bins(){
  local src="${1:?rust functionsystem source dir (checkout of rust-rewrite-sandbox)}"
  local img="${2:-compile-ubuntu2004-rust:arm64}"
  [ -d "$src" ] || die "no such rust source dir: $src"
  docker image inspect "$img" >/dev/null 2>&1 || die "compile image '$img' not found.
  Build/obtain a toolchain image matching the AIO base (arm64 / Ubuntu 22.04.5 / glibc 2.35,
  with cargo + protoc). The AIO image's own build toolchain works; otherwise any
  ubuntu:22.04 arm64 + rustup + protobuf-compiler will do."
  echo "[build-bins] compiling function_master/proxy/agent from $src ..."
  docker rm -f yr-smoke-build >/dev/null 2>&1 || true
  docker run -d --name yr-smoke-build -v "$src:/workspace" "$img" sleep infinity >/dev/null
  docker exec yr-smoke-build bash -lc '
    cd /workspace && export PROTOC=$(command -v protoc || echo /usr/bin/protoc)
    cargo build --release --bin function_master --bin function_proxy --bin function_agent' \
    || die "cargo build failed (see compile container output)"
  echo "[build-bins] done. binaries at: $src/target/release/{function_master,function_proxy,function_agent}"
  docker rm -f yr-smoke-build >/dev/null 2>&1 || true
}

# --- bake trio + config + master start-script into a smoke image ---
cmd_build_image(){
  local bins="${1:?dir containing function_master/proxy/agent (e.g. <rust-src>/target/release)}"
  local base="${2:-$DEFAULT_BASE}"; local tag="${3:-$DEFAULT_TAG}"
  for b in function_master function_proxy function_agent; do [ -f "$bins/$b" ] || die "missing $bins/$b (run build-bins first)"; done
  if ! docker image inspect "$base" >/dev/null 2>&1; then
    die "base AIO image '$base' not found.
  The base bundles dockerd+containerd, functionsystem, runtime-launcher, traefik, the yr SDK
  and the runtime image. If you don't have it: build it from the openYuanRong monorepo
  (deploy/sandbox/docker/build-images.sh -> aio image) or load a shared tarball, then re-run.
  Network for the full wheel build may be restricted; a prebuilt base tarball is the easy path."
  fi
  local ctx; ctx="$(mktemp -d)"
  cp "$bins"/function_master "$bins"/function_proxy "$bins"/function_agent "$ctx/"
  cp "$TPL/init_scheduler_args.json" "$TPL/start-master.sh" "$ctx/"
  sed "s|__BASE__|$base|" "$TPL/Dockerfile" > "$ctx/Dockerfile"
  echo "[build-image] FROM $base -> $tag"
  docker build -t "$tag" "$ctx" >/dev/null && echo "[build-image] built $tag"
  rm -rf "$ctx"
}

_wait_ready(){ local n="$1"; for i in $(seq 1 75); do
  local c; c=$(docker exec "$n" bash -lc 'curl -s -o /dev/null -w "%{http_code}" -m3 http://127.0.0.1:8888/ 2>/dev/null' 2>/dev/null)
  [ "$c" = 200 ] && { echo " $n ready (~$((i*4))s)"; return 0; }; sleep 4; done
  echo " $n TIMEOUT (last=$c)"; return 1; }

# --- deploy master + (nodes-1) data-plane workers on the default docker bridge ---
cmd_up(){
  local tag="${1:-$DEFAULT_TAG}"; local nodes="${2:-3}"
  docker image inspect "$tag" >/dev/null 2>&1 || die "image '$tag' not found (run build-image)"
  docker rm -f "$MASTER" >/dev/null 2>&1 || true
  for i in $(seq 1 9); do docker rm -f "${WPREFIX}${i}" >/dev/null 2>&1 || true; done
  echo "[up] master $MASTER"
  docker run -d --name "$MASTER" --privileged --cgroupns host "$tag" >/dev/null
  _wait_ready "$MASTER" || die "master not ready"
  local mip; mip=$(docker exec "$MASTER" hostname -i | awk '{print $1}')
  local minfo; minfo=$(docker exec "$MASTER" bash -lc "cat $MASTER_INFO_FILE" 2>/dev/null)
  [ -n "$minfo" ] || die "could not read master.info from $MASTER"
  echo "[up] master ip=$mip  workers=$((nodes-1))"
  local nums=(odd even odd even odd)
  for i in $(seq 2 "$nodes"); do
    local w="${WPREFIX}$((i-1))"; local wf; wf="$(mktemp)"
    # IMPORTANT: docker cp preserves source file mode -> chmod +x the HOST file so the
    # copied /usr/local/bin/start-yuanrong.sh is executable (else supervisord: "command
    # not executable" -> yuanrong-master FATAL -> worker never joins). Do NOT rely on
    # `docker exec chmod` between `create` and `start` (container isn't running yet).
    sed -e "s|__MASTER_INFO__|$minfo|" -e "s|__NODE_TAG__|node_tag${i}|" \
        -e "s|__NODE_NAME__|node${i}|" -e "s|__NUMBER__|${nums[$((i-1))]}|" \
        "$TPL/start-worker.sh" > "$wf"; chmod +x "$wf"
    docker create --name "$w" --privileged --cgroupns host "$tag" >/dev/null
    docker cp "$wf" "$w:/usr/local/bin/start-yuanrong.sh"; rm -f "$wf"
    docker start "$w" >/dev/null; echo "[up] worker $w (node_tag${i})"
  done
  echo "[up] waiting ~50s for workers to join..."; sleep 50
  cmd_status
}

# --- pull/refresh the smoke case repo (needs a GitCode token) ---
cmd_fetch_cases(){
  local token="${1:?gitcode token}"; local dest="${2:-$HOME/yr-smoke-cases}"
  # Adjust REPO/SUBDIR to your case source. Cases live under FunctionSystemTest/cases/python-actor.
  local repo="${YR_SMOKE_CASES_REPO:-https://oauth2:${token}@gitcode.com/<org>/OpenYuanRongTest.git}"
  if [ -d "$dest/.git" ]; then echo "[fetch-cases] updating $dest"; git -C "$dest" pull --ff-only;
  else echo "[fetch-cases] cloning -> $dest"; GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$repo" "$dest"; fi
  echo "[fetch-cases] python-actor cases:"; ls "$dest"/FunctionSystemTest/cases/python-actor/test_*.py 2>/dev/null | wc -l
}

# --- load cases + python deps + driver config.ini into the master container ---
cmd_prepare(){
  local cases="${1:?path to python-actor cases dir (has conftest.py + test_*.py)}"
  [ -f "$cases/conftest.py" ] || die "no conftest.py in $cases"
  docker exec "$MASTER" mkdir -p /opt/yrtest /root/.yr /home/sn/.yr
  ( cd "$cases" && rm -f job-*-driver.log *.log 2>/dev/null; docker cp . "$MASTER:/opt/yrtest/python-actor" 2>&1 | grep -iv "tar:" || true )
  local mip; mip=$(docker exec "$MASTER" hostname -i | awk '{print $1}')
  sed "s|__MASTER_IP__|$mip|" "$TPL/config.ini" | docker exec -i "$MASTER" bash -lc 'cat > /root/.yr/config.ini; cp /root/.yr/config.ini /home/sn/.yr/config.ini'
  docker exec "$MASTER" bash -lc 'cd /opt/yrtest/python-actor && python3 -m pip install -q pytest -r requirements.txt 2>&1 | tail -1 || python3 -m pip install -q pytest numpy pydantic fastapi xlwt xlrd xlutils 2>&1 | tail -1'
  echo "[prepare] cases + deps + config.ini ready (NOTE: test_ray_* need the framework's ray_adapter module, not bundled here)"
}

# --- run smoke isolated (per-file process), with periodic health + leftover-runtime cleanup ---
cmd_run(){
  local filter="${1:-}"; local res="${YR_SMOKE_RESULTS:-$HOME/yr-smoke-results.txt}"; : > "$res"
  mapfile -t FILES < <(docker exec "$MASTER" bash -lc "cd /opt/yrtest/python-actor && ls test_*.py" | tr -d '\r' | { [ -n "$filter" ] && grep -E "$filter" || cat; })
  local i=0 nodes; nodes=$(docker ps --format '{{.Names}}' | grep -E "^$MASTER\$|^$WPREFIX" || true)
  for f in "${FILES[@]}"; do i=$((i+1))
    local r; r=$(docker exec "$MASTER" bash -lc "cd /opt/yrtest/python-actor && YR_TEST_CONFIG_FILE=/root/.yr/config.ini timeout ${YR_SMOKE_TIMEOUT:-130} python3 -m pytest -q '$f' 2>&1 | grep -E 'passed|failed|error|no tests ran' | tail -1 | sed 's/\x1b\[[0-9;]*m//g'")
    [ -z "$r" ] && r="TIMEOUT_or_NOSUMMARY"
    printf '%3d/%d  %-44s | %s\n' "$i" "${#FILES[@]}" "$f" "$r" | tee -a "$res"
    if [ $((i % 10)) -eq 0 ]; then for n in $nodes; do
      local c; c=$(docker exec "$n" bash -lc 'docker ps -q 2>/dev/null | wc -l' 2>/dev/null)
      [ "${c:-0}" -gt 3 ] && docker exec "$n" bash -lc 'docker rm -f $(docker ps -q) >/dev/null 2>&1' 2>/dev/null || true
    done; fi
  done
  echo "=== summary ===" | tee -a "$res"
  echo "files all-pass: $(grep -cE '[0-9]+ passed' "$res" | tr -d ' ')  with-fail/err: $(grep -cE 'failed|error' "$res")  timeouts: $(grep -c TIMEOUT "$res")" | tee -a "$res"
  echo "full results: $res"
}

cmd_status(){
  docker ps --format '{{.Names}}\t{{.Status}}' | grep -E "^$MASTER|^$WPREFIX" || echo "no yr-smoke containers"
  docker exec "$MASTER" bash -lc 'curl -s -m5 http://172.17.0.4:8480/global-scheduler/resources 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(\"node_count=\",d.get(\"node_count\"))" 2>/dev/null' 2>/dev/null || true
}

cmd_down(){ docker rm -f "$MASTER" >/dev/null 2>&1 || true; for i in $(seq 1 9); do docker rm -f "${WPREFIX}${i}" >/dev/null 2>&1 || true; done; echo "torn down"; }

case "${1:-}" in
  build-bins)  shift; cmd_build_bins "$@" ;;
  build-image) shift; cmd_build_image "$@" ;;
  up)          shift; cmd_up "$@" ;;
  fetch-cases) shift; cmd_fetch_cases "$@" ;;
  prepare)     shift; cmd_prepare "$@" ;;
  run)         shift; cmd_run "$@" ;;
  status)      cmd_status ;;
  down)        cmd_down ;;
  *) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
