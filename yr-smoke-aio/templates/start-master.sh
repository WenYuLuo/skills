#!/usr/bin/env bash
# yr-smoke-aio MASTER node deploy (replaces image's /usr/local/bin/start-yuanrong.sh).
set -euo pipefail
AIO_NODE_IP="$(hostname -i | awk '{print $1}')"
# Deploy-time env the actor-smoke getenv cases assert on (inherited into runtimes via --enable_inherit_env).
export MY_ENV=myenv LD_LIBRARY_PATH=:/testEnv PYTHONPATH=:/testpythonpayh
exec /usr/local/bin/yr start \
  --master --block true --port_policy FIX --enable_inherit_env true \
  --enable_faas_frontend=true --faas_frontend_http_port 8889 \
  --enable_traefik_registry true --traefik_http_entrypoint web --traefik_enable_tls false \
  --enable_function_scheduler false --enable_meta_service true \
  --frontend_ssl_enable false --enable_iam_server false \
  --frontend_client_auth_type NoClientCert --enable_function_token_auth false \
  --custom_resources '{"node_tag1":3,"node":1}' \
  --labels '{"name":"node1","role":"server","number":"odd","only":"one"}' \
  -a "${AIO_NODE_IP}" -p /openyuanrong/services.yaml
