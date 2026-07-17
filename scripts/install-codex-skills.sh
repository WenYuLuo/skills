#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
CHECK_ONLY=false
TOOLKIT_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --toolkit) TOOLKIT_ONLY=true ;;
    *) echo "Usage: $0 [--check] [--toolkit]" >&2; exit 2 ;;
  esac
done

mkdir -p "$DEST_ROOT"
installed=0; ok=0; conflicts=0
while IFS=$'\t' read -r name source_dir; do
  dest="$DEST_ROOT/$name"
  if [[ -L "$dest" ]]; then
    current=$(readlink "$dest")
    if [[ "$current" == "$source_dir" ]]; then
      echo "OK        $name -> $source_dir"; ok=$((ok+1))
    else
      echo "CONFLICT  $dest -> $current (expected $source_dir)" >&2; conflicts=$((conflicts+1))
    fi
  elif [[ -e "$dest" ]]; then
    echo "CONFLICT  $dest exists and is not a symlink" >&2; conflicts=$((conflicts+1))
  elif $CHECK_ONLY; then
    echo "MISSING   $dest -> $source_dir" >&2; conflicts=$((conflicts+1))
  else
    ln -s "$source_dir" "$dest"
    echo "INSTALLED $name -> $source_dir"; installed=$((installed+1))
  fi
done < <(
  if $TOOLKIT_ONLY; then
    printf 'yuanrong-toolkit\t%s\n' "$SOURCE_ROOT"
  else
    find "$SOURCE_ROOT" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -printf '%h\n' \
      | sort \
      | while IFS= read -r source_dir; do
          printf '%s\t%s\n' "$(basename "$source_dir")" "$source_dir"
        done
  fi
)

echo "SUMMARY installed=$installed ok=$ok conflicts=$conflicts"
[[ "$conflicts" -eq 0 ]]
