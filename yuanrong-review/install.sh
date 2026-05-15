#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCAL_CONFIG="$SCRIPT_DIR/config/config.yaml.local"
USER_CONFIG="${YUANRONG_REVIEW_CONFIG:-$HOME/.config/yuanrong-review/config.yaml}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 2; }
}

need python3

mkdir -p "$SCRIPT_DIR/config" "$(dirname "$USER_CONFIG")"

token="${YUANRONG_PAT:-}"
if [[ -z "$token" ]]; then
  printf 'GitCode token [Enter to keep ${YUANRONG_PAT} reference]: ' >&2
  stty -echo 2>/dev/null || true
  IFS= read -r token || true
  stty echo 2>/dev/null || true
  printf '\n' >&2
fi

if [[ -z "$token" ]]; then
  token='${YUANRONG_PAT}'
fi

write_config() {
  local dest="$1"
  umask 077
  cat > "$dest" <<CFG
api:
  base_url: "https://api.gitcode.com/api/v5"
  access_token: "$token"

defaults:
  owner: "openeuler"
  default_repo: "yuanrong"
  review_style: "normal"
CFG
}

write_config "$LOCAL_CONFIG"
write_config "$USER_CONFIG"

python3 - <<'PY'
import importlib.util
import subprocess
import sys

missing = [pkg for pkg in ("requests", "yaml") if importlib.util.find_spec(pkg) is None]
if missing:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "pyyaml"])
PY

echo "Wrote local migration config: $LOCAL_CONFIG"
echo "Wrote runtime config: $USER_CONFIG"
