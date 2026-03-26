#!/bin/bash
set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------------------------------------------------------------------------
# Configure git identity (needed if the sync script ever auto-commits)
# ---------------------------------------------------------------------------
git config --global user.name  "${GIT_AUTHOR_NAME:-DVC Sync Bot}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-dvc-sync@localhost}"

# ---------------------------------------------------------------------------
# 1. Pull the DVC data-store (shared remote, mounted at /dvc-remote)
# ---------------------------------------------------------------------------
log "Syncing DVC data-store..."
/scripts/pull-data-store.sh

# ---------------------------------------------------------------------------
# 2. Optionally pull the DVC workspace project repo
# ---------------------------------------------------------------------------
if [ -n "${WORKSPACE_REPO}" ]; then
  log "Syncing workspace from ${WORKSPACE_REPO}..."
  /scripts/pull-workspace.sh
else
  log "WORKSPACE_REPO not set — skipping workspace pull."
fi

# ---------------------------------------------------------------------------
# 3. Ensure DVC remote points to /dvc-remote
# ---------------------------------------------------------------------------
if [ -f /workspace/.dvc/config ]; then
  log "Configuring DVC remote..."
  cd /workspace
  dvc remote add -d -f shared /dvc-remote 2>/dev/null || true
  log "DVC remote 'shared' -> /dvc-remote"
fi

# ---------------------------------------------------------------------------
# 4. Schedule periodic sync via background loop
# ---------------------------------------------------------------------------
log "Starting periodic sync every ${SYNC_INTERVAL:-300}s..."
/scripts/sync-loop.sh &

log "DVC container ready."

# Keep container alive
exec tail -f /dev/null
