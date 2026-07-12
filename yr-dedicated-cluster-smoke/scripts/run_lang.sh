#!/usr/bin/env bash
# Run ONE language's actor smoke suite against the running dedicated cluster. Place on the
# master/test host yrm (192.168.0.128) and invoke: bash run_lang.sh <python|java|cpp> <run_python_actor_test.sh|run_java_actor_test.sh|run_cpp_actor_test.sh>
# Synchronous (returns when the suite finishes). Tests connect to the already-
# running cluster via /root/.yr/config.ini; they do NOT start it.
# Order matters: run java BEFORE cpp (the cpp suite deletes *.so incl java's libcross.so).
set -uo pipefail
W=/home/workspace/openyuanrong/OpenYR_Actor_Smoke_Process_X86
TWS=192.168.0.128
lang="${1:?lang}"; script="${2:?script}"
cd "$W/OpenYuanRongTest/FunctionSystemTest/scripts/shell"
export YR_SERVER_ADDRESS="$TWS:22773" YR_DS_ADDRESS="$TWS:31501" YR_MASTER_ADDRESS="$TWS:22770"
export YR_IN_CLUSTER=true MY_ENV=myenv
export LD_LIBRARY_PATH="$W/OpenYuanRongTest/FunctionSystemTest/cases/cpp-actor/build:${LD_LIBRARY_PATH:-}:/testEnv"
export PYTHONPATH="${PYTHONPATH:-}:/testpythonpayh"
LOG="/home/disk/yr-workspace/actor-${lang}-$(date +%Y%m%d-%H%M%S).log"
echo "RUNLOG=$LOG"
set +e
bash "$script" "$W" "$TWS" > "$LOG" 2>&1
rc=$?
set -e
ok=$(grep -c 'execute end with success' "$LOG" || true)
err=$(grep -c 'execute end with error' "$LOG" || true)
echo "EXIT=$rc lang=$lang  ok=$ok  err=$err"
echo "FAILED CASES:"
egrep -i 'execute end with error' "$LOG" | sed -E 's/.*Task] [a-f0-9-]+-//;s/,.*//' | sort -u | sed 's/^/  /' || true
exit "$rc"
