#!/usr/bin/env bash

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLIC_DIR="$REPO_ROOT/public"
TARGET_REPO="${TARGET_REPO:-$(cd "$REPO_ROOT/.." && pwd)/wushao666.github.io}"
TARGET_SYNC_SCRIPT="$TARGET_REPO/scripts/wushao666-auto-git-sync.sh"

log() {
  printf '[blog-generator publish] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing command: $1"
    exit 1
  fi
}

main() {
  require_command hugo
  require_command rsync

  if [ ! -d "$TARGET_REPO/.git" ]; then
    log "Target repository not found: $TARGET_REPO"
    exit 1
  fi

  if [ ! -x "$TARGET_SYNC_SCRIPT" ]; then
    log "Target sync script is not executable: $TARGET_SYNC_SCRIPT"
    exit 1
  fi

  cd "$REPO_ROOT"
  log "Running hugo -D"
  hugo -D

  if [ ! -d "$PUBLIC_DIR" ]; then
    log "Hugo did not create public directory: $PUBLIC_DIR"
    exit 1
  fi

  log "Syncing public output to $TARGET_REPO"
  rsync -av --delete \
    --exclude='.git/' \
    --exclude='scripts/' \
    --exclude='*.png' \
    --exclude='*.ico' \
    "$PUBLIC_DIR/" "$TARGET_REPO/"

  log "Triggering target repository auto commit"
  "$TARGET_SYNC_SCRIPT" --once
}

main "$@"
