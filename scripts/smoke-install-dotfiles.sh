#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"

# Hook-local Git state must not redirect fixture repositories or drift checks.
# shellcheck disable=SC2046
unset $(git -C "$DOTFILES_DIR" rev-parse --local-env-vars)

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

smoke_base_dir="$(mktemp -d)"
trap 'rm -rf "$smoke_base_dir"' EXIT
set_smoke_base_path "$smoke_base_dir"
UV_BIN="$(command -v uv)"
JUST_BIN="$(command -v just)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir)}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir)}"
# Runtime overrides must never escape the temporary HOME used by each case.
unset XDG_CONFIG_HOME DOTFILES_FIRSTMATE_HOME
unset CODEX_HOME CODEX_CONFIG CODEX_SETTINGS_TEMPLATE CODEX_PLUGIN_MANIFEST
unset CODEX_REMOTE_PLUGIN_CACHE CODEX_PLUGIN_LIST_FILE CODEX_MARKETPLACE_LIST_FILE
unset CLAUDE_SETTINGS_FILE CLAUDE_USER_CONFIG CLAUDE_TEMPLATE_FILE CLAUDE_MANIFEST
unset OPENCODE_CONFIG_DIR OPENCODE_CONFIG
unset PI_CODING_AGENT_DIR PI_SETTINGS_FILE PI_SKILLS_DIR PI_MCP_CONFIG
unset PI_SETTINGS_TEMPLATE PI_AGENTS_SOURCE SKILL_LOCK_LIVE SKILLS_CLI
unset PLUGIN_MANIFEST MCP_SERVERS SKILL_LOCK_REPO
unset HERDR_CONFIG_PATH
export SKILL_FIXTURE_LOCK="${DOTFILES_DIR}/.agents/skill-lock.json"

smoke_public_menu() {
    local actual expected
    actual="$(mktemp)"
    expected="$(mktemp)"
    "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" --summary |
        tr ' ' '\n' | sort >"$actual"
    printf '%s\n' disable doctor enable export groups install sync >"$expected"
    cmp "$expected" "$actual" ||
        fail "public menu is not the daily and install group commands"
    rm -f "$actual" "$expected"
}

smoke_jq_bootstrap() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    (
        export HOME="${tmp_dir}/home"
        mkdir -p "$HOME"
        : >"${tmp_dir}/mise.log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
        mkdir -p "$BIN_DIR"
        export PATH="$BIN_DIR"
        install_mise() { printf 'install-mise\n' >>"${tmp_dir}/mise.log"; }
        run_global_mise() {
            printf '%s\n' "$*" >>"${tmp_dir}/mise.log"
            if [ "$1" = use ]; then
                printf '#!/bin/sh\necho jq-1.8.2\n' >"${BIN_DIR}/jq"
                /bin/chmod +x "${BIN_DIR}/jq"
            else
                printf '%s\n' "${BIN_DIR}/jq"
            fi
        }
        ensure_jq >/dev/null
        jq --version >/dev/null
    )

    grep -Fx 'use --global jq@latest' "${tmp_dir}/mise.log" >/dev/null ||
        fail "jq bootstrap did not use mise"
    if grep -E 'apt-get|github' "${tmp_dir}/mise.log" >/dev/null; then
        fail "jq bootstrap used a legacy provider"
    fi

    rm -rf "$tmp_dir"
}

smoke_source_has_no_home_side_effect() {
    local tmp_dir
    local home_dir
    local env_file

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    env_file="${tmp_dir}/dotfiles.env"

    mkdir -p "$home_dir"

    (
        export HOME="$home_dir"
        export DOTFILES_ENV_FILE="$env_file"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
    )

    [ ! -e "${home_dir}/.local" ] || fail "sourcing install.sh should not create ~/.local"
    [ ! -e "$env_file" ] || fail "sourcing install.sh should not create env file"

    rm -rf "$tmp_dir"
}

smoke_run_steps_preserve_errexit() {
    local tmp_dir
    local home_dir
    local side_effect
    local step_log
    local rc

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    side_effect="${tmp_dir}/side-effect"
    step_log="${tmp_dir}/step.log"

    mkdir -p "$home_dir"

    (
        export HOME="$home_dir"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"

        bad_step() {
            false
            echo "errexit was ignored" >"$side_effect"
        }

        run_optional_step "bad optional" bad_step >"$step_log" 2>&1
        [ ! -e "$side_effect" ] || fail "optional step ignored errexit"
        printf '%s\n' "${RUN_STEP_RESULTS[@]}" | grep -q "failed|bad optional" ||
            fail "optional step failure was not recorded"

        run_required_step "bad required" bad_step >>"$step_log" 2>&1
        rc="$LAST_RUN_STEP_STATUS"
        [ "$rc" -ne 0 ] || fail "required step failure was not recorded"
        [ ! -e "$side_effect" ] || fail "required step ignored errexit"
    )

    rm -rf "$tmp_dir"
}

smoke_tmux_plugins_install_after_setup_dotfiles() {
    local tmp_dir
    local home_dir
    local stub_dir
    local env_file
    local npx_log
    local tmux_log

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    stub_dir="${tmp_dir}/stubs"
    env_file="${tmp_dir}/dotfiles.env"
    printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$env_file"
    npx_log="${tmp_dir}/npx.log"
    tmux_log="${tmp_dir}/tmux.log"

    mkdir -p "${home_dir}/.tmux/plugins/tpm/bin" "$stub_dir"
    ln -s "$UV_BIN" "${stub_dir}/uv"
    : >"$npx_log"
    : >"$tmux_log"

    cat >"${stub_dir}/skills" <<'STUB'
#!/bin/bash
set -eu
echo "skills $*" >> "$NPX_LOG"
skills=()
collect=false
for arg in "$@"; do
    if [ "$arg" = --skill ]; then
        collect=true
        continue
    fi
    if [ "$collect" = true ] && [[ "$arg" == --* ]]; then
        collect=false
    fi
    [ "$collect" = true ] && skills+=("$arg")
done
for skill in "${skills[@]}"; do
    name=$(jq -r --arg name "$skill" '
        .skills | to_entries[] |
        select((.value.installName // .key) == $name) |
        .key
    ' "$SKILL_FIXTURE_LOCK")
    [ -n "$name" ]
    mkdir -p "$HOME/.agents/skills/$name"
    printf '%s\n' '---' "name: $skill" '---' \
        > "$HOME/.agents/skills/$name/SKILL.md"
done
STUB
    chmod +x "${stub_dir}/skills"
    printf '#!/bin/sh\nexit 0\n' >"${stub_dir}/codex"
    chmod +x "${stub_dir}/codex"

    cat >"${home_dir}/.tmux/plugins/tpm/bin/install_plugins" <<'STUB'
#!/bin/sh
if [ ! -L "$HOME/.tmux.conf" ]; then
    echo "missing linked tmux config" >> "$TMUX_LOG"
    exit 42
fi
echo "tmux plugins installed with $(readlink "$HOME/.tmux.conf")" >> "$TMUX_LOG"
STUB
    chmod +x "${home_dir}/.tmux/plugins/tpm/bin/install_plugins"

    (
        export HOME="$home_dir"
        export PATH="${stub_dir}:${SMOKE_BASE_PATH}"
        export EMAIL="test@example.com"
        export WORK_EMAIL="work@example.com"
        export EDITOR="vim"
        export CODEX_HOME="${HOME}/.codex"
        export CODEX_PLUGIN_MANIFEST="${tmp_dir}/codex-plugins.json"
        printf '{"plugins":{},"marketplaces":{},"codexPlugins":[]}\n' >"$CODEX_PLUGIN_MANIFEST"
        export CODEX_PLUGIN_LIST_FILE="${tmp_dir}/codex-plugin-state.json"
        export CODEX_MARKETPLACE_LIST_FILE="${tmp_dir}/codex-marketplace-state.json"
        printf '{"installed":[]}\n' >"$CODEX_PLUGIN_LIST_FILE"
        printf '{"marketplaces":[]}\n' >"$CODEX_MARKETPLACE_LIST_FILE"
        export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
        export DOTFILES_SKIP_SSH=true
        export DOTFILES_ENV_FILE="$env_file"
        export NPX_LOG="$npx_log"
        export TMUX_LOG="$tmux_log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"

        export OS="Linux"
        export ARCH="x86_64"
        export IS_MACOS=false
        export IS_LINUX=true

        if ! setup_dotfiles >"${tmp_dir}/setup.log" 2>&1; then
            cat "${tmp_dir}/setup.log" >&2
            exit 1
        fi
        install_tmux_plugins >/dev/null 2>&1
    )

    grep -q "tmux plugins installed with ${DOTFILES_DIR}/.tmux.conf" "$tmux_log" ||
        fail "tmux plugins were not installed after .tmux.conf was linked"

    rm -rf "$tmp_dir"
}

smoke_pi_drift_check() {
    local tmp_dir home_dir pi_dir template git_dir

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    pi_dir="${home_dir}/.pi/agent"
    template="${tmp_dir}/settings.json"
    git_dir="${pi_dir}/git/example.test/example/package"

    mkdir -p "$git_dir" "${pi_dir}/npm/node_modules/example-package"
    printf 'fixture\n' >"${git_dir}/README.md"
    (
        git -C "$git_dir" init -q
        git -C "$git_dir" add README.md
        git -C "$git_dir" \
            -c user.name=Test \
            -c user.email=test@example.com \
            commit -qm fixture
    )

    jq -n '{
        packages: [
            "git:example.test/example/package",
            "npm:example-package"
        ]
    }' >"$template"
    jq -c '. + {
        lastChangelogVersion: "local-only",
        deviceId: "local-device",
        trackingId: "local-tracking",
        apiKeys: {fixture: "local-api-key"},
        extensionChangelogVersions: {"npm:example-package": "1.2.3"}
    }' "$template" \
        >"${pi_dir}/settings.json"
    printf '{"version":"1.2.3"}\n' \
        >"${pi_dir}/npm/node_modules/example-package/package.json"

    if ! HOME="$home_dir" \
        PI_CODING_AGENT_DIR="$pi_dir" \
        PI_SETTINGS_TEMPLATE="$template" \
        "${DOTFILES_DIR}/sync-agents.sh" --quiet pi-check; then
        fail "Pi check rejected matching settings and packages"
    fi

    jq '. + {hideThinkingBlock: false}' "${pi_dir}/settings.json" >"${tmp_dir}/drift.json"
    mv "${tmp_dir}/drift.json" "${pi_dir}/settings.json"
    if HOME="$home_dir" PI_CODING_AGENT_DIR="$pi_dir" \
        PI_SETTINGS_TEMPLATE="$template" \
        "${DOTFILES_DIR}/sync-agents.sh" --quiet pi-check >/dev/null 2>&1; then
        fail "Pi check ignored changed setting"
    fi
    cp "$template" "${pi_dir}/settings.json"
    rm "${pi_dir}/npm/node_modules/example-package/package.json"
    if HOME="$home_dir" \
        PI_CODING_AGENT_DIR="$pi_dir" \
        PI_SETTINGS_TEMPLATE="$template" \
        "${DOTFILES_DIR}/sync-agents.sh" --quiet pi-check \
        >/dev/null 2>&1; then
        fail "Pi check ignored missing package"
    fi

    jq '.deviceId = "template-device-sentinel"' "$template" \
        >"${tmp_dir}/unsafe-template.json"
    if HOME="$home_dir" PI_CODING_AGENT_DIR="$pi_dir" \
        PI_SETTINGS_TEMPLATE="${tmp_dir}/unsafe-template.json" \
        "${DOTFILES_DIR}/sync-agents.sh" --quiet pi-install \
        >"${tmp_dir}/unsafe-template.log" 2>&1; then
        fail "Pi install accepted an installation-local template key"
    fi
    grep -F 'deviceId' "${tmp_dir}/unsafe-template.log" >/dev/null ||
        fail "Pi install did not name the unsafe template key"
    if grep -F 'template-device-sentinel' \
        "${tmp_dir}/unsafe-template.log" >/dev/null; then
        fail "Pi install exposed an installation-local template value"
    fi

    rm -rf "$tmp_dir"
}

smoke_pi_package_update() {
    local tmp_dir home_dir template bin_dir log_file
    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    template="${tmp_dir}/settings.json"
    bin_dir="${tmp_dir}/bin"
    log_file="${tmp_dir}/pi.log"
    mkdir -p "$home_dir" "$bin_dir"
    printf '{"packages":["npm:example-package"]}\n' >"$template"
    cat >"${bin_dir}/pi" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$PI_TEST_LOG"
STUB
    chmod +x "${bin_dir}/pi"

    HOME="$home_dir" PATH="${bin_dir}:${SMOKE_BASE_PATH}" \
        PI_CODING_AGENT_DIR="${home_dir}/.pi/agent" \
        PI_SETTINGS_TEMPLATE="$template" PI_TEST_LOG="$log_file" \
        "$DOTFILES_DIR/sync-agents.sh" --quiet pi-packages-update

    grep -Fx 'install npm:example-package' "$log_file" >/dev/null ||
        fail "Pi update did not restore a missing package"
    grep -Fx 'update --extensions' "$log_file" >/dev/null ||
        fail "Pi update did not refresh extensions"
    rm -rf "$tmp_dir"
}

run_case() {
    local os_name="$1"
    local expected_code_dir="$2"
    local expected_ghostty_config="$3"
    local tmp_dir
    local home_dir
    local stub_dir
    local sync_log
    local env_file
    local npx_log
    local pi_log
    local zsh_backup

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    stub_dir="${tmp_dir}/stubs"
    sync_log="${tmp_dir}/sync.log"
    env_file="${tmp_dir}/dotfiles.env"
    printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$env_file"
    npx_log="${tmp_dir}/npx.log"
    pi_log="${tmp_dir}/pi.log"

    mkdir -p "$home_dir" "$stub_dir"
    printf 'local zsh drift\n' >"${home_dir}/.zshrc"
    ln -s "$UV_BIN" "${stub_dir}/uv"
    : >"$npx_log"
    : >"$pi_log"
    if [ "$os_name" = Darwin ]; then
        mkdir -p "${home_dir}/.no-mistakes"
        cat >"${home_dir}/.no-mistakes/config.yaml" <<'YAML'
# Keep workstation settings local.
agent: [claude, codex]
ci_timeout: 168h
agent_config:
  codex:
    model: local-model
    effort: low
auto_fix:
  review: 0
worktree_roots:
  /example/repo: /example/worktrees
YAML
    fi
    if [ "$os_name" = Darwin ]; then
        mkdir -p "${home_dir}/.config/herdr"
        cat >"${home_dir}/.config/herdr/config.toml" <<'TOML'
# Local preferences survive installation.
onboarding = false
[theme]
name = "catppuccin"
auto_switch = false
[ui]
status_indicators = "dots"
[ui.toast]
delivery = "herdr"
[ui.sidebar.agents]
row_gap = 1
rows = [["state_icon", "agent"]]
TOML
        cp "${home_dir}/.config/herdr/config.toml" "${tmp_dir}/herdr-before.toml"
    fi
    mkdir -p "${home_dir}/.pi/agent"
    cat >"${home_dir}/.pi/agent/settings.json" <<'JSON'
{
  "lastChangelogVersion": "local-only",
  "deviceId": "local-device",
  "trackingId": "local-tracking",
  "apiKeys": {"fixture": "local-api-key"},
  "extensionChangelogVersions": {"npm:example-package": "1.2.3"},
  "theme": "unmanaged"
}
JSON

    cat >"${stub_dir}/skills" <<'STUB'
#!/bin/bash
set -eu
echo "skills $*" >> "$NPX_LOG"
skills=()
collect=false
for arg in "$@"; do
    if [ "$arg" = --skill ]; then
        collect=true
        continue
    fi
    if [ "$collect" = true ] && [[ "$arg" == --* ]]; then
        collect=false
    fi
    [ "$collect" = true ] && skills+=("$arg")
done
for skill in "${skills[@]}"; do
    name=$(jq -r --arg name "$skill" '
        .skills | to_entries[] |
        select((.value.installName // .key) == $name) |
        .key
    ' "$SKILL_FIXTURE_LOCK")
    [ -n "$name" ]
    mkdir -p "$HOME/.agents/skills/$name"
    printf '%s\n' '---' "name: $skill" '---' \
        > "$HOME/.agents/skills/$name/SKILL.md"
done
STUB
    chmod +x "${stub_dir}/skills"
    printf '#!/bin/sh\nexit 0\n' >"${stub_dir}/codex"
    chmod +x "${stub_dir}/codex"

    cat >"${stub_dir}/pi" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$PI_LOG"
STUB
    chmod +x "${stub_dir}/pi"

    (
        export HOME="$home_dir"
        export PATH="${stub_dir}:${SMOKE_BASE_PATH}"
        export EMAIL="test@example.com"
        export WORK_EMAIL="work@example.com"
        export EDITOR="vim"
        export CODEX_HOME="${HOME}/.codex"
        export CODEX_PLUGIN_MANIFEST="${tmp_dir}/codex-plugins.json"
        printf '{"plugins":{},"marketplaces":{},"codexPlugins":[]}\n' >"$CODEX_PLUGIN_MANIFEST"
        export CODEX_PLUGIN_LIST_FILE="${tmp_dir}/codex-plugin-state.json"
        export CODEX_MARKETPLACE_LIST_FILE="${tmp_dir}/codex-marketplace-state.json"
        printf '{"installed":[]}\n' >"$CODEX_PLUGIN_LIST_FILE"
        printf '{"marketplaces":[]}\n' >"$CODEX_MARKETPLACE_LIST_FILE"
        export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
        export DOTFILES_SKIP_SSH=true
        export DOTFILES_ENV_FILE="$env_file"
        export NPX_LOG="$npx_log"
        export PI_LOG="$pi_log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"

        export OS="$os_name"
        export ARCH="arm64"
        export IS_MACOS=false
        export IS_LINUX=false
        if [ "$OS" = "Darwin" ]; then
            export IS_MACOS=true
        else
            export IS_LINUX=true
        fi

        if ! setup_dotfiles >"$sync_log" 2>&1; then
            cat "$sync_log" >&2
            exit 1
        fi
        local skill_install_count
        skill_install_count="$(wc -l <"$npx_log" | tr -d ' ')"
        [ "$skill_install_count" -gt 0 ] || fail "$os_name: skills were not installed"
        local config="${HOME}/.no-mistakes/config.yaml"
        [ -f "$config" ] || fail "$os_name: missing no-mistakes config"
        if [ "$os_name" = Darwin ]; then
            cat >"${tmp_dir}/expected.yaml" <<'YAML'
# Keep workstation settings local.
agent: codex
ci_timeout: 168h
agent_config:
  codex:
    model: local-model
    effort: low
auto_fix:
  review: 0
worktree_roots:
  /example/repo: /example/worktrees
YAML
        else
            printf 'agent: codex\n' >"${tmp_dir}/expected.yaml"
        fi
        cmp "$config" "${tmp_dir}/expected.yaml" ||
            fail "$os_name: no-mistakes settings differ"
        if ! setup_dotfiles >>"$sync_log" 2>&1; then
            cat "$sync_log" >&2
            exit 1
        fi
        [ "$(wc -l <"$npx_log" | tr -d ' ')" -eq "$skill_install_count" ] ||
            fail "$os_name: repeated setup reinstalled matching skills"
        cmp "$config" "${tmp_dir}/expected.yaml" ||
            fail "$os_name: repeated setup changed no-mistakes settings"
        echo "[INFO] $os_name: no-mistakes fresh/existing + repeat passed"

        local herdr_config="${HOME}/.config/herdr/config.toml"
        if [ "$os_name" = Darwin ]; then
            sed 's/rows = .*/rows = [["state_icon", "agent"], ["terminal_title"]]/' \
                "${tmp_dir}/herdr-before.toml" >"${tmp_dir}/herdr-expected.toml"
        else
            cp "$DOTFILES_DIR/config/herdr/config.toml" "${tmp_dir}/herdr-expected.toml"
        fi
        cmp "$herdr_config" "${tmp_dir}/herdr-expected.toml" ||
            fail "$os_name: Herdr settings lost or title missing after repeat"
        if [ "$os_name" = Darwin ]; then
            cp "${tmp_dir}/herdr-before.toml" "$herdr_config"
        else
            rm "$herdr_config"
        fi
        if ! setup_dotfiles >>"$sync_log" 2>&1; then
            cat "$sync_log" >&2
            exit 1
        fi
        [ "$(wc -l <"$npx_log" | tr -d ' ')" -eq "$skill_install_count" ] ||
            fail "$os_name: unrelated config repair reinstalled matching skills"
        cmp "$herdr_config" "${tmp_dir}/herdr-expected.toml" ||
            fail "$os_name: Herdr title not restored or local settings lost"
        echo "[INFO] $os_name: Herdr fresh/existing + repeat + restore passed"
    )

    [ -L "${home_dir}/.zshrc" ] || fail "$os_name: missing .zshrc symlink"
    zsh_backup="$(find "${home_dir}/.dotfiles-backup" -type f \
        -name .zshrc -print -quit)"
    [ -n "$zsh_backup" ] || fail "$os_name: missing .zshrc backup"
    grep -Fx 'local zsh drift' "$zsh_backup" >/dev/null ||
        fail "$os_name: .zshrc backup lost drift"
    grep -F "[WARN] ${home_dir}/.zshrc differs from dotfiles source" \
        "$sync_log" >/dev/null || fail "$os_name: missing drift warning"
    [ "$(cat "$env_file")" = 'DOTFILES_GROUPS=core,agents,desktop' ] ||
        fail "$os_name: setup_dotfiles should not change the env file when sourced"
    [ -L "${home_dir}/${expected_code_dir}/settings.json" ] || fail "$os_name: missing VS Code settings symlink"
    [ -L "${home_dir}/${expected_ghostty_config}" ] || fail "$os_name: missing Ghostty config symlink"
    [ -L "${home_dir}/.claude/CLAUDE.md" ] || fail "$os_name: missing Claude instructions symlink"
    [ -L "${home_dir}/.claude/settings.local.json" ] || fail "$os_name: missing Claude local settings symlink"
    [ -L "${home_dir}/.summarize/config.json" ] || fail "$os_name: missing summarize config symlink"
    [ -L "${home_dir}/.codex/AGENTS.md" ] || fail "$os_name: missing Codex instructions symlink"
    [ -L "${home_dir}/.config/opencode/AGENTS.md" ] || fail "$os_name: missing OpenCode instructions symlink"
    [ -L "${home_dir}/.pi/agent/AGENTS.md" ] || fail "$os_name: missing Pi instructions symlink"
    [ -f "${home_dir}/.pi/agent/settings.json" ] || fail "$os_name: missing Pi settings"
    jq -e --slurpfile wanted "${DOTFILES_DIR}/config/pi/settings.json" '
        .lastChangelogVersion == "local-only" and
        .deviceId == "local-device" and
        .trackingId == "local-tracking" and
        .apiKeys == {fixture: "local-api-key"} and
        .extensionChangelogVersions == {"npm:example-package": "1.2.3"} and
        (del(
            .lastChangelogVersion,
            .deviceId,
            .trackingId,
            .apiKeys,
            .extensionChangelogVersions
        ) == $wanted[0])
    ' "${home_dir}/.pi/agent/settings.json" >/dev/null ||
        fail "$os_name: Pi stable settings or local changelog state differ"
    while IFS= read -r package; do
        grep -Fx "install $package" "$pi_log" >/dev/null ||
            fail "$os_name: Pi package was not restored: $package"
    done < <(jq -r '.packages[]' "${DOTFILES_DIR}/config/pi/settings.json")
    for resource in themes/rose-pine-moon.json extensions/terminal-title.ts; do
        cmp -s "${DOTFILES_DIR}/config/pi/$resource" \
            "${home_dir}/.pi/agent/$resource" || fail "missing Pi $resource"
    done
    cp "${home_dir}/.pi/agent/settings.json" "${tmp_dir}/pi-settings.before"
    HOME="$home_dir" PATH="${stub_dir}:${SMOKE_BASE_PATH}" PI_LOG="$pi_log" \
        "${DOTFILES_DIR}/sync-agents.sh" pi-install >/dev/null
    cmp "${tmp_dir}/pi-settings.before" \
        "${home_dir}/.pi/agent/settings.json" ||
        fail "$os_name: repeated Pi install rewrote stable settings"
    [ "$(find "${home_dir}/.pi/agent/extensions" -name terminal-title.ts | wc -l)" -eq 1 ] ||
        fail "Pi repeat install duplicated extension"
    [ -f "${home_dir}/.codex/config.toml" ] || fail "$os_name: missing Codex config"
    [ -f "${home_dir}/.config/opencode/opencode.json" ] || fail "$os_name: missing OpenCode config"

    if [ -L "${home_dir}/.claude/settings.json" ]; then
        fail "$os_name: Claude settings must be generated as a plain file, not symlinked"
    fi
    [ -f "${home_dir}/.claude/settings.json" ] || fail "$os_name: missing generated Claude settings"
    [ -s "$npx_log" ] ||
        fail "$os_name: sync should install required skills"

    rm -rf "$tmp_dir"
}

smoke_node_activation_before_tools() {
    local task_dir outcome
    task_dir="$(mktemp -d)"
    mkdir -p "${task_dir}/fixture/scripts" "${task_dir}/node/bin"
    printf '#!/bin/sh\nprintf "configured-node\\n"\n' >"${task_dir}/node/bin/node"
    cat >"${task_dir}/fixture/scripts/agent-tools.sh" <<'STUB'
#!/bin/sh
[ "$(node --version)" = configured-node ] || exit 42
printf 'installed\n' >"$TOOLS_INSTALLED"
STUB
    chmod +x "${task_dir}/node/bin/node" "${task_dir}/fixture/scripts/agent-tools.sh"
    printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"${task_dir}/all-groups.env"

    for outcome in success failure; do
        rm -f "${task_dir}/installed"
        rm -f "${task_dir}/jq-ready"
        (
            export HOME="${task_dir}/home"
            export TOOLS_INSTALLED="${task_dir}/installed"
            export DOTFILES_ENV_FILE="${task_dir}/all-groups.env"
            # shellcheck source=/dev/null
            source "${DOTFILES_DIR}/install.sh"
            export DOTFILES_DIR="${task_dir}/fixture"
            load_env() { :; }
            setup_repo_git() { :; }
            setup_dotfiles() { [ -f "$TOOLS_INSTALLED" ]; }
            install_uv() { :; }
            install_zsh() { :; }
            install_oh_my_zsh() { :; }
            install_pipx() { :; }
            ensure_jq() { touch "${task_dir}/jq-ready"; }
            install_tools() { [ -f "${task_dir}/jq-ready" ]; }
            install_fonts() { :; }
            install_terminal_colors() { :; }
            install_macos_apps() { :; }
            install_tmux_plugins() { :; }
            prek() { return 1; }
            install_node() { [ "$outcome" = success ]; }
            activate_node() { export PATH="${task_dir}/node/bin:$PATH"; }
            main
        ) >"${task_dir}/${outcome}.log" 2>&1 && {
            [ "$outcome" = success ] || fail "Node failure did not stop installation"
        }
        if [ "$outcome" = success ]; then
            [ -f "${task_dir}/installed" ] || fail "tools did not use activated Node"
        else
            [ ! -f "${task_dir}/installed" ] || fail "tools ran after Node failure"
        fi
    done
    rm -rf "$task_dir"
}

smoke_prek_replaces_pre_commit_hook() {
    local tmp_dir prek_bin hooks shim custom
    prek_bin="$(command -v prek)" || fail "prek is required for the Git hook test"
    tmp_dir="$(mktemp -d)"
    hooks="${tmp_dir}/fixture/.git/hooks"
    shim=$'#!/bin/sh\n# File generated by pre-commit: https://pre-commit.com\n'
    custom=$'#!/bin/sh\necho custom hook\n'
    mkdir -p "${tmp_dir}/home" "${tmp_dir}/bin"
    ln -s "$prek_bin" "${tmp_dir}/bin/prek"
    HOME="${tmp_dir}/home" GIT_CONFIG_NOSYSTEM=1 git init -q "${tmp_dir}/fixture"
    printf 'repos: []\n' >"${tmp_dir}/fixture/.pre-commit-config.yaml"

    install_hook() {
        (
            export HOME="${tmp_dir}/home" PATH="${tmp_dir}/bin:${SMOKE_BASE_PATH}"
            # shellcheck source=/dev/null
            source "${DOTFILES_DIR}/install.sh"
            DOTFILES_DIR="${tmp_dir}/fixture"
            install_git_hooks
        ) >>"${tmp_dir}/install.log" 2>&1 || {
            cat "${tmp_dir}/install.log" >&2
            fail "prek hook installation failed"
        }
    }

    # The old shim must not stay behind as a legacy hook that runs pre-commit.
    printf '%s' "$shim" >"${hooks}/pre-commit"
    install_hook
    grep -F 'File generated by prek' "${hooks}/pre-commit" >/dev/null ||
        fail "install did not write the prek Git hook"
    [ ! -e "${hooks}/pre-commit.legacy" ] ||
        fail "install kept the pre-commit hook as a legacy hook"
    install_hook
    [ ! -e "${hooks}/pre-commit.legacy" ] ||
        fail "repeated install created a legacy hook"

    # A user's own hook survives as prek's legacy hook.
    printf '%s' "$custom" >"${hooks}/pre-commit"
    install_hook
    [ "$(cat "${hooks}/pre-commit.legacy")" = "${custom%$'\n'}" ] ||
        fail "install did not preserve a custom Git hook"
    rm -rf "$tmp_dir"
}

smoke_no_mistakes_config() {
    local tmp_dir config agent
    tmp_dir="$(mktemp -d)"
    config="${tmp_dir}/.no-mistakes/config.yaml"
    mkdir -p "$(dirname "$config")"
    for agent in auto claude '"claude"' ''; do
        printf '# local comment\nci_timeout: 168h\n' >"$config"
        [ -z "$agent" ] || printf 'agent: %s\n' "$agent" >>"$config"
        chmod 640 "$config"
        HOME="$tmp_dir" "$UV_BIN" run --no-project --script \
            "$DOTFILES_DIR/scripts/no-mistakes-config.py"
        grep -Eq '^agent: "?codex"?$' "$config" || fail "agent not codex"
        grep -q '^# local comment$' "$config" || fail "comment lost"
        grep -q '^ci_timeout: 168h$' "$config" || fail "setting lost"
        [ "$(find "$config" -perm 640 | wc -l)" -eq 1 ] || fail "mode changed"
        cp "$config" "${tmp_dir}/before.yaml"
        HOME="$tmp_dir" "$UV_BIN" run --no-project --script \
            "$DOTFILES_DIR/scripts/no-mistakes-config.py"
        cmp "$config" "${tmp_dir}/before.yaml" || fail "repeat changed config"
    done
    for agent in 'agent: [' '- claude' $'agent: claude\nagent: auto'; do
        printf '%s\n' "$agent" >"$config"
        cp "$config" "${tmp_dir}/before.yaml"
        if HOME="$tmp_dir" "$UV_BIN" run --no-project --script \
            "$DOTFILES_DIR/scripts/no-mistakes-config.py" \
            >"${tmp_dir}/error.log" 2>&1; then
            fail "invalid config accepted"
        fi
        cmp "$config" "${tmp_dir}/before.yaml" || fail "invalid config overwritten"
    done
    rm -rf "$tmp_dir"
    echo '[INFO] no-mistakes scalar/missing agents, permissions, invalid YAML passed'
}

smoke_no_mistakes_config
smoke_prek_replaces_pre_commit_hook
smoke_public_menu
smoke_jq_bootstrap
smoke_node_activation_before_tools
smoke_source_has_no_home_side_effect
smoke_run_steps_preserve_errexit
smoke_tmux_plugins_install_after_setup_dotfiles
smoke_pi_drift_check
smoke_pi_package_update
run_case "Linux" ".config/Code/User" ".config/ghostty/config"
run_case "Darwin" "Library/Application Support/Code/User" "Library/Application Support/com.mitchellh.ghostty/config.ghostty"

echo "[INFO] install dotfiles smoke test passed"
