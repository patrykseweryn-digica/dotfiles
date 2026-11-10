#!/bin/bash

# Enable shell script strictness
set -eu

# Detect if sudo is available
HAS_SUDO=false
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    HAS_SUDO=true
fi

# Detect OS and architecture
OS="$(uname -s)"   # "Linux" or "Darwin"
ARCH="$(uname -m)" # "x86_64" or "arm64"
export ARCH
export IS_MACOS=false
export IS_LINUX=false
if [ "$OS" = "Darwin" ]; then
    IS_MACOS=true
elif [ "$OS" = "Linux" ]; then
    IS_LINUX=true
fi

# Installation directory for user-local installs
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
OPT_DIR="${INSTALL_DIR}/opt"

# Source installation modules
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE="${DOTFILES_DIR}/.env.example"
ENV_FILE="${DOTFILES_ENV_FILE:-${DOTFILES_DIR}/.env}"

# shellcheck source=scripts/managed-links.sh
source "${DOTFILES_DIR}/scripts/managed-links.sh"

ensure_install_dirs() {
    mkdir -p "${BIN_DIR}" "${OPT_DIR}"

    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        export PATH="${BIN_DIR}:${PATH}"
    fi
}

ensure_env_file() {
    if [ ! -f "$ENV_TEMPLATE" ]; then
        echo "[ERROR] Missing environment template at $ENV_TEMPLATE" >&2
        exit 1
    fi

    if [ ! -f "$ENV_FILE" ]; then
        cp "$ENV_TEMPLATE" "$ENV_FILE"
        echo "[INFO] Created $ENV_FILE from template"
    fi
}

load_env() {
    ensure_env_file

    if [ ! -f "$ENV_FILE" ]; then
        echo "[ERROR] Environment file $ENV_FILE not found" >&2
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a

    if [ -z "${EMAIL:-}" ]; then
        echo "[ERROR] EMAIL is not set in $ENV_FILE" >&2
        exit 1
    fi

    if [ -z "${WORK_EMAIL:-}" ]; then
        echo "[ERROR] WORK_EMAIL is not set in $ENV_FILE" >&2
        exit 1
    fi

    if [ -z "${EDITOR:-}" ]; then
        EDITOR="vim"
    fi

    export EMAIL
    export WORK_EMAIL
    export EDITOR
    echo "[INFO] Loaded environment from $ENV_FILE"
}

DEBUG=false

usage() {
    echo "Usage: $0 [--sudo] [--debug]"
    echo
    echo "  --sudo, -s     Force enable sudo (skip auto-detection)"
    echo "  --debug        Enable verbose shell tracing"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -s | --sudo)
            HAS_SUDO=true
            ;;
        --debug)
            DEBUG=true
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        esac
        shift
    done
}

link_file() {
    local source_path="$1"
    local target_path="$2"
    local backup_dir="${HOME}/.dotfiles-backup"

    # Already a correct symlink - nothing to do
    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
        return
    fi

    # Target exists and is not our symlink - backup with drift warning
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        mkdir -p "$backup_dir"
        local backup_path
        backup_path=$(mktemp -d "${backup_dir}/$(basename "$target_path").XXXXXX") || return 1
        backup_path="${backup_path}/$(basename "$target_path")"
        cp -rP "$target_path" "$backup_path" || return 1

        # Drift warning: target differs from source
        if [ -f "$target_path" ] && [ -f "$source_path" ] && ! diff -q "$source_path" "$target_path" >/dev/null 2>&1; then
            echo "[WARN] $target_path differs from dotfiles source. Backed up to $backup_path"
            echo "[WARN] Diff (source vs target):"
            diff --color=auto "$source_path" "$target_path" | head -20 || true
        else
            echo "[INFO] Backed up $target_path to $backup_path"
        fi

        rm -rf "$target_path"
    fi

    ln -s "$source_path" "$target_path"
    echo "[INFO] Linked $target_path -> $source_path"
}

deploy_symlink_target() {
    local source_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "$target_path")"
    link_file "$source_path" "$target_path"
}

deploy_plain_absent_target() {
    local target_path="$1"

    if [ -L "$target_path" ]; then
        rm "$target_path"
        echo "[INFO] Removed legacy symlink: $target_path"
    fi
}

RUN_STEP_RESULTS=()
LAST_RUN_STEP_STATUS=0

record_step_result() {
    local label="$1"
    local result="$2"

    RUN_STEP_RESULTS+=("${result}|${label}")
}

print_step_summary() {
    local result label

    echo "[INFO] Installation step summary:"
    for entry in "${RUN_STEP_RESULTS[@]}"; do
        IFS='|' read -r result label <<<"$entry"
        echo "[INFO]   ${result}: ${label}"
    done
}

run_required_step() {
    local label="$1"
    shift

    echo "[INFO] Running required step: ${label}"
    set +e
    (
        set -e
        "$@"
    )
    LAST_RUN_STEP_STATUS=$?
    set -e

    if [ "$LAST_RUN_STEP_STATUS" -eq 0 ]; then
        record_step_result "$label" "ok"
    else
        record_step_result "$label" "failed"
        echo "[ERROR] Required step failed: ${label}" >&2
    fi

    return 0
}

run_optional_step() {
    local label="$1"
    shift

    echo "[INFO] Running optional step: ${label}"
    set +e
    (
        set -e
        "$@"
    )
    LAST_RUN_STEP_STATUS=$?
    set -e

    if [ "$LAST_RUN_STEP_STATUS" -eq 0 ]; then
        record_step_result "$label" "ok"
    else
        record_step_result "$label" "failed"
        echo "[WARN] Optional step failed: ${label}"
    fi

    return 0
}

for module in "${DOTFILES_DIR}/bootstrap.d"/*.sh; do
    if [ -f "$module" ]; then
        # shellcheck source=/dev/null
        source "$module"
    fi
done

setup_repo_git() {
    if [ ! -e "${DOTFILES_DIR}/.git" ]; then
        echo "[INFO] Skipping repository Git settings: not a Git checkout"
        return 0
    fi

    # Preserve published commits when combining the two remote histories.
    git -C "$DOTFILES_DIR" config --local pull.rebase false
    git -C "$DOTFILES_DIR" config --local branch.master.rebase false
}

update_managed_links() {
    local rows source_path target_path

    ensure_install_dirs
    rows="$(managed_link_rows)" || return 1
    while IFS='|' read -r source_path target_path; do
        deploy_symlink_target "$source_path" "$target_path"
    done <<<"$rows"
}

# Setup and link configuration files
setup_dotfiles() {
    echo "[INFO] Setting up dotfile configurations..."

    # Fail on dispatch conflicts before changing unrelated configuration.
    setup_firstmate || return $?
    ensure_install_dirs
    # Merge after tool installation; the update workflow also calls this.
    uv run --no-project --script "$DOTFILES_DIR/scripts/no-mistakes-config.py"
    uv run --no-project --script "$DOTFILES_DIR/scripts/herdr-config.py"
    mkdir -p "${HOME}/.claude/plugins" "${HOME}/.claude/output-styles" "${HOME}/.claude/skills" "${HOME}/.agents/skills" "${HOME}/.codex" "${HOME}/.summarize"
    update_managed_links
    deploy_plain_absent_target "$HOME/.claude/settings.json"

    # Link bin scripts
    for script in "$DOTFILES_DIR/bin"/*; do
        [ -f "$script" ] || continue
        chmod +x "$script"
        deploy_symlink_target "$script" "${BIN_DIR}/$(basename "$script")"
    done

    # Sync shared agent config plus tool-specific adapters.
    if [ -f "$DOTFILES_DIR/sync-agents.sh" ]; then
        "$DOTFILES_DIR/sync-agents.sh" install || return 1
    else
        echo "[WARN] sync-agents.sh not found, skipping agent config sync"
    fi

    echo "[INFO] Using environment variables defined in $ENV_FILE"

    # Source aliases
    if [ -f "$DOTFILES_DIR/.aliases" ]; then
        source "$DOTFILES_DIR/.aliases"
        echo "[INFO] Loaded aliases"
    else
        echo "[WARN] Aliases file not found"
    fi

    # Setup SSH key
    if [ "${DOTFILES_SKIP_SSH:-false}" = true ]; then
        echo "[INFO] Skipping SSH setup"
    elif [ -f "$DOTFILES_DIR/ssh.sh" ]; then
        echo "[INFO] Setting up SSH key..."
        "$DOTFILES_DIR/ssh.sh" "$EMAIL" "$WORK_EMAIL"
    else
        echo "[WARN] ssh.sh script not found"
    fi
}

# Main installation flow
main() {
    parse_args "$@"

    if [ "$DEBUG" = true ]; then
        set -x
    fi

    ensure_install_dirs
    load_env
    setup_repo_git

    echo "[INFO] Starting dotfiles installation..."
    echo "[INFO] Sudo available: ${HAS_SUDO}"
    echo "[INFO] Install directory: ${INSTALL_DIR}"
    RUN_STEP_RESULTS=()

    # Install tools. Required steps abort; optional failures are summarized.
    run_optional_step "uv" install_uv
    if [[ ":$PATH:" != *":${HOME}/.cargo/bin:"* ]]; then
        export PATH="${HOME}/.cargo/bin:${PATH}"
    fi
    run_required_step "zsh" install_zsh
    if [ "$LAST_RUN_STEP_STATUS" -ne 0 ]; then
        print_step_summary
        return "$LAST_RUN_STEP_STATUS"
    fi
    run_optional_step "Oh My Zsh" install_oh_my_zsh
    run_optional_step "pipx" install_pipx
    run_optional_step "CLI tools" install_tools
    run_optional_step "fonts" install_fonts
    run_required_step "NVM and Node.js" install_nvm
    if [ "$LAST_RUN_STEP_STATUS" -ne 0 ]; then
        print_step_summary
        return "$LAST_RUN_STEP_STATUS"
    fi
    # Step helpers use subshells, so activate Node in this shell for all CLIs.
    activate_node || {
        local status=$?
        record_step_result "Node activation" "failed"
        print_step_summary
        return "$status"
    }
    run_optional_step "developer tools" \
        "$DOTFILES_DIR/scripts/agent-tools.sh" install
    run_optional_step "terminal colors" install_terminal_colors
    if declare -f install_macos_apps >/dev/null 2>&1; then
        run_optional_step "macOS apps" install_macos_apps
    fi

    # Setup dotfile configurations
    run_required_step "dotfile links" setup_dotfiles
    if [ "$LAST_RUN_STEP_STATUS" -ne 0 ]; then
        print_step_summary
        return "$LAST_RUN_STEP_STATUS"
    fi
    run_optional_step "tmux plugins" install_tmux_plugins

    # Setup pre-commit hooks
    if pre-commit --version >/dev/null 2>&1; then
        echo "[INFO] Installing pre-commit hooks..."
        run_optional_step "pre-commit hooks" pre-commit install -c "${DOTFILES_DIR}/.pre-commit-config.yaml"
    fi

    print_step_summary
    echo "[INFO] Installation complete!"
    if [ -n "${ZSH_VERSION:-}" ]; then
        echo "[INFO] Please restart your shell or run: source ~/.zshrc"
    else
        echo "[INFO] Please restart your shell or run: exec zsh -l"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
