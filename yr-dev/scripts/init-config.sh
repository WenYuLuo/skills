#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
LOCAL_CONFIG="$SKILL_DIR/config/gitcode.env.local"
USER_CONFIG="${YR_DEV_CONFIG:-$HOME/.config/yr-dev/gitcode.env}"

mkdir -p "$SKILL_DIR/config" "$(dirname "$USER_CONFIG")"

read_secret() {
  local prompt="$1" value="${2:-}"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return
  fi
  printf '%s' "$prompt" >&2
  stty -echo 2>/dev/null || true
  IFS= read -r value || true
  stty echo 2>/dev/null || true
  printf '\n' >&2
  printf '%s\n' "$value"
}

token=$(read_secret "GitCode token [required]: " "${GITCODE_TOKEN:-}")
name="${YR_SIGNOFF_NAME:-$(git config user.name 2>/dev/null || true)}"
email="${YR_SIGNOFF_EMAIL:-$(git config user.email 2>/dev/null || true)}"

printf 'Sign-off name [%s]: ' "${name:-unset}" >&2
IFS= read -r maybe_name || true
[[ -n "${maybe_name:-}" ]] && name="$maybe_name"

printf 'Sign-off email [%s]: ' "${email:-unset}" >&2
IFS= read -r maybe_email || true
[[ -n "${maybe_email:-}" ]] && email="$maybe_email"

write_config() {
  local dest="$1"
  umask 077
  cat > "$dest" <<CFG
GITCODE_API_BASE=https://gitcode.com/api/v5
GITCODE_TOKEN=$token
YR_SIGNOFF_NAME=$name
YR_SIGNOFF_EMAIL=$email
CFG
}

write_config "$LOCAL_CONFIG"
write_config "$USER_CONFIG"

echo "Wrote local migration config: $LOCAL_CONFIG"
echo "Wrote runtime config: $USER_CONFIG"
