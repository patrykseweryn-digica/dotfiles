FROM ubuntu:24.04 AS prepared

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libncurses-dev \
        rsync \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

USER ubuntu
ENV HOME=/home/ubuntu
ENV DOTFILES_ENV_FILE=/home/ubuntu/ci.env
ENV DOTFILES_SKIP_CODEX_REMOTE_PLUGINS=true
ENV DOTFILES_SKIP_SSH=true
ENV DOTFILES_SKIP_SSH_AGENT=true
ENV MISE_TRUSTED_CONFIG_PATHS=/home/ubuntu/.config/mise/conf.d
ENV PATH=/home/ubuntu/.local/bin:/home/ubuntu/.local/share/mise/shims:/home/ubuntu/.cargo/bin:/home/ubuntu/.grok/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /home/ubuntu/repo

COPY --chown=ubuntu:ubuntu . .

RUN set -eux; \
    test "$(id -u)" -ne 0; \
    ! command -v sudo; \
    for command_name in jq just mise zsh; do \
        ! command -v "$command_name"; \
    done; \
    git init -b ci; \
    git config user.name "Dotfiles CI"; \
    git config user.email "ci@example.invalid"; \
    git add .; \
    git commit -m "test: create clean install fixture"; \
    git init --bare "$HOME/origin.git"; \
    git remote add origin "$HOME/origin.git"; \
    git push --set-upstream origin ci; \
    printf '%s\n' \
        'EMAIL=ci@example.invalid' \
        'WORK_EMAIL=ci@example.invalid' \
        'EDITOR=vim' >"$HOME/ci.env"

RUN --mount=type=secret,id=github_token,uid=1000,gid=1000,required=true \
    set -eu; \
    ./install.sh; \
    test -s /run/secrets/github_token; \
    GITHUB_TOKEN="$(cat /run/secrets/github_token)"; \
    export GITHUB_TOKEN; \
    if ! just sync >"$HOME/first-sync.log" 2>&1; then \
        grep -E '^\[(INFO|ERROR|FAILED|RESULT)\]' \
            "$HOME/first-sync.log" || true; \
        awk '/^\[REFRESH\] Node and agent tools$/ { show = 1 } \
            show { print } \
            /^\[REFRESH\] Pi packages$/ { exit }' \
            "$HOME/first-sync.log"; \
        tail -n 200 "$HOME/first-sync.log"; \
        exit 1; \
    fi; \
    if ! just sync >"$HOME/second-sync.log" 2>&1; then \
        tail -n 200 "$HOME/second-sync.log"; \
        exit 1; \
    fi; \
    grep -Fx '[RESULT] PASS' "$HOME/second-sync.log"; \
    just doctor; \
    test ! -e "$HOME/.ssh"

