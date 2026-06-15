# yr-smoke-aio image = AIO base + current rust functionsystem binaries + smoke config.
# 4 binaries: function_master/proxy/agent + domain_scheduler (function_master spawns
# domain_scheduler from its own bin dir for the multi-tier scheduler / instance-affinity).
FROM __BASE__
ARG BP=/opt/uv/python/cpython-3.10-linux-aarch64-gnu/lib/python3.10/site-packages/yr/inner/functionsystem/bin
ARG CP=/opt/uv/python/cpython-3.10-linux-aarch64-gnu/lib/python3.10/site-packages/yr/inner/functionsystem/config
COPY function_master   ${BP}/function_master
COPY function_proxy    ${BP}/function_proxy
COPY function_agent    ${BP}/function_agent
COPY domain_scheduler  ${BP}/domain_scheduler
COPY init_scheduler_args.json ${CP}/init_scheduler_args.json
COPY start-master.sh   /usr/local/bin/start-yuanrong.sh
RUN chmod +x ${BP}/function_master ${BP}/function_proxy ${BP}/function_agent ${BP}/domain_scheduler /usr/local/bin/start-yuanrong.sh
