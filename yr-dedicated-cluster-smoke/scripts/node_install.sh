#!/usr/bin/env bash
# Run ON a cluster node (via ssh ... 'bash -s' < node_install.sh) with the wheel
# URLs exported (see get_obs_urls.sh). Downloads wheels from OBS (fast, same
# cloud), pip-installs --no-deps (base deps already present), verifies layout.
set -uo pipefail
S=/home/disk/yr-package-staging
rm -rf "$S"; mkdir -p "$S"; cd "$S"
for var in WHEEL_openyuanrong WHEEL_runtime WHEEL_functionsystem WHEEL_datasystem WHEEL_faas WHEEL_sdk WHEEL_cpp_sdk; do
  url="${!var:-}"; [ -n "$url" ] || { echo "MISSING $var"; exit 1; }
  fn=$(basename "${url%%\?*}"); fn="${fn//%2B/+}"
  curl -fsSL -o "$fn" "$url" && echo "  got $fn ($(stat -c%s "$fn") B)" || { echo "  FAIL $url"; exit 1; }
done
echo "[pip install --no-deps --force-reinstall]"
python3.11 -m pip install --break-system-packages --force-reinstall --no-cache-dir --no-deps "$S"/*.whl \
  >/tmp/pipinstall.log 2>&1 && echo "  pip OK" || { echo "  pip FAILED"; tail -20 /tmp/pipinstall.log; exit 1; }
sp=$(python3.11 -c 'import site; print(site.getsitepackages()[0])')
echo "[verify] site=$sp"
echo -n "  fs bins: "; ls "$sp/yr/functionsystem/bin/" 2>/dev/null | tr '\n' ' '; echo
for f in third_party/etcd/etcd runtime/service/go/bin/goruntime runtime/service/cpp/bin/runtime datasystem/datasystem_worker; do
  echo -n "  $f: "; test -x "$sp/yr/$f" && echo present || echo MISSING
done
python3.11 -m pip show openyuanrong openyuanrong-functionsystem 2>/dev/null | egrep '^(Name|Version):' | paste - -
