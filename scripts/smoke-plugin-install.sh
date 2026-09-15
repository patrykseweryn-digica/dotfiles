#!/bin/bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
just_bin="$(command -v just)"
uv_bin="$(command -v uv)"
mkdir -p "$task_dir/fixture/scripts" "$task_dir/stubs"
cp "$repo/justfile" "$task_dir/fixture/justfile"
cat > "$task_dir/manifest.json" <<'JSON'
{"plugins":{},"marketplaces":{},"codexPlugins":["required@official"],
 "codexMarketplaces":{"official":"https://example.test/official.git"}}
JSON
cat > "$task_dir/codex" <<'STUB'
#!/bin/bash
set -eu
state="$HOME/.codex"
printf '%s\n' "$*" >> "$state/calls"
case "$*" in
'--version') echo 'codex 0.154.0' ;;
'plugin list --json') cat "$state/plugins.json" ;;
'plugin marketplace list --json') cat "$state/marketplaces.json" ;;
'plugin marketplace add https://example.test/official.git')
    jq '.marketplaces += [{name:"official",marketplaceSource:{sourceType:"git",
        source:"https://example.test/official.git"}}]' "$state/marketplaces.json" > "$state/next"
    mv "$state/next" "$state/marketplaces.json" ;;
'plugin add required@official')
    jq -e '.marketplaces | any(.[]; .name == "official")' "$state/marketplaces.json" >/dev/null
    [ "${FAIL_PLUGIN:-false}" = false ] || { echo 'download interrupted' >&2; exit 22; }
    jq '.installed |= (map(select(.pluginId != "required@official")) +
        [{pluginId:"required@official",installed:true,enabled:true,
          marketplaceSource:{sourceType:"git"}}])' "$state/plugins.json" > "$state/next"
    mv "$state/next" "$state/plugins.json" ;;
*) echo "Unexpected codex command: $*" >&2; exit 1 ;;
esac
STUB
cat > "$task_dir/fixture/scripts/agent-tools.sh" <<'STUB'
#!/bin/bash
set -eu
[ "$(node --version)" = fixture-node ]
cp "$PLUGIN_TEST_DIR/codex" "$HOME/.local/bin/codex"
chmod +x "$HOME/.local/bin/codex"
STUB
cat > "$task_dir/fixture/install.sh" <<'STUB'
#!/bin/bash
set -eu
source "$PLUGIN_TEST_REPO/install.sh"
# Keep the full main flow; replace unrelated external installers.
load_env() { :; }
setup_repo_git() { :; }
install_uv() { :; }
install_zsh() { :; }
install_oh_my_zsh() { :; }
install_pipx() { :; }
install_tools() { :; }
install_fonts() { :; }
install_terminal_colors() { :; }
install_macos_apps() { :; }
install_tmux_plugins() { :; }
pre-commit() { return 1; }
install_nvm() {
    mkdir -p "$HOME/.nvm/bin"
    printf '#!/bin/sh\necho fixture-node\n' > "$HOME/.nvm/bin/node"
    chmod +x "$HOME/.nvm/bin/node"
}
activate_node() { export PATH="$HOME/.nvm/bin:$PATH"; }
setup_dotfiles() { "$PLUGIN_TEST_REPO/sync-agents.sh" install; }
DOTFILES_DIR="$PLUGIN_TEST_DIR/fixture"
main
STUB
cat > "$task_dir/stubs/uname" <<'STUB'
#!/bin/sh
if [ "$1" = -s ]; then echo "$TEST_OS"; else echo "$TEST_ARCH"; fi
STUB
printf '#!/bin/sh\nexit 0\n' > "$task_dir/stubs/pi"
ln -s "$uv_bin" "$task_dir/stubs/uv"
chmod +x "$task_dir/fixture/install.sh" "$task_dir/fixture/scripts/agent-tools.sh" "$task_dir/stubs/pi" "$task_dir/stubs/uname"
printf '{"skills":{}}\n' > "$task_dir/skills.json"
mkdir -p "$task_dir/custom"
printf 'local MCP state\n' > "$task_dir/mcp-sentinel"
export PI_MCP_CONFIG="$task_dir/mcp-sentinel" KIMI_MCP_CONFIG="$task_dir/mcp-sentinel"
export PLUGIN_TEST_DIR="$task_dir" PLUGIN_TEST_REPO="$repo"
for platform in Linux-x86_64 Linux-arm64 Darwin-x86_64 Darwin-arm64; do
    TEST_OS="${platform%-*}"
    TEST_ARCH="${platform#*-}"
    export TEST_OS TEST_ARCH
    for state in empty partial complete retry; do
        task_home="$task_dir/$platform $state home"
        mkdir -p "$task_home/.codex"
        printf '{"installed":[]}\n' > "$task_home/.codex/plugins.json"
        printf '{"marketplaces":[]}\n' > "$task_home/.codex/marketplaces.json"
        if [ "$state" = partial ] || [ "$state" = complete ]; then
            printf '{"installed":[{"pluginId":"required@official","installed":true,"enabled":%s,"marketplaceSource":{"sourceType":"git"}},{"pluginId":"extra@extra","installed":true,"enabled":true,"marketplaceSource":{"sourceType":"git"}}]}\n' \
                "$([ "$state" = complete ] && echo true || echo false)" > "$task_home/.codex/plugins.json"
        fi
        run_install() {
            env -u CODEX_PLUGIN_LIST_FILE -u CODEX_MARKETPLACE_LIST_FILE \
                -u OPENCODE_CONFIG_DIR -u OPENCODE_CONFIG -u KIMI_CODE_HOME \
                -u PI_MCP_CONFIG -u KIMI_MCP_CONFIG \
                -u PI_CODING_AGENT_DIR -u PI_SKILLS_DIR -u PI_SETTINGS_FILE \
                -u CLAUDE_SETTINGS_FILE -u CLAUDE_USER_CONFIG \
                HOME="$task_home" CODEX_HOME="$task_home/.codex" \
                CODEX_REMOTE_PLUGIN_CACHE="$task_home/.codex/remote" \
                CODEX_CONFIG="$task_home/.codex/config.toml" \
                SKILL_LOCK_LIVE="$task_home/.agents/.skill-lock.json" \
                SKILL_LOCK_REPO="$task_dir/skills.json" \
                SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
                CODEX_PLUGIN_MANIFEST="$task_dir/manifest.json" \
                CLAUDE_MANIFEST="$task_dir/manifest.json" \
                PATH="$task_dir/stubs:/usr/bin:/bin" \
                "$just_bin" --justfile "$task_dir/fixture/justfile" install \
                > "$task_dir/output" 2>&1
        }
        if [ "$state" = retry ]; then
            if FAIL_PLUGIN=true run_install; then echo 'Failed install passed' >&2; exit 1; fi
            rg -q 'required@official' "$task_dir/output"
            rg -q 'download interrupted' "$task_dir/output"
        fi
        for _ in 1 2; do
            run_install || { cat "$task_dir/output" >&2; exit 1; }
            jq -e '.installed | any(.[]; .pluginId == "required@official" and .enabled)' \
                "$task_home/.codex/plugins.json" >/dev/null
        done
        if [ "$state" = partial ] || [ "$state" = complete ]; then
            jq -e '.installed | any(.[]; .pluginId == "extra@extra")' "$task_home/.codex/plugins.json" >/dev/null
        fi
        [ "$(rg -c '^plugin add required@official$' "$task_home/.codex/calls" || true)" = \
            "$([ "$state" = complete ] && echo '' || { [ "$state" = retry ] && echo 2 || echo 1; })" ]
    done
done
[ "$(cat "$task_dir/mcp-sentinel")" = 'local MCP state' ]
echo '[INFO] Full install plugin smoke test passed (external installers simulated)'
