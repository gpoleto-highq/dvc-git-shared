#!/bin/bash
# Detects new/modified files in the DVC data-store, pushes them to a new
# branch, and opens a GitHub Pull Request for team review.

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [push] $*"
}

DATA_STORE=/dvc-remote
BASE_BRANCH="${GIT_BRANCH:-main}"

if [ ! -d "${DATA_STORE}/.git" ]; then
  log "WARNING: ${DATA_STORE} is not a git repository. Skipping."
  exit 0
fi

cd "${DATA_STORE}"

# Ensure we are on the base branch before checking for changes
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "${CURRENT_BRANCH}" != "${BASE_BRANCH}" ]; then
  log "Not on ${BASE_BRANCH} (currently on '${CURRENT_BRANCH}'). Switching..."
  git checkout "${BASE_BRANCH}"
fi

# Check for any uncommitted changes (new cache files from dvc push)
UNTRACKED=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
MODIFIED=$(git status --porcelain | wc -l | tr -d ' ')

if [ "${MODIFIED}" -eq 0 ] && [ "${UNTRACKED}" -eq 0 ]; then
  log "No changes detected in data-store. Nothing to push."
  exit 0
fi

log "${UNTRACKED} untracked / ${MODIFIED} changed file(s) detected."

# ---------------------------------------------------------------------------
# Create a sync branch
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME_SAFE=$(hostname | tr '.' '-' | tr '[:upper:]' '[:lower:]')
BRANCH="dvc-sync/${HOSTNAME_SAFE}-${TIMESTAMP}"

log "Creating branch ${BRANCH}..."
git checkout -b "${BRANCH}"

# Stage and commit all new cache objects
git add -A
FILE_COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
git commit -m "dvc: sync ${FILE_COUNT} file(s) from ${HOSTNAME_SAFE} at ${TIMESTAMP}"

# ---------------------------------------------------------------------------
# Push branch to origin
# ---------------------------------------------------------------------------
log "Pushing ${BRANCH} to origin..."
git push origin "${BRANCH}"

# ---------------------------------------------------------------------------
# Create Pull Request via GitHub API
# ---------------------------------------------------------------------------
if [ -z "${GITHUB_TOKEN}" ]; then
  log "GITHUB_TOKEN not set — branch pushed but PR not created."
  log "Create the PR manually at: $(git remote get-url origin)"
  git checkout "${BASE_BRANCH}"
  exit 0
fi

# Extract owner/repo from remote URL (supports both SSH and HTTPS)
REMOTE_URL=$(git remote get-url origin)
GITHUB_REPO=$(echo "${REMOTE_URL}" \
  | sed -E 's|git@github\.com:||; s|https://github\.com/||; s|\.git$||')

log "Opening PR in ${GITHUB_REPO}..."

PR_BODY="Automated DVC data sync from host \`${HOSTNAME_SAFE}\` at \`${TIMESTAMP}\`.

**${FILE_COUNT} cache file(s)** added to the DVC remote.

Review the changes and merge into \`${BASE_BRANCH}\` to make this data available to the whole team via \`dvc pull\`."

PR_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
  -d "$(jq -n \
    --arg title "DVC sync: ${HOSTNAME_SAFE} @ ${TIMESTAMP}" \
    --arg head  "${BRANCH}" \
    --arg base  "${BASE_BRANCH}" \
    --arg body  "${PR_BODY}" \
    '{title: $title, head: $head, base: $base, body: $body}')")

PR_URL=$(echo "${PR_RESPONSE}" | grep -o '"html_url":"[^"]*"' | head -1 | sed 's/"html_url":"//; s/"//')

if [ -n "${PR_URL}" ]; then
  log "PR created: ${PR_URL}"
else
  PR_ERROR=$(echo "${PR_RESPONSE}" | grep -o '"message":"[^"]*"' | sed 's/"message":"//; s/"//')
  log "WARNING: PR creation failed — ${PR_ERROR:-unknown error}"
  log "Full response: ${PR_RESPONSE}"
fi

# Return to base branch for the next sync cycle
git checkout "${BASE_BRANCH}"
