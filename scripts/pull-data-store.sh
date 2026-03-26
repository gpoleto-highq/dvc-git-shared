#!/bin/bash
# Pull the latest DVC data-store from its git remote.
# The data-store is mounted at /dvc-remote and is itself a git repository.

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [data-store] $*"
}

DATA_STORE=/dvc-remote

if [ ! -d "${DATA_STORE}/.git" ]; then
  log "WARNING: ${DATA_STORE} is not a git repository. Skipping pull."
  log "Make sure you cloned the data-store repo into ./data-store before running."
  exit 0
fi

cd "${DATA_STORE}"

BRANCH="${GIT_BRANCH:-main}"

log "Fetching origin..."
git fetch origin 2>&1 | sed "s/^/  /"

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")

if [ -z "${REMOTE}" ]; then
  log "Remote branch origin/${BRANCH} not found. Skipping pull."
  exit 0
fi

if [ "${LOCAL}" = "${REMOTE}" ]; then
  log "Already up to date (${LOCAL:0:8})."
else
  log "Pulling origin/${BRANCH} (${LOCAL:0:8} -> ${REMOTE:0:8})..."
  git pull --ff-only origin "${BRANCH}" 2>&1 | sed "s/^/  /"
  log "Data-store updated."
fi
