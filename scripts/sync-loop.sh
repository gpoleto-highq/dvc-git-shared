#!/bin/bash
# Runs in the background: on each interval it pulls both repos to receive
# updates, then checks for local DVC changes and opens a PR if any are found.

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sync-loop] $*"
}

INTERVAL="${SYNC_INTERVAL:-300}"
log "Sync interval: ${INTERVAL}s"

while true; do
  sleep "${INTERVAL}"
  log "--- Periodic sync ---"

  # 1. Pull the shared data-store so we branch off the latest main
  /scripts/pull-data-store.sh || log "WARNING: data-store pull failed"

  # 2. Push any local DVC changes to a branch and open a PR
  /scripts/push-data-store.sh || log "WARNING: data-store push/PR failed"

  # 3. Pull the workspace project (code + .dvc files)
  if [ -n "${WORKSPACE_REPO}" ]; then
    /scripts/pull-workspace.sh || log "WARNING: workspace pull failed"
  fi

  log "--- Sync complete ---"
done
