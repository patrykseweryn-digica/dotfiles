#!/bin/bash

install_claude_code() {
    echo "[INFO] Installing Claude Code..."

    if command -v claude >/dev/null 2>&1; then
        echo "[INFO] Claude Code is already installed"
    else
        if curl -fsSL https://claude.ai/install.sh | bash; then
            echo "[INFO] Claude Code installed successfully"
        else
            echo "[WARN] Failed to install Claude Code"
            return 1
        fi
    fi

    install_mcp_servers
    setup_mcp_auth
}

# Merge MCP server definitions from dotfiles into ~/.claude.json
install_mcp_servers() {
    local claude_json="$HOME/.claude.json"
    local mcp_source="${DOTFILES_DIR}/config/claude/mcp-servers.json"

    if [ ! -f "$mcp_source" ]; then
        echo "[WARN] MCP servers config not found at $mcp_source"
        return
    fi

    if ! check_installed python3; then
        echo "[WARN] python3 not found, skipping MCP server installation"
        return
    fi

    # Create ~/.claude.json if it doesn't exist
    if [ ! -f "$claude_json" ]; then
        echo '{}' > "$claude_json"
    fi

    echo "[INFO] Installing MCP servers into $claude_json..."

    python3 -c "
import json, sys

claude_json_path = sys.argv[1]
mcp_source_path = sys.argv[2]

with open(claude_json_path) as f:
    config = json.load(f)

with open(mcp_source_path) as f:
    mcp_servers = json.load(f)

existing = config.get('mcpServers', {})
added = []
updated = []

for name, server in mcp_servers.items():
    if name not in existing:
        added.append(name)
    elif existing[name] != server:
        updated.append(name)
    existing[name] = server

config['mcpServers'] = existing

with open(claude_json_path, 'w') as f:
    json.dump(config, f, indent=2)

for name in added:
    print(f'  + {name} (added)')
for name in updated:
    print(f'  ~ {name} (updated)')
if not added and not updated:
    print('  All MCP servers already up to date')
" "$claude_json" "$mcp_source"
}

setup_mcp_auth() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  MCP Server Authentication"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    setup_mcp_garmin
    setup_mcp_telegram
    setup_mcp_todoist

    echo "[INFO] Servers without auth are installed but won't connect until credentials are provided."
    echo ""
}

setup_mcp_garmin() {
    echo "[MCP] Garmin Connect"

    if [ -d "$HOME/.garminconnect" ] && [ -n "$(ls -A "$HOME/.garminconnect" 2>/dev/null)" ]; then
        echo "  ✓ Already authenticated (tokens in ~/.garminconnect)"
        echo ""
        return
    fi

    echo "  ✗ Not authenticated — tokens not found in ~/.garminconnect"
    echo ""
    echo "  Garmin MCP requires interactive login with your Garmin Connect credentials."

    if [ ! -t 0 ]; then
        echo "  [SKIP] Non-interactive terminal"
        echo "  Run later: uvx --python 3.12 --from 'git+https://github.com/Taxuspt/garmin_mcp' garmin-mcp-auth"
        echo ""
        return
    fi

    printf "  Authenticate now? [y/N] "
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        echo "  Starting Garmin authentication (enter credentials + MFA)..."
        if uvx --python 3.12 --from "git+https://github.com/Taxuspt/garmin_mcp" garmin-mcp-auth; then
            echo "  ✓ Garmin authenticated successfully"
        else
            echo "  ✗ Authentication failed — server installed but not functional"
            echo "  Retry: uvx --python 3.12 --from 'git+https://github.com/Taxuspt/garmin_mcp' garmin-mcp-auth"
        fi
    else
        echo "  [SKIP] Run later: uvx --python 3.12 --from 'git+https://github.com/Taxuspt/garmin_mcp' garmin-mcp-auth"
    fi
    echo ""
}

setup_mcp_telegram() {
    echo "[MCP] Telegram"

    if [ -n "${TELEGRAM_API_ID:-}" ] && [ -n "${TELEGRAM_API_HASH:-}" ]; then
        echo "  ✓ Configured (TELEGRAM_API_ID and TELEGRAM_API_HASH set)"
        echo ""
        return
    fi

    local env_file="${DOTFILES_DIR:-.}/.env"
    echo "  ✗ Missing TELEGRAM_API_ID and/or TELEGRAM_API_HASH"
    echo ""
    echo "  Get credentials at: https://my.telegram.org/apps"
    echo "  Then set in $env_file:"
    echo "    TELEGRAM_API_ID=<your_api_id>"
    echo "    TELEGRAM_API_HASH=<your_api_hash>"
    echo "    TELEGRAM_SESSION_STRING=<your_session_string>"
    echo ""
    echo "  [SKIP] Server installed but won't connect until credentials are set"
    echo ""
}

setup_mcp_todoist() {
    echo "[MCP] Todoist"
    echo "  OAuth — authenticate in Claude Code via /mcp → Todoist → Sign in"
    echo ""
}
