#!/usr/bin/env bash
# yr-aio.sh — drive the self-contained openYuanRong AIO images (C++ or Rust stack)
# to validate cases. Encodes the hard-won gotchas (readiness gate, bin path,
# restart-to-apply). Works for both AI and humans.
#
# Usage:
#   yr-aio.sh up    <cpp|rust|image> [name] [host_port] # launch a fresh AIO container
#   yr-aio.sh wait  <name>                          # block until the cluster is READY
#   yr-aio.sh smoke <name>                          # run the canonical SDK smoke case
#   yr-aio.sh case  <name> <host_script.py>         # run an arbitrary python case inside
#   yr-aio.sh sandbox <name> [sbx_name] [port]      # sandbox create + traefik route + delete
#   yr-aio.sh swap  <name> <bin> <host_file>        # replace a functionsystem binary + apply
#   yr-aio.sh restart <name>                        # docker restart + wait (apply new bins)
#   yr-aio.sh shell <name>                          # interactive shell inside
#   yr-aio.sh logs  <name>                          # tail the functionsystem deploy log
#   yr-aio.sh down  <name>                          # remove the container
#
# Inside the container the cluster front door is 127.0.0.1:8888 (traefik → frontend 8889).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

image_for() {
  case "$1" in
    cpp)  echo "${YR_AIO_CPP_IMAGE:-yuanrong-aio:cpp}" ;;
    rust) echo "${YR_AIO_RUST_IMAGE:-yuanrong-aio:rust}" ;;
    *)    echo "$1" ;;
  esac
}

bin_path_for() {
  local name="${1:?name}"
  docker exec "$name" python3 -c '
from pathlib import Path
import yr
root = Path(yr.__file__).resolve().parent
for rel in ("functionsystem/bin", "inner/functionsystem/bin"):
    candidate = root / rel
    if candidate.is_dir():
        print(candidate)
        raise SystemExit(0)
raise SystemExit(f"functionsystem bin directory not found below {root}")
'
}

cmd_up() {
  local stack="${1:?stack cpp|rust, or an image tag}"
  local default_name="yrv-local"
  [ "$stack" = "cpp" ] && default_name="yrv-cpp"
  [ "$stack" = "rust" ] && default_name="yrv-rust"
  local name="${2:-$default_name}"; local port="${3:-}"
  local image; image="$(image_for "$stack")"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "image $image not found. Build/load it first (see SKILL.md)." >&2; exit 1
  fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  local pflag=()
  [ -n "$port" ] && pflag=(-p "${port}:8888")
  # --cgroupns host is REQUIRED: private cgroupns makes the in-container runc fail
  # with "cannot enter cgroupv2 /sys/fs/cgroup/docker". Two privileged AIOs sharing
  # host cgroups can also clash — prefer one live AIO at a time.
  docker run -d --name "$name" --privileged --cgroupns host "${pflag[@]}" "$image" >/dev/null
  echo "launched $name from $image${port:+ (host port $port → 8888)}"
  cmd_wait "$name"
}

cmd_wait() {
  local name="${1:?name}"
  echo -n "waiting for cluster ready in $name "
  docker exec "$name" bash -lc '
    for i in $(seq 1 90); do
      # READY signal = traefik front door (8888) reaches its backend → HTTP 200.
      # While the frontend is still starting, 8888 returns 502; before traefik is
      # up, 000. (Do NOT probe 127.0.0.1:8889 — the frontend binds the node IP,
      # not localhost, so it always reads 000.)
      code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8888/ 2>/dev/null)
      if [ "$code" = "200" ]; then echo " ready (8888=200)"; exit 0; fi
      sleep 3
    done
    echo " TIMEOUT (cluster not ready after ~270s; last 8888=$code)"; exit 1
  '
}

cmd_smoke() {
  local name="${1:?name}"
  docker cp "$SKILL_DIR/cases/sdk_smoke.py" "$name:/tmp/yr_sdk_smoke.py"
  docker exec "$name" bash -lc 'YR_SMOKE_SERVER_ADDRESS=127.0.0.1:8888 python3 /tmp/yr_sdk_smoke.py'
}

cmd_case() {
  local name="${1:?name}"; local script="${2:?host python script}"
  [ -f "$script" ] || { echo "no such file: $script" >&2; exit 1; }
  docker cp "$script" "$name:/tmp/yr_case.py"
  docker exec "$name" bash -lc 'YR_SMOKE_SERVER_ADDRESS=127.0.0.1:8888 python3 /tmp/yr_case.py'
}

cmd_sandbox() {
  local name="${1:?name}"; local sbx="${2:-sbx-demo}"; local port="${3:-8080}"
  docker exec "$name" bash -lc "
    IP=\$(hostname -i | awk '{print \$1}')
    echo '--- create ---'
    curl -s -m 60 -X POST http://\$IP:8889/api/sandbox/create -H 'Content-Type: application/json' \
      -d '{\"name\":\"$sbx\",\"namespace\":\"default\",\"runtime\":\"python3.10\",\"ports\":[\"$port\"]}' | head -c 200
    echo; sleep 4
    echo '--- container ---'; docker ps --format '{{.Names}}\t{{.Status}}' | grep $sbx || true
    echo '--- traefik route (502 = matched, container backend) ---'
    curl -s -o /dev/null -w '%{http_code}\n' -m 8 http://127.0.0.1:8888/default-$sbx/$port/
    echo '--- delete ---'
    curl -s -m 30 -X DELETE http://\$IP:8889/api/sandbox/default-$sbx | head -c 120; echo
    sleep 5; docker ps -a --format '{{.Names}}' | grep $sbx || echo 'container cleaned'
  "
}

cmd_swap() {
  local name="${1:?name}"; local bin="${2:?bin e.g. function_proxy}"; local file="${3:?host binary file}"
  local bin_path
  [ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }
  bin_path="$(bin_path_for "$name")"
  docker cp "$file" "$name:$bin_path/$bin"
  docker exec "$name" chmod +x "$bin_path/$bin"
  echo "copied $file → $name:$bin_path/$bin"
  cmd_restart "$name"
}

cmd_restart() {
  local name="${1:?name}"
  # supervisord here has no control socket, so a targeted restart isn't available;
  # docker restart re-runs the deploy with whatever bins are now in place.
  docker restart "$name" >/dev/null
  echo "restarted $name (re-deploying with current bins)"
  cmd_wait "$name"
}

cmd_shell() { docker exec -it "${1:?name}" bash; }

cmd_logs() {
  docker exec "${1:?name}" bash -lc 'tail -n 40 -f $(ls -t /tmp/yr_sessions/*/log/*function_proxy* 2>/dev/null | head -1)'
}

cmd_down() { docker rm -f "${1:?name}" >/dev/null && echo "removed ${1}"; }

sub="${1:-}"; shift || true
case "$sub" in
  up)      cmd_up "$@" ;;
  wait)    cmd_wait "$@" ;;
  smoke)   cmd_smoke "$@" ;;
  case)    cmd_case "$@" ;;
  sandbox) cmd_sandbox "$@" ;;
  swap)    cmd_swap "$@" ;;
  restart) cmd_restart "$@" ;;
  shell)   cmd_shell "$@" ;;
  logs)    cmd_logs "$@" ;;
  down)    cmd_down "$@" ;;
  *) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
