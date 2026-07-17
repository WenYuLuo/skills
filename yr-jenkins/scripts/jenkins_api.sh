#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jenkins_api.sh status <build-url>
  jenkins_api.sh stages <build-url>
  jenkins_api.sh console <build-url>
  jenkins_api.sh scan <build-url>
  jenkins_api.sh info <job-url>
  jenkins_api.sh job <job-url> [count]
  jenkins_api.sh params <build-url>
  jenkins_api.sh trigger <job-url> key=value [key=value ...]
  jenkins_api.sh queue <queue-url-or-id>
  jenkins_api.sh cancel-queue <queue-url-or-id>
  jenkins_api.sh stop <build-url>
  jenkins_api.sh obs-links <obs-upload-build-url>

Credentials:
  Set JENKINS_TOKEN, or store it in macOS Keychain service
  openyuanrong-jenkins. Otherwise enter the token on stdin when prompted.
  JENKINS_USER defaults to songminhui.

Environment:
  JENKINS_BASE defaults to http://1.95.91.104.
  JENKINS_QUEUE_WAIT seconds to wait for queue executable, default 120.
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

cmd="$1"
url="${2%/}"
user="${JENKINS_USER:-songminhui}"
base="${JENKINS_BASE:-http://1.95.91.104}"
keychain_service="${JENKINS_KEYCHAIN_SERVICE:-openyuanrong-jenkins}"

if [[ -n "${JENKINS_TOKEN:-}" ]]; then
  token="$JENKINS_TOKEN"
elif command -v security >/dev/null 2>&1 \
  && token="$(security find-generic-password -s "$keychain_service" -a "$user" -w 2>/dev/null)" \
  && [[ -n "$token" ]]; then
  :
else
  read -r -s -p "Jenkins token: " token
  printf '\n' >&2
fi

auth="$(printf '%s:%s' "$user" "$token" | base64 | tr -d '\n')"

normalize_url() {
  local target="$1"
  target="${target/https:\/\/jenkins.openyuanrong.com/${base}}"
  target="${target/http:\/\/jenkins.openyuanrong.com/${base}}"
  printf '%s' "$target"
}

fetch() {
  local target
  target="$(normalize_url "$1")"
  curl -K - "$target" <<EOF
globoff
location
compressed
noproxy = "*"
connect-timeout = 10
max-time = 120
silent
show-error
header = "Authorization: Basic ${auth}"
EOF
}

redact_console() {
  python3 -c '
import re
import sys

secret_assignment = re.compile(
    r"(?i)(\b[A-Z0-9_]*(?:TOKEN|PASSWORD|PASSWD|SECRET|KEY|WEBHOOK)[A-Z0-9_]*=)(\S+)"
)
for line in sys.stdin:
    sys.stdout.write(secret_assignment.sub(r"\1<redacted>", line))
'
}

post_form() {
  local target="$1"
  local data="$2"
  target="$(normalize_url "$target")"
  curl -K - --data "$data" "$target" <<EOF
globoff
location
compressed
noproxy = "*"
connect-timeout = 10
max-time = 120
silent
show-error
include
request = "POST"
header = "Authorization: Basic ${auth}"
EOF
}

urlencode_pairs() {
  python3 - "$@" <<'PY'
import sys
from urllib.parse import urlencode
pairs = []
for item in sys.argv[1:]:
    if "=" not in item:
        raise SystemExit(f"expected key=value, got {item!r}")
    k, v = item.split("=", 1)
    pairs.append((k, v))
print(urlencode(pairs))
PY
}

case "$cmd" in
  status)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    fetch "$url/api/json?tree=building,result,duration,estimatedDuration,fullDisplayName,timestamp,actions[parameters[name,value]]"
    ;;
  stages)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    fetch "$url/wfapi/describe" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("build={} status={} duration={}s".format(
    d.get("name", ""), d.get("status", ""), int((d.get("durationMillis") or 0) / 1000)))
for stage in d.get("stages", []):
    print("{}\t{}\t{}s".format(
        stage.get("status", ""), stage.get("name", ""),
        int((stage.get("durationMillis") or 0) / 1000)))
'
    ;;
  console)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    fetch "$url/consoleText" | redact_console
    ;;
  scan)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    fetch "$url/consoleText" > "$tmp"
    rg -n "Finished:|ERROR:|FAILED:|Build completed successfully|当前 Commit|写入 commit.txt|script returned|SUCCESS|FAILURE|构建成功|构建失败|开始构建|构建组件|Found artifact|No .*artifact|Scheduling project|Starting building|仓库:|分支:|git clone|current_time|build_cache|obs://|openyuanrong[.]obs|release_summary[.]yaml|openyuanrong-[0-9].*[.](tar[.]gz|whl)" "$tmp" || true
    ;;
  info)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    fetch "$url/api/json?tree=name,displayName,url,buildable,inQueue,color,nextBuildNumber" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("name={}".format(d.get("displayName") or d.get("name", "")))
print("buildable={}".format(str(bool(d.get("buildable"))).lower()))
print("in_queue={}".format(str(bool(d.get("inQueue"))).lower()))
print("color={}".format(d.get("color", "")))
print("next_build_number={}".format(d.get("nextBuildNumber", "")))
'
    ;;
  job)
    [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
    count="${3:-20}"
    [[ "$count" =~ ^[0-9]+$ ]] || { echo "count must be numeric" >&2; exit 2; }
    fetch "$url/api/json?tree=displayName,url,lastBuild[number,url,result,building,timestamp],lastCompletedBuild[number,url,result,timestamp],lastSuccessfulBuild[number,url,result,timestamp],lastFailedBuild[number,url,result,timestamp],builds[number,url,result,building,timestamp,duration]{0,${count}}" | python3 -c '
import datetime
import json
import sys

d = json.load(sys.stdin)
print("job={}".format(d.get("displayName", "")))
for key in ("lastBuild", "lastCompletedBuild", "lastSuccessfulBuild", "lastFailedBuild"):
    b = d.get(key) or {}
    if not b:
        continue
    ts = datetime.datetime.fromtimestamp((b.get("timestamp") or 0) / 1000).strftime("%Y-%m-%d %H:%M:%S")
    url = (b.get("url") or "").replace("jenkins.openyuanrong.com", "1.95.91.104")
    print("{}=#{} {} {} {}".format(key, b.get("number", ""), b.get("result") or "BUILDING", ts, url))
print("builds:")
for b in d.get("builds", []):
    ts = datetime.datetime.fromtimestamp((b.get("timestamp") or 0) / 1000).strftime("%Y-%m-%d %H:%M:%S")
    url = (b.get("url") or "").replace("jenkins.openyuanrong.com", "1.95.91.104")
    duration = int((b.get("duration") or 0) / 1000)
    print("#{} {} {} dur={}s {}".format(b.get("number", ""), b.get("result") or "BUILDING", ts, duration, url))
'
    ;;
  params)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    fetch "$url/api/json?tree=actions[parameters[name,value]]" | python3 -c '
import json, sys
d=json.load(sys.stdin)
for action in d.get("actions", []):
    for p in action.get("parameters", []) or []:
        print("{}={}".format(p.get("name", ""), p.get("value", "")))
'
    ;;
  trigger)
    [[ $# -ge 3 ]] || { usage; exit 2; }
    shift 2
    data="$(urlencode_pairs "$@")"
    post_form "$url/buildWithParameters" "$data" | awk 'BEGIN{IGNORECASE=1} /^HTTP\//{status=$2} /^Location:/{loc=$2; gsub("\r","",loc)} END{print "status=" status; if (loc) print "queue_url=" loc}'
    ;;
  queue)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    queue="$url"
    if [[ "$queue" =~ ^[0-9]+$ ]]; then
      queue="${base}/queue/item/${queue}"
    fi
    queue="${queue%/}"
    end=$((SECONDS + ${JENKINS_QUEUE_WAIT:-120}))
    while :; do
      json="$(fetch "$queue/api/json")"
      result="$(python3 -c '
import json, sys
try:
    d=json.load(sys.stdin)
except json.JSONDecodeError:
    print("queue_item_unavailable=true")
    print("hint=queue record expired; identify the build with job and params")
    raise SystemExit
e=d.get("executable") or {}
if e:
    print("build_number={}".format(e.get("number", "")))
    print("build_url={}".format(e.get("url", "")))
else:
    print("queued=true")
    why=d.get("why")
    if why:
        print("why={}".format(why))
' <<<"$json")"
      printf '%s\n' "$result"
      if grep -q '^queue_item_unavailable=true' <<<"$result"; then
        exit 2
      fi
      if grep -q '^build_number=' <<<"$result"; then
        break
      fi
      if (( SECONDS >= end )); then
        exit 1
      fi
      sleep 5
    done
    ;;
  cancel-queue)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    queue="$url"
    if [[ "$queue" =~ ^[0-9]+$ ]]; then
      queue="${base}/queue/item/${queue}"
    fi
    queue="${queue%/}"
    post_form "$queue/cancelQueue" "" >/dev/null
    json="$(fetch "$queue/api/json")"
    python3 -c '
import json, sys
d=json.load(sys.stdin)
print("queue_id={}".format(d.get("id", "")))
print("cancelled={}".format(str(bool(d.get("cancelled"))).lower()))
' <<<"$json"
    ;;
  stop)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    post_form "$url/stop" "" | awk 'BEGIN{IGNORECASE=1} /^HTTP\//{status=$2} END{print "status=" status}'
    ;;
  obs-links)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    fetch "$url/consoleText" > "$tmp"
    python3 - "$tmp" <<'PY'
import re, sys
s=open(sys.argv[1], encoding="utf-8", errors="ignore").read()
roots=[]
for match in re.findall(r"(?:Scanning:\s+|-->\s+)obs://openyuanrong/([^\s,]+)", s):
    root=match.rstrip("/")
    if root.endswith("/index.html"):
        root = root.rsplit("/", 1)[0]
    if root not in roots:
        roots.append(root)
versions=sorted(set(re.findall(r"openyuanrong-([0-9][^\s/]*)[.]tar[.]gz", s)))
if not versions:
    versions=["*"]
for root in roots:
    base=f"https://openyuanrong.obs.cn-southwest-2.myhuaweicloud.com/{root}"
    print(f"index={base}/index.html")
    for version in versions:
        for arch in ("x86_64", "aarch64"):
            print(f"{arch}_tar={base}/{arch}/openyuanrong-{version}.tar.gz")
for name in sorted(set(re.findall(r"openyuanrong[^\s/]*[.]whl", s))):
    print(f"wheel={name}")
PY
    ;;
  *)
    usage
    exit 2
    ;;
esac
