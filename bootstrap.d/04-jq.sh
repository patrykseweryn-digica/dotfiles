#!/bin/bash

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        JQ_BIN="$(command -v jq)"
        export JQ_BIN
        echo "[INFO] jq is already installed"
        "$JQ_BIN" --version
        return 0
    fi

    install_mise || return 1
    echo "[INFO] Installing jq through mise before manifest validation..."
    run_global_mise install jq@latest || return 1
    JQ_BIN="$(run_global_mise exec jq@latest -- sh -c 'command -v jq')" || {
        echo "[ERROR] mise installed jq without an available command" >&2
        return 1
    }
    export JQ_BIN
    "$JQ_BIN" --version
}
