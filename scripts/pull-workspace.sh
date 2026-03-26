#!/bin/bash
# Clone or pull the DVC workspace project into /workspace.

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [workspace] $*"
}

WORKSPACE=/workspace
BRANCH="${GIT_BRANCH:-main}"

if [ -z "${WORKSPACE_REPO}" ]; then
  log "WORKSPACE_REPO is not set. Skipping."
  exit 0
fi

if [ ! -d "${WORKSPACE}/.git" ]; then
  log "Cloning ${WORKSPACE_REPO} into ${WORKSPACE}..."
  git clone --branch "${BRANCH}" "${WORKSPACE_REPO}" "${WORKSPACE}" 2>&1 | sed "s/^/  /"
  log "Workspace cloned."
else
  cd "${WORKSPACE}"
  log "Pulling origin/${BRANCH}..."
  git fetch origin 2>&1 | sed "s/^/  /"

  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")

  if [ -n "${REMOTE}" ] && [ "${LOCAL}" != "${REMOTE}" ]; then
    git pull --ff-only origin "${BRANCH}" 2>&1 | sed "s/^/  /"
    log "Workspace updated (${LOCAL:0:8} -> ${REMOTE:0:8})."
  else
    log "Already up to date."
  fi
fi
