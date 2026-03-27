# dvc-git-shared

A self-syncing DVC (Data Version Control) environment using Docker Compose and Git — no dedicated DVC server required.

Data is stored in a separate git repository ([data-store](https://github.com/gpoleto-highq/data-store-dvc-git-shared)) that acts as the DVC remote. The container pulls both repos on boot and at a configurable interval. When a user runs `dvc push`, the container automatically commits the new cache files to a branch and opens a GitHub Pull Request — team members review and merge via the GitHub website.

## How it works

```
  User runs: dvc push
       │
       ▼ writes files into data-store/
┌─────────────────────────────────────────┐
│  Docker container  (every SYNC_INTERVAL) │
│                                          │
│  1. git pull data-store  (get latest)    │
│  2. detect new cache files               │
│  3. git checkout -b dvc-sync/<host>-<ts> │
│  4. git commit + push branch             │
│  5. POST /pulls  → GitHub PR             │
│  6. git pull workspace  (code sync)      │
└─────────────────────────────────────────┘
       │
       ▼ PR opened on GitHub
  Team reviews & merges
       │
       ▼ next sync pulls merged data
  All machines run: dvc pull
```

No S3, no DVC server, no extra infrastructure — just two GitHub repos.

## Repository structure

```
dvc-git-shared/                          ← this repo
├── Dockerfile                           # python:3.11-slim + git + jq + dvc
├── docker-compose.yml
├── .env.example                         # copy to .env and configure
├── .gitmodules                          # registers data-store submodule
├── scripts/
│   ├── entrypoint.sh                    # boot: pull → configure DVC remote → start sync
│   ├── pull-data-store.sh               # git pull on /dvc-remote
│   ├── pull-workspace.sh                # git clone/pull the workspace project
│   ├── push-data-store.sh               # detect changes → branch → commit → push → open PR
│   └── sync-loop.sh                     # background loop: pull → push/PR → repeat
└── data-store/                          ← separate git repo (submodule)
    └── .github/workflows/
        ├── auto-merge-dvc-sync.yml      # auto-merges dvc-sync/* PRs; flags conflicts
        └── cleanup-merged-branches.yml  # deletes branches after merge
```

## Prerequisites

- Docker + Docker Compose
- Git with SSH access to GitHub
- SSH key added to your GitHub account (`~/.ssh/id_ed25519` or equivalent)
- GitHub personal access token (for auto-PR creation)

## First-time setup

### 1. Clone with submodule

```bash
git clone --recurse-submodules git@github.com:gpoleto-highq/dvc-git-shared.git
cd dvc-git-shared
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### 2. Create a GitHub token

Go to **GitHub → Settings → Developer settings → Personal access tokens**.

- **Classic token**: enable the `repo` scope.
- **Fine-grained token**: enable **Contents** (read/write) and **Pull requests** (read/write) on the `data-store` repo.

### 3. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

| Variable | Description | Default |
|---|---|---|
| `GITHUB_TOKEN` | Personal access token for opening PRs | _(required for auto-PR)_ |
| `WORKSPACE_REPO` | Git URL of your DVC project repo (cloned into `/workspace`) | _(empty)_ |
| `GIT_BRANCH` | Branch to track on both repos | `main` |
| `SYNC_INTERVAL` | Seconds between sync cycles | `300` |
| `SSH_KEY_PATH` | Path to SSH key directory on the host | `~/.ssh` |
| `GIT_AUTHOR_NAME` | Git identity for auto-commits | `DVC Sync Bot` |
| `GIT_AUTHOR_EMAIL` | Git identity for auto-commits | `dvc-sync@localhost` |

### 4. Start

```bash
docker compose up -d
```

The container will:
1. Pull the latest `data-store` from GitHub
2. Clone/pull the workspace project (if `WORKSPACE_REPO` is set)
3. Configure DVC to use `/dvc-remote` as its default remote
4. Start a background sync loop

## Daily usage

### Sharing new data with the team

```bash
# Inside the container (or wherever your DVC project lives):
dvc push
```

That's it. On the next sync cycle the container will:
1. Detect the new cache files in `data-store/`
2. Push them to a branch named `dvc-sync/<hostname>-<timestamp>`
3. Open a PR on GitHub automatically

A teammate then reviews and merges the PR on GitHub. On the next sync after the merge, every other machine pulls the new data automatically.

To trigger a sync immediately instead of waiting:

```bash
docker exec -it dvc /scripts/push-data-store.sh
```

### Receiving data pushed by others

Happens automatically on each sync cycle. To trigger it now:

```bash
docker exec -it dvc /scripts/pull-data-store.sh
```

Or inside the container:

```bash
docker exec -it dvc bash
cd /workspace && dvc pull
```

### Run DVC commands inside the container

```bash
docker exec -it dvc bash

# Inside the container:
cd /workspace
dvc repro
dvc push   # → triggers auto-PR on next sync
dvc pull
```

## GitHub Actions (data-store repo)

Two workflows live in `data-store/.github/workflows/` and run automatically in the `data-store` repository.

### `auto-merge-dvc-sync.yml`

Triggers on every PR from a `dvc-sync/*` branch into `main`.

1. Polls GitHub until mergeability is computed (up to 10 attempts × 5 s)
2. **Mergeable** → merges automatically with a descriptive commit message
3. **Conflict** → adds a `needs-resolution` label and posts a comment with rebase instructions
4. **Timeout** → adds the same label and posts a warning comment; workflow fails so it shows up in the PR checks

> Conflicts are practically impossible with DVC cache files because they are content-addressed (named by their hash) and immutable — two sync branches always add *different* files.

### `cleanup-merged-branches.yml`

Triggers when a `dvc-sync/*` PR is closed as merged. Deletes the branch immediately so the remote stays clean.

---

## GitHub Pull Request format

Each auto-PR looks like:

> **DVC sync: my-hostname @ 20260326-143022**
>
> Automated DVC data sync from host `my-hostname` at `20260326-143022`.
>
> **14 cache file(s)** added to the DVC remote.
>
> Review the changes and merge into `main` to make this data available to the whole team via `dvc pull`.

If `GITHUB_TOKEN` is not set, the branch is still pushed but no PR is created — you'll see the URL in the container logs to open one manually.

## SSH authentication

The container mounts `SSH_KEY_PATH` (default `~/.ssh`) read-only into `/root/.ssh`, so git operations inside the container use your host keys.

On Windows, if the SSH agent service is disabled:

```bash
# Git Bash — start agent for this session
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Test
ssh -T git@github.com
```

To persist across sessions, add to `~/.bashrc`:

```bash
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent > ~/.ssh/agent.env
fi
if [[ ! "$SSH_AUTH_SOCK" ]]; then
    source ~/.ssh/agent.env > /dev/null
fi
ssh-add -l &>/dev/null || ssh-add ~/.ssh/id_ed25519
```

## Adding this setup to a new machine

```bash
git clone --recurse-submodules git@github.com:gpoleto-highq/dvc-git-shared.git
cd dvc-git-shared
cp .env.example .env   # add GITHUB_TOKEN + set WORKSPACE_REPO
docker compose up -d
```

That's it — the container pulls shared data and starts auto-syncing.
