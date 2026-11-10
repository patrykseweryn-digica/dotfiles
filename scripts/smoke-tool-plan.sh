#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_TOOLS="$DOTFILES_DIR/scripts/core-tools.sh"
INVENTORY="$DOTFILES_DIR/.agents/tool-versions.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

jq -e '
    all(.tools[] | select(.scope == "core");
        .versionPolicy == "latest" and
        (has("github") | not) and
        (has("packages") | not) and
        (has("adapter") | not)) and
    ([.tools[] | select(.scope == "system") | .name] == ["xclip"])
' "$INVENTORY" >/dev/null ||
    fail "core inventory is not fully provisioned by mise"

expected_brew=$(printf '%s\n' gh gnupg pnpm shellcheck)
actual_brew=$(sed -n 's/^brew "\([^"]*\)"$/\1/p' "$DOTFILES_DIR/Brewfile")
[ "$actual_brew" = "$expected_brew" ] ||
    fail "Brewfile repeats a managed tool"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
home_dir="$tmp_dir/home"
mkdir -p "$home_dir/.local/bin"
mise_log="$tmp_dir/mise.log"

cat >"$home_dir/.local/bin/mise" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >>"$MISE_LOG"
action=""
for argument in "$@"; do
    case "$argument" in
    install | upgrade | which | exec) action="$argument"; break ;;
    esac
done
case "$action" in
install | upgrade | exec) exit 0 ;;
which)
    command_name="${!#}"
    printf '%s/bin/%s\n' "$HOME" "$command_name"
    ;;
*) exit 2 ;;
esac
STUB
chmod +x "$home_dir/.local/bin/mise"

export HOME="$home_dir"
export MISE_BIN="$home_dir/.local/bin/mise"
export MISE_LOG="$mise_log"
export PATH="/usr/bin:/bin"
tool_list=$(jq -r '.tools[] | select(.scope == "core") | .name' \
    "$INVENTORY" | paste -sd ' ' -)
tool_count=$(jq '[.tools[] | select(.scope == "core")] | length' "$INVENTORY")

for target in Darwin:arm64 Linux:x86_64 Linux:arm64; do
    os="${target%%:*}"
    arch="${target#*:}"
    config="$tmp_dir/core-${os}-${arch}.toml"
    : >"$mise_log"

    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" plan \
        >"$tmp_dir/plan"
    [ "$(wc -l <"$tmp_dir/plan" | tr -d ' ')" -eq "$tool_count" ] ||
        fail "public plan omitted tools for $target"
    awk -F '\t' '$3 != "mise" { exit 1 }' "$tmp_dir/plan" ||
        fail "public plan used a non-mise core provider for $target"

    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" install
    grep -F -- "--cd $HOME install $tool_list" "$mise_log" >/dev/null ||
        fail "install did not use the common mise path for $target"
    [ "$(grep -c ' = "latest"$' "$config")" -eq "$tool_count" ] ||
        fail "generated mise config omitted tools for $target"
    grep -F '[tools]' "$config" >/dev/null ||
        fail "generated mise config has no tools table"

    : >"$mise_log"
    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" update
    grep -F -- "--cd $HOME upgrade --global --no-prune $tool_list" \
        "$mise_log" >/dev/null ||
        fail "update did not use the common mise path for $target"
done

invalid="$tmp_dir/invalid.json"
jq '.tools[0].github = {"repo":"example/demo"}' "$INVENTORY" >"$invalid"
if TOOL_INVENTORY="$invalid" CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >/dev/null 2>&1; then
    fail "core inventory accepted a custom GitHub source"
fi

if CORE_TOOLS_OS=Plan9 CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >/dev/null 2>&1; then
    fail "core plan accepted an unsupported platform"
fi

if grep -REn 'install_github_(binary|tree)|download_release_asset' \
    "$DOTFILES_DIR/bootstrap.d" "$CORE_TOOLS" >/dev/null; then
    fail "legacy GitHub release downloader remains"
fi

echo "[OK] core tool provisioning smoke test passed"
