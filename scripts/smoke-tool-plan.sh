#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
CORE_TOOLS="$DOTFILES_DIR/scripts/core-tools.sh"
INVENTORY="$DOTFILES_DIR/.agents/tool-versions.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

jq -e '
    all(.tools[] | select(.scope == "core");
        (.versionPolicy == "latest" or .versionPolicy == "pinned") and
        (has("github") | not) and
        (has("packages") | not) and
        (has("adapter") | not)) and
    ([.tools[] | select(.scope == "system") | .name] ==
        ["gnupg", "xclip"])
' "$INVENTORY" >/dev/null ||
    fail "core inventory is not fully provisioned by mise"
jq -e '
    def tool($name): .tools[] | select(.name == $name);
    (tool("gh") | .scope == "core" and .group == "core") and
    (tool("shellcheck") | .scope == "core" and .group == "core") and
    (tool("pnpm") | .scope == "core" and .group == "agents") and
    (tool("gnupg") | .group == "core" and .commands == ["gpg"] and
        .packages.brew == "gnupg" and .packages.apt == "gnupg")
' "$INVENTORY" >/dev/null ||
    fail "gh, shellcheck, pnpm and gnupg are not in the tool inventory"

# Tools with a zsh completion declare how to get it: a generator command or
# a file shipped in the mise install directory.
jq -e '
    def tool($name): .tools[] | select(.name == $name);
    def args($name): tool($name).zshCompletion.args;
    args("gh") == ["completion", "-s", "zsh"] and
    args("pnpm") == ["completion", "zsh"] and
    args("bitwarden") == ["completion", "--shell", "zsh"] and
    args("ripgrep") == ["--generate", "complete-zsh"] and
    args("fd") == ["--gen-completions", "zsh"] and
    args("delta") == ["--generate-completion", "zsh"] and
    args("bat") == ["--completion", "zsh"] and
    args("git-lfs") == ["completion", "zsh"] and
    tool("zoxide").zshCompletion == {"file": "completions/_zoxide"}
' "$INVENTORY" >/dev/null ||
    fail "inventory does not declare zsh completions of mise tools"

# Brewfile holds only desktop casks; CLI tools come from the inventory.
if grep -E '^brew ' "$DOTFILES_DIR/Brewfile"; then
    fail "Brewfile installs a CLI tool outside the install groups"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The machine group setting must not change fixture results.
export DOTFILES_ENV_FILE="${tmp_dir}/all-groups.env"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$DOTFILES_ENV_FILE"
home_dir="$tmp_dir/home"
mkdir -p "$home_dir/.local/bin"
mise_log="$tmp_dir/mise.log"

cat >"$home_dir/.local/bin/mise" <<'STUB'
#!/bin/bash
set -eu
case ":${MISE_TRUSTED_CONFIG_PATHS:-}:" in
*":$HOME/.config/mise/conf.d:"*) ;;
*) exit 3 ;;
esac
printf '%s\n' "$*" >>"$MISE_LOG"
action=""
for argument in "$@"; do
    case "$argument" in
    install | upgrade | which | exec | where) action="$argument"; break ;;
    esac
done
case "$action" in
install | upgrade) exit 0 ;;
exec)
    while [ "$1" != -- ]; do shift; done
    command_name="$2"
    case "$command_name" in
    git | tldr) exit 0 ;;
    esac
    # A generator prints a completion whose content follows the release.
    [ "${COMPLETION_FAIL:-}" != "$command_name" ] || exit 1
    printf '#compdef %s %s\n' "$command_name" "${COMPLETION_VERSION:-v1}"
    ;;
where)
    tool="${!#}"
    dir="$HOME/mise-installs/${tool//[:\/]/-}"
    mkdir -p "$dir/completions"
    printf '#compdef %s %s\n' "$tool" "${COMPLETION_VERSION:-v1}" \
        >"$dir/completions/_${tool}"
    printf '%s\n' "$dir"
    ;;
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
tool_list=$(jq -r '.tools[] | select(.scope == "core") | (.mise // .name)' \
    "$INVENTORY" | paste -sd ' ' -)
tool_count=$(jq '[.tools[] | select(.scope == "core")] | length' "$INVENTORY")
completion_commands=$(jq -r '.tools[] | select(.scope == "core" and
    has("zshCompletion")) | .commands[0]' "$INVENTORY")
completion_dir="$home_dir/.zfunc"

for target in Darwin:arm64 Linux:x86_64 Linux:arm64; do
    os="${target%%:*}"
    arch="${target#*:}"
    config="$tmp_dir/core-${os}-${arch}.toml"
    system_count=$(jq --arg platform "${os/Darwin/darwin}" \
        --arg arch "${arch/x86_64/x86_64}" '
        (($platform | ascii_downcase) + "-" + $arch) as $target |
        [.tools[] | select(.scope == "system") |
            select((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | index($target))] | length
    ' "$INVENTORY")
    : >"$mise_log"

    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        CORE_TOOLS_HAS_SUDO=false \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" plan \
        >"$tmp_dir/plan"
    rm -rf "$completion_dir"
    [ "$(wc -l <"$tmp_dir/plan" | tr -d ' ')" \
        -eq "$((tool_count + system_count + 1))" ] ||
        fail "public plan omitted tools for $target"
    [ "$(grep -c 'is available through mise$' "$tmp_dir/plan")" \
        -eq "$tool_count" ] || fail "public plan omitted mise tools for $target"
    awk -F '\t' 'NF != 4 || $2 != "tools" ||
        ($3 != "none" && $3 != "update") { exit 1 }' \
        "$tmp_dir/plan" || fail "public plan returned an invalid row for $target"

    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        CORE_TOOLS_HAS_SUDO=false \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" install
    grep -F -- "--cd $HOME install $tool_list" "$mise_log" >/dev/null ||
        fail "install did not use the common mise path for $target"
    [ "$(grep -c ' = "' "$config")" -eq "$tool_count" ] ||
        fail "generated mise config omitted tools for $target"
    grep -F '[tools]' "$config" >/dev/null ||
        fail "generated mise config has no tools table"
    grep -F '"aqua:neovim/neovim" = "latest"' "$config" >/dev/null ||
        fail "generated mise config omitted the declared backend"
    for entry in 'aqua:crate-ci/typos 1.52.2' \
        'aqua:sharkdp/hyperfine 2.0.0' 'aqua:watchexec/watchexec 2.8.0' \
        'aqua:errata-ai/vale 3.27.0'; do
        read -r source version <<<"$entry"
        grep -Fx "\"$source\" = \"$version\"" "$config" >/dev/null ||
            fail "generated config lost the $source pin"
    done
    if grep -E '^"just" = ' "$config"; then
        fail "just must use uv, not mise"
    fi
    # The aqua zipapp lacks dependencies for the host python3, e.g. 3.10.
    grep -Fx '"pypi:pre-commit" = "latest"' "$config" >/dev/null ||
        fail "pre-commit does not install as a Python package"
    for command_name in $completion_commands; do
        [ "$(cat "$completion_dir/_${command_name}")" = \
            "#compdef ${command_name} v1" ] ||
            fail "install did not write the $command_name completion for $target"
    done
    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        CORE_TOOLS_HAS_SUDO=false \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" plan |
        grep -Fx $'PASS\ttools\tnone\tZsh completions match installed tools' \
        >/dev/null || fail "plan did not pass written completions for $target"

    : >"$mise_log"
    CORE_TOOLS_OS="$os" CORE_TOOLS_ARCH="$arch" \
        CORE_TOOLS_HAS_SUDO=false \
        MISE_CORE_TOOLS_FILE="$config" "$CORE_TOOLS" update
    grep -F -- "--cd $HOME upgrade --global --no-prune $tool_list" \
        "$mise_log" >/dev/null ||
        fail "update did not use the common mise path for $target"
done

# A new release changes a completion; the plan names it and update rewrites it.
completion_plan() {
    CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 CORE_TOOLS_HAS_SUDO=false \
        MISE_CORE_TOOLS_FILE="$tmp_dir/completion.toml" "$CORE_TOOLS" plan |
        awk -F '\t' '$4 ~ /^Zsh completions/ { print $1 "\t" $3 "\t" $4 }'
}
printf '#compdef gh v2\n' >"$tmp_dir/gh-v2"
COMPLETION_VERSION=v2 completion_plan >"$tmp_dir/completion-plan"
grep -E $'^UPDATE\tupdate\tZsh completions are missing or outdated: .*gh' \
    "$tmp_dir/completion-plan" >/dev/null ||
    fail "plan did not name an outdated completion"
rm "$completion_dir/_zoxide"
[ "$(COMPLETION_VERSION=v1 completion_plan)" = \
    $'UPDATE\tupdate\tZsh completions are missing or outdated: zoxide' ] ||
    fail "plan did not name a missing shipped completion"
COMPLETION_VERSION=v2 CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    CORE_TOOLS_HAS_SUDO=false MISE_CORE_TOOLS_FILE="$tmp_dir/completion.toml" \
    "$CORE_TOOLS" update >/dev/null || fail "completion update failed"
cmp -s "$tmp_dir/gh-v2" "$completion_dir/_gh" ||
    fail "update did not rewrite an outdated completion"
[ "$(cat "$completion_dir/_zoxide")" = '#compdef zoxide v2' ] ||
    fail "update did not copy the shipped completion"
[ "$(COMPLETION_VERSION=v2 completion_plan)" = \
    $'PASS\tnone\tZsh completions match installed tools' ] ||
    fail "plan did not pass rewritten completions"

# A failed generator keeps its old completion and fails the update; other
# completions still update.
if COMPLETION_VERSION=v3 COMPLETION_FAIL=gh CORE_TOOLS_OS=Darwin \
    CORE_TOOLS_ARCH=arm64 CORE_TOOLS_HAS_SUDO=false \
    MISE_CORE_TOOLS_FILE="$tmp_dir/completion.toml" \
    "$CORE_TOOLS" update >"$tmp_dir/completion-fail" 2>&1; then
    fail "update passed with a failed completion generator"
fi
grep -F '[ERROR] gh: could not generate the zsh completion' \
    "$tmp_dir/completion-fail" >/dev/null ||
    fail "failed completion generator was not named"
cmp -s "$tmp_dir/gh-v2" "$completion_dir/_gh" ||
    fail "failed completion generator changed the old completion"
[ "$(cat "$completion_dir/_bat")" = '#compdef bat v3' ] ||
    fail "a failed generator stopped other completions"
for leftover in "$completion_dir"/.*; do
    case "${leftover##*/}" in
    . | ..) ;;
    *) [ ! -e "$leftover" ] || fail "completion update left $leftover" ;;
    esac
done

for invalid_completion in \
    '(.tools[] | select(.name == "gh")).zshCompletion = {"args": ["x"], "file": "y"}' \
    '(.tools[] | select(.name == "gh")).zshCompletion = {"args": []}' \
    '(.tools[] | select(.name == "gh")).zshCompletion = {"file": "../_gh"}' \
    '(.tools[] | select(.name == "gnupg")).zshCompletion = {"args": ["x"]}'; do
    jq "$invalid_completion" "$INVENTORY" >"$tmp_dir/invalid-completion.json"
    if TOOL_INVENTORY="$tmp_dir/invalid-completion.json" CORE_TOOLS_OS=Darwin \
        CORE_TOOLS_ARCH=arm64 "$CORE_TOOLS" plan >/dev/null 2>&1; then
        fail "inventory accepted an invalid completion: $invalid_completion"
    fi
done
echo "[INFO] zsh completions: written, updated, kept on failure, validated"

# The host may already have xclip; a fixture command keeps the plan stable.
xclip_fixture="$tmp_dir/xclip-fixture.json"
jq '(.tools[] | select(.name == "xclip")).commands = ["xclip-fixture"]' \
    "$INVENTORY" >"$xclip_fixture"
assert_xclip_plan() {
    local os="$1" arch="$2" has_sudo="$3" expected="$4"
    TOOL_INVENTORY="$xclip_fixture" CORE_TOOLS_OS="$os" \
        CORE_TOOLS_ARCH="$arch" CORE_TOOLS_HAS_SUDO="$has_sudo" \
        "$CORE_TOOLS" plan |
        grep -Fx "$expected" >/dev/null ||
        fail "unexpected xclip plan for $os/$arch sudo=$has_sudo"
}

assert_xclip_plan Linux arm64 false \
    $'SKIP\ttools\tnone\txclip requires sudo on linux-arm64'
assert_xclip_plan Linux x86_64 false \
    $'SKIP\ttools\tnone\txclip requires sudo on linux-x86_64'
assert_xclip_plan Linux arm64 true \
    $'FAIL\ttools\tupdate\txclip is missing'
assert_xclip_plan Linux x86_64 true \
    $'FAIL\ttools\tupdate\txclip is missing'

# The host may already have gpg; a fixture command keeps installs visible.
brew_fixture="$tmp_dir/brew-fixture.json"
jq '(.tools[] | select(.name == "gnupg")).commands = ["gpg-fixture"]' \
    "$xclip_fixture" >"$brew_fixture"
system_bin="$tmp_dir/system-bin"
system_log="$tmp_dir/system.log"
mkdir -p "$system_bin"
cat >"$system_bin/apt-get" <<'STUB'
#!/bin/bash
printf 'apt-get %s\n' "$*" >>"$SYSTEM_LOG"
case "${!#}" in
gnupg) command_name=gpg-fixture ;;
xclip) command_name=xclip-fixture ;;
*) command_name="${!#}" ;;
esac
printf '#!/bin/sh\n' >"$SYSTEM_BIN/$command_name"
chmod +x "$SYSTEM_BIN/$command_name"
STUB
cat >"$system_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$SYSTEM_LOG"
"$@"
STUB
chmod +x "$system_bin/apt-get" "$system_bin/sudo"
: >"$system_log"
TOOL_INVENTORY="$brew_fixture" \
    PATH="$system_bin:/usr/bin:/bin" SYSTEM_BIN="$system_bin" \
    SYSTEM_LOG="$system_log" \
    CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 \
    CORE_TOOLS_HAS_SUDO=true "$CORE_TOOLS" install >/dev/null
grep -Fx 'sudo apt-get install -y xclip' "$system_log" >/dev/null ||
    fail "sudo-aware install omitted xclip"
grep -Fx 'sudo apt-get install -y gnupg' "$system_log" >/dev/null ||
    fail "sudo-aware install omitted gnupg"
PATH="$system_bin:/usr/bin:/bin" assert_xclip_plan Linux arm64 false \
    $'PASS\ttools\tnone\txclip is available'

# Homebrew needs no sudo; Linux package managers do.
rm "$system_bin/gpg-fixture"
cat >"$system_bin/brew" <<'STUB'
#!/bin/bash
printf 'brew %s\n' "$*" >>"$SYSTEM_LOG"
printf '#!/bin/sh\n' >"$SYSTEM_BIN/gpg-fixture"
chmod +x "$SYSTEM_BIN/gpg-fixture"
STUB
chmod +x "$system_bin/brew"
gnupg_plan() {
    TOOL_INVENTORY="$brew_fixture" CORE_TOOLS_OS="$1" CORE_TOOLS_ARCH=arm64 \
        CORE_TOOLS_HAS_SUDO=false PATH="$system_bin:/usr/bin:/bin" \
        "$CORE_TOOLS" plan | awk -F '\t' '$4 ~ /^gnupg / { print $1 "\t" $4 }'
}
[ "$(gnupg_plan Darwin)" = "$(printf 'FAIL\tgnupg is missing')" ] ||
    fail "macOS plan skipped gnupg without sudo"
[ "$(TOOL_INVENTORY="$brew_fixture" CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    PATH=/usr/bin:/bin "$CORE_TOOLS" plan |
    awk -F '\t' '$4 ~ /^gnupg / { print $1 "\t" $4 }')" = \
    "$(printf 'SKIP\tgnupg requires brew on darwin-arm64')" ] ||
    fail "macOS plan without Homebrew did not skip gnupg"
[ "$(gnupg_plan Linux)" = \
    "$(printf 'SKIP\tgnupg requires sudo on linux-arm64')" ] ||
    fail "Linux plan did not require sudo for gnupg"
: >"$system_log"
TOOL_INVENTORY="$brew_fixture" PATH="$system_bin:/usr/bin:/bin" \
    SYSTEM_BIN="$system_bin" SYSTEM_LOG="$system_log" \
    CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    CORE_TOOLS_HAS_SUDO=false "$CORE_TOOLS" install >/dev/null
grep -Fx 'brew install gnupg' "$system_log" >/dev/null ||
    fail "macOS install without sudo omitted gnupg"
[ "$(gnupg_plan Darwin)" = "$(printf 'PASS\tgnupg is available')" ] ||
    fail "installed gnupg did not pass the plan"

for platform in darwin-arm64 darwin-x86_64 linux-arm64 linux-x86_64; do
    invalid_system="$tmp_dir/invalid-${platform}.json"
    jq --arg platform "$platform" '
        (.tools[] | select(.name == "xclip")) |=
            (del(.requires) | .platforms = [$platform])
    ' "$INVENTORY" >"$invalid_system"
    case "$platform" in
    darwin-*) os=Darwin; arch="${platform#darwin-}" ;;
    linux-*) os=Linux; arch="${platform#linux-}" ;;
    esac
    if TOOL_INVENTORY="$invalid_system" CORE_TOOLS_OS="$os" \
        CORE_TOOLS_ARCH="$arch" "$CORE_TOOLS" plan >/dev/null 2>&1; then
        fail "inventory accepted $platform without a no-sudo source or requirement"
    fi
done

invalid="$tmp_dir/invalid.json"
jq '.tools[0].github = {"repo":"example/demo"}' "$INVENTORY" >"$invalid"
if TOOL_INVENTORY="$invalid" CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >/dev/null 2>&1; then
    fail "core inventory accepted a custom GitHub source"
fi

missing_group="$tmp_dir/missing-group.json"
jq 'del(.tools[0].group)' "$INVENTORY" >"$missing_group"
if TOOL_INVENTORY="$missing_group" CORE_TOOLS_OS=Darwin CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >/dev/null 2>&1; then
    fail "core inventory accepted a tool without a group"
fi

# A core-scope tool of an unselected group is skipped by name and group.
grouped="$tmp_dir/grouped.json"
jq '.tools += [{"commands": ["demo-viewer"], "group": "desktop",
    "name": "demo-viewer", "scope": "core", "versionPolicy": "latest"}]' \
    "$INVENTORY" >"$grouped"
printf 'DOTFILES_GROUPS=core\n' >"$tmp_dir/core.env"
DOTFILES_ENV_FILE="$tmp_dir/core.env" TOOL_INVENTORY="$grouped" \
    CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 CORE_TOOLS_HAS_SUDO=false \
    "$CORE_TOOLS" plan >"$tmp_dir/grouped-plan"
grep -Fx $'SKIP\ttools\tnone\tdemo-viewer skipped: group desktop is not selected' \
    "$tmp_dir/grouped-plan" >/dev/null ||
    fail "core-only plan did not skip a desktop tool by group"
grep -F $'bitwarden is available through mise' "$tmp_dir/grouped-plan" \
    >/dev/null || fail "core-only plan omitted Bitwarden CLI"
: >"$mise_log"
DOTFILES_ENV_FILE="$tmp_dir/core.env" TOOL_INVENTORY="$grouped" \
    CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 CORE_TOOLS_HAS_SUDO=false \
    MISE_CORE_TOOLS_FILE="$tmp_dir/grouped.toml" \
    ZSH_COMPLETION_DIR="$tmp_dir/core-zfunc" \
    "$CORE_TOOLS" install >/dev/null
if grep -F demo-viewer "$mise_log" "$tmp_dir/grouped.toml"; then
    fail "core-only install provisioned a desktop tool"
fi
grep -Fx '"aqua:bitwarden/clients" = "latest"' "$tmp_dir/grouped.toml" \
    >/dev/null || fail "core-only install omitted native Bitwarden CLI"
[ -f "$tmp_dir/core-zfunc/_gh" ] && [ ! -e "$tmp_dir/core-zfunc/_pnpm" ] ||
    fail "core-only install did not limit completions to selected groups"
TOOL_INVENTORY="$grouped" \
    CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 CORE_TOOLS_HAS_SUDO=false \
    "$CORE_TOOLS" plan | grep -F 'demo-viewer is available through mise' \
    >/dev/null || fail "plan with all groups skipped a desktop tool"

if CORE_TOOLS_OS=Plan9 CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >/dev/null 2>&1; then
    fail "core plan accepted an unsupported platform"
fi

if grep -REn 'install_github_(binary|tree)|download_release_asset' \
    "$DOTFILES_DIR/bootstrap.d" "$CORE_TOOLS" >/dev/null; then
    fail "legacy GitHub release downloader remains"
fi

# A machine provisioned before mise must still get a plan and a bootstrap.
absent_mise="$tmp_dir/absent/bin/mise"
MISE_BIN="$absent_mise" CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 \
    "$CORE_TOOLS" plan >"$tmp_dir/plan-without-mise" ||
    fail "plan failed on a machine without mise"
[ "$(cat "$tmp_dir/plan-without-mise")" = \
    $'FAIL\ttools\tupdate\tmise is missing' ] ||
    fail "plan without mise did not request an update"

stub_bin="$tmp_dir/stub-bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
output=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then output="$2"; fi
    shift
done
printf '%s\n' 'cp "$MISE_STUB" "$MISE_INSTALL_PATH"' >"$output"
STUB
chmod +x "$stub_bin/curl"
: >"$mise_log"
MISE_STUB="$home_dir/.local/bin/mise" MISE_BIN="$absent_mise" \
    PATH="$stub_bin:$PATH" CORE_TOOLS_OS=Linux CORE_TOOLS_ARCH=arm64 \
    CORE_TOOLS_HAS_SUDO=false \
    MISE_CORE_TOOLS_FILE="$tmp_dir/core-bootstrap.toml" \
    "$CORE_TOOLS" update || fail "update failed on a machine without mise"
[ -x "$absent_mise" ] || fail "update did not bootstrap mise"
grep -F -- "upgrade --global --no-prune $tool_list" "$mise_log" >/dev/null ||
    fail "update did not continue after the mise bootstrap"

echo "[OK] core tool provisioning smoke test passed"
