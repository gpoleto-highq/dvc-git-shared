FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    cron \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir dvc

# Git safe directory for mounted volumes
RUN git config --global --add safe.directory /workspace \
    && git config --global --add safe.directory /dvc-remote

WORKDIR /workspace

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
