# yr-smoke-aio image = AIO base + current rust functionsystem binaries + smoke config.
# 4 binaries: function_master/proxy/agent + domain_scheduler (function_master spawns
# domain_scheduler from its own bin dir for the multi-tier scheduler / instance-affinity).
FROM __BASE__
COPY function_master function_proxy function_agent domain_scheduler init_scheduler_args.json /tmp/yr-smoke-aio/
COPY start-master.sh   /usr/local/bin/start-yuanrong.sh
RUN set -eu; \
    YR_ROOT="$(python3 -c 'from pathlib import Path; import yr; print(Path(yr.__file__).resolve().parent)')"; \
    if [ -d "${YR_ROOT}/functionsystem/bin" ]; then FS_ROOT="${YR_ROOT}/functionsystem"; \
    elif [ -d "${YR_ROOT}/inner/functionsystem/bin" ]; then FS_ROOT="${YR_ROOT}/inner/functionsystem"; \
    else echo "functionsystem directory not found below ${YR_ROOT}" >&2; exit 1; fi; \
    install -m 0755 /tmp/yr-smoke-aio/function_master "${FS_ROOT}/bin/function_master"; \
    install -m 0755 /tmp/yr-smoke-aio/function_proxy "${FS_ROOT}/bin/function_proxy"; \
    install -m 0755 /tmp/yr-smoke-aio/function_agent "${FS_ROOT}/bin/function_agent"; \
    install -m 0755 /tmp/yr-smoke-aio/domain_scheduler "${FS_ROOT}/bin/domain_scheduler"; \
    install -d "${FS_ROOT}/config"; \
    install -m 0644 /tmp/yr-smoke-aio/init_scheduler_args.json "${FS_ROOT}/config/init_scheduler_args.json"; \
    chmod +x /usr/local/bin/start-yuanrong.sh; \
    rm -rf /tmp/yr-smoke-aio
