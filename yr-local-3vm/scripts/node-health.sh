#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: node-health.sh [node1 node2 node3]

Nodes may instead be supplied through YR_LOCAL_3VM_NODES as a space-separated list.
The probe is read-only and requires exactly three existing Lima instances.
EOF
  exit 2
}

if [[ $# -gt 0 ]]; then
  nodes=("$@")
elif [[ -n "${YR_LOCAL_3VM_NODES:-}" ]]; then
  read -r -a nodes <<<"$YR_LOCAL_3VM_NODES"
else
  usage
fi

[[ ${#nodes[@]} -eq 3 ]] || {
  echo "ERROR: expected exactly three node names, got ${#nodes[@]}" >&2
  exit 2
}
command -v limactl >/dev/null 2>&1 || {
  echo "ERROR: limactl is not installed or not on PATH" >&2
  exit 1
}

echo "=== Lima inventory ==="
limactl list

failed=0
for node in "${nodes[@]}"; do
  echo
  echo "=== $node ==="
  if ! limactl shell "$node" -- bash -lc '
    set -e
    printf "hostname="; hostname
    printf "arch="; uname -m
    if [ -r /etc/os-release ]; then . /etc/os-release; printf "os=%s %s\n" "${NAME:-unknown}" "${VERSION_ID:-unknown}"; fi
    df -Pk / | awk "NR==2 {printf \"root_kb_total=%s root_kb_used=%s root_kb_available=%s root_use=%s\\n\", \$2, \$3, \$4, \$5}"
    if command -v free >/dev/null 2>&1; then free -m | awk "/^Mem:/ {printf \"memory_mb_total=%s memory_mb_available=%s\\n\", \$2, \$7}"; fi
    if command -v python3 >/dev/null 2>&1; then python3 -c "import platform,sys; print(\"python=\"+platform.python_version()); print(\"python_executable=\"+sys.executable)"; else echo "python=missing"; fi
  '; then
    echo "ERROR: health probe failed for $node" >&2
    failed=1
  fi
done

[[ "$failed" -eq 0 ]]
echo
echo "HEALTH PASS: ${nodes[*]}"
