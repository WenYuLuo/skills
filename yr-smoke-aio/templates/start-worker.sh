#!/usr/bin/env bash
# yr-smoke-aio DATA-PLANE node deploy. Placeholders filled by `up` (sed): __MASTER_INFO__ __NODE_TAG__ __NODE_NAME__ __NUMBER__
set -euo pipefail
AIO_NODE_IP="$(hostname -i | awk '{print $1}')"
export MY_ENV=myenv LD_LIBRARY_PATH=:/testEnv PYTHONPATH=:/testpythonpayh
exec /usr/local/bin/yr start \
  --master_info '__MASTER_INFO__' \
  --block true --port_policy FIX --enable_inherit_env true \
  --custom_resources '{"__NODE_TAG__":3,"node":1}' \
  --labels '{"name":"__NODE_NAME__","role":"worker","number":"__NUMBER__"}' \
  -a "${AIO_NODE_IP}"
