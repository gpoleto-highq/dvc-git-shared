#!/bin/bash
# Runs in the background and periodically pulls both repos so that
# users sharing the git data-store always get the latest DVC cache.

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sync-loop] $*"
}

INTERVAL="${SYNC_INTERVAL:-300}"
log "Sync interval: ${INTERVAL}s"

while true; do
  sleep "${INTERVAL}"
  log "--- Periodic sync ---"

  /scripts/pull-data-store.sh || log "WARNING: data-store pull failed"

  if [ -n "${WORKSPACE_REPO}" ]; then
    /scripts/pull-workspace.sh || log "WARNING: workspace pull failed"
  fi

  log "--- Sync complete ---"
done
