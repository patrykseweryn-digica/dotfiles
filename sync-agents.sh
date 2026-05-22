#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_FILE="${DOTFILES_DIR}/AGENTS.md"
MCP_SERVERS="${DOTFILES_DIR}/.agents/mcp-servers.json"
CODEX_AGENTS_SOURCE="${DOTFILES_DIR}/config/codex/AGENTS.md"
CLAUDE_AGENTS_SOURCE="${DOTFILES_DIR}/config/claude/CLAUDE.md"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-${CODEX_HOME}/config.toml}"
CODEX_AGENTS_FILE="${CODEX_HOME}/AGENTS.md"
CLAUDE_AGENTS_FILE="${HOME}/.claude/CLAUDE.md"

QUIET=false
MANAGED_START="# dotfiles-managed-mcp-start"
MANAGED_END="# dotfiles-managed-mcp-end"

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not installed" >&2
    exit 1
fi

if [ ! -f "$AGENTS_FILE" ]; then
    echo "[ERROR] Agent instructions not found: $AGENTS_FILE" >&2
    exit 1
fi

if [ ! -f "$MCP_SERVERS" ]; then
    echo "[ERROR] MCP servers file not found: $MCP_SERVERS" >&2
    exit 1
fi

if [ ! -e "$CODEX_AGENTS_SOURCE" ] || [ ! -e "$CLAUDE_AGENTS_SOURCE" ]; then
    echo "[ERROR] Tool-specific agent instruction symlinks are missing" >&2
    exit 1
fi

log_info() {
    [ "$QUIET" = true ] && return
    echo "[INFO] $*"
}

link_file() {
    local source_path="$1"
    local target_path="$2"
    local backup_dir="${HOME}/.dotfiles-backup"

    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
        return
    fi

    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        mkdir -p "$backup_dir"
        local backup_name
        backup_name="$(basename "$target_path").$(date +%Y%m%d%H%M%S)"
        cp -rP "$target_path" "${backup_dir}/${backup_name}"
        rm -rf "$target_path"
        log_info "Backed up $target_path to ${backup_dir}/${backup_name}"
    fi

    mkdir -p "$(dirname "$target_path")"
    ln -s "$source_path" "$target_path"
    log_info "Linked $target_path -> $source_path"
}

render_codex_mcp_block() {
    {
        echo "$MANAGED_START"
        jq -r '
          to_entries[]
          | .key as $name
          | .value as $server
          | "[mcp_servers.\($name)]",
            (if $server.type == "http" then
                "url = \($server.url | @json)"
             else
                "command = \($server.command | @json)\nargs = \($server.args // [] | @json)"
             end),
            ""
        ' "$MCP_SERVERS"
        echo "$MANAGED_END"
    }
}

strip_codex_managed_mcp() {
    local source_file="$1"
    local names
    names="$(jq -r 'keys | join(" ")' "$MCP_SERVERS")"

    [ -f "$source_file" ] || return 0

    awk -v start="$MANAGED_START" -v end="$MANAGED_END" -v names="$names" '
        BEGIN {
            split(names, managed_names, " ")
            in_managed_block = 0
            skip_table = 0
        }

        function is_managed_header(line, i, exact, prefix) {
            for (i in managed_names) {
                exact = "[mcp_servers." managed_names[i] "]"
                prefix = "[mcp_servers." managed_names[i] "."
                if (line == exact || index(line, prefix) == 1) {
                    return 1
                }
            }
            return 0
        }

        $0 == start { in_managed_block = 1; next }
        $0 == end { in_managed_block = 0; next }
        in_managed_block { next }

        /^\[/ {
            skip_table = is_managed_header($0)
        }

        !skip_table { print }
    ' "$source_file"
}

render_codex_config() {
    local source_file="$1"
    local target_file="$2"
    local stripped
    local block

    stripped="$(mktemp)"
    block="$(mktemp)"
    strip_codex_managed_mcp "$source_file" > "$stripped"
    render_codex_mcp_block > "$block"

    awk '
        NF {
            while (blank_lines > 0) {
                print ""
                blank_lines--
            }
            print
            next
        }
        { blank_lines++ }
    ' "$stripped" > "$target_file"
    if [ -s "$target_file" ]; then
        printf '\n\n' >> "$target_file"
    fi
    cat "$block" >> "$target_file"

    rm -f "$stripped" "$block"
}

cmd_codex_install() {
    log_info "Installing Codex agent config..."
    mkdir -p "$CODEX_HOME"

    link_file "$CODEX_AGENTS_SOURCE" "$CODEX_AGENTS_FILE"

    local tmp
    tmp="$(mktemp)"
    render_codex_config "$CODEX_CONFIG" "$tmp"

    if [ -f "$CODEX_CONFIG" ] && cmp -s "$tmp" "$CODEX_CONFIG"; then
        rm -f "$tmp"
        log_info "Codex MCP config already in sync"
    else
        mv "$tmp" "$CODEX_CONFIG"
        log_info "Wrote $CODEX_CONFIG"
    fi
}

cmd_codex_check() {
    local tmp
    tmp="$(mktemp)"
    render_codex_config "$CODEX_CONFIG" "$tmp"

    if [ -f "$CODEX_CONFIG" ] && cmp -s "$tmp" "$CODEX_CONFIG"; then
        rm -f "$tmp"
        log_info "Codex MCP config in sync"
        return 0
    fi

    echo "[ERROR] Codex MCP config drift detected: $CODEX_CONFIG" >&2
    echo "Run: ./sync-agents.sh codex-install" >&2
    if [ -f "$CODEX_CONFIG" ]; then
        diff -u "$CODEX_CONFIG" "$tmp" >&2 || true
    fi
    rm -f "$tmp"
    return 1
}

cmd_claude_install() {
    log_info "Installing Claude agent config..."
    link_file "$CLAUDE_AGENTS_SOURCE" "$CLAUDE_AGENTS_FILE"
    if [ -f "$DOTFILES_DIR/sync-claude.sh" ]; then
        "$DOTFILES_DIR/sync-claude.sh" install
    else
        echo "[WARN] sync-claude.sh not found, skipping Claude adapter"
    fi
}

cmd_install() {
    cmd_codex_install
    cmd_claude_install

    log_info "Agent config sync complete"
}

while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --quiet) QUIET=true; shift ;;
        *) echo "[ERROR] Unknown flag: $1" >&2; exit 1 ;;
    esac
done

case "${1:-}" in
    install)
        cmd_install
        ;;
    codex-install)
        cmd_codex_install
        ;;
    codex-check)
        cmd_codex_check
        ;;
    claude-install)
        cmd_claude_install
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|codex-install|codex-check|claude-install}"
        echo
        echo "  install        Sync shared AGENTS.md, Codex MCP config, and Claude adapter"
        echo "  codex-install  Link AGENTS.md and generate Codex MCP config"
        echo "  codex-check    Exit 1 if Codex MCP config is out of sync"
        echo "  claude-install Delegate Claude-only installation to sync-claude.sh"
        exit 1
        ;;
esac
