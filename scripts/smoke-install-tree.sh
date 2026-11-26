#!/bin/bash
# Check the install tree through its public commands:
#   - `install-tree.py json` gives jq the tree, with derived skill paths;
#   - `install-tree.py check` passes on this checkout and fails on fixture
#     checkouts where an inventory entry has no tree node, or a tree node has
#     no inventory entry.
set -eu -o pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

install_tree() {
    uv run --quiet --no-project --script \
        "${DOTFILES_DIR}/scripts/install-tree.py" "$@"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# The real tree converts to JSON that jq reads.
install_tree json >"${tmp_dir}/tree.json"
node_field() {
    jq -er --arg path "$1" \
        ".nodes[] | select(.path == \$path) | $2" "${tmp_dir}/tree.json"
}
# The lock owns skill membership: read the pstack skills from it.
pstack_skills="$(jq -r '.skills | to_entries[]
    | select(.value.skillPath | startswith("harness/pstack/")) | .key' \
    "${DOTFILES_DIR}/.agents/skill-lock.json")"
[ -n "$pstack_skills" ] || fail "the skill lock must list pstack skills"
for skill in $pstack_skills; do
    [ "$(node_field "agents/skills/pstack/${skill}" .skill)" = "$skill" ] ||
        fail "pstack skill ${skill} must resolve to agents/skills/pstack/${skill}"
done
[ "$(node_field shell/zsh .required)" = true ] ||
    fail "shell/zsh must be required"

install_tree check >/dev/null || fail "check must pass on this checkout"

# Copy the checkout files that Git sees once; each case gets a fresh copy.
base="${tmp_dir}/base"
mkdir -p "$base"
git -C "$DOTFILES_DIR" ls-files -z --cached --others --exclude-standard |
    tar -C "$DOTFILES_DIR" --null --ignore-failed-read -T - -cf - 2>/dev/null |
    tar -C "$base" -xf -
fixture=""
new_fixture() {
    fixture="${tmp_dir}/case-$1"
    cp -a "$base" "$fixture"
}

# Run check on the fixture; it must fail and print the expected error.
expect_error() {
    local expected="$1" output
    if output="$(install_tree check --root "$fixture" 2>&1)"; then
        fail "check must fail with: ${expected}"
    fi
    grep -qF -- "$expected" <<<"$output" ||
        fail "check must print: ${expected}"$'\n'"Output:"$'\n'"${output}"
}

# Edit a JSON inventory of the fixture with a jq filter.
edit_json() {
    jq "$2" "${fixture}/$1" >"${fixture}/$1.new"
    mv "${fixture}/$1.new" "${fixture}/$1"
}

new_fixture tool-without-node
edit_json .agents/tool-versions.json \
    '.tools += [{name: "fixture-tool", scope: "core", group: "core"}]'
expect_error 'tool "fixture-tool" has no tree node'

# Append TOML to the fixture tree.
add_tree() {
    printf '\n%s\n' "$1" >>"${fixture}/config/install-tree.toml"
}

new_fixture tool-node-without-entry
add_tree '["cli/utils/ghost"]
label = "Ghost"
tools = ["ghost-tool"]'
expect_error 'cli/utils/ghost: tool "ghost-tool" has no inventory entry'

new_fixture link-without-node
printf '%s\n' 'core|all|config/fixture|.config/fixture' \
    >>"${fixture}/config/managed-links.tsv"
expect_error 'managed link "config/fixture" has no tree node'

new_fixture link-node-without-entry
add_tree '["cli/utils/ghost"]
label = "Ghost"
links = ["config/ghost"]'
expect_error 'cli/utils/ghost: managed link "config/ghost" has no inventory entry'

new_fixture app-without-node
printf '%s\n' 'cask "fixture-app"' >>"${fixture}/Brewfile"
expect_error 'macOS application "fixture-app" has no tree node'

new_fixture app-node-without-entry
add_tree '["apps/media/ghost"]
label = "Ghost"
casks = ["ghost-app"]'
expect_error 'apps/media/ghost: macOS application "ghost-app" has no inventory entry'

new_fixture file-node-without-file
add_tree '["cli/utils/ghost"]
label = "Ghost"
files = ["bootstrap.d/ghost.sh"]'
expect_error 'cli/utils/ghost: file "bootstrap.d/ghost.sh" does not exist'

new_fixture element-without-entry
add_tree '["cli/utils/ghost"]
label = "Ghost"'
expect_error 'cli/utils/ghost: element has no inventory entry'

new_fixture skill-without-author
edit_json .agents/skill-lock.json '.skills["fixture-skill"] = {
    skillPath: "skills/fixture-skill/SKILL.md", source: "fixture-owner/skills",
    sourceType: "github",
    sourceUrl: "https://github.com/fixture-owner/skills.git"}'
expect_error 'skill "fixture-skill" has no tree node: declare agents/skills/fixture-owner'

# Remove every skill of the GitHub account of the first skill outside harness/.
author="$(jq -r '[.skills[] | select(.skillPath | startswith("harness/") | not)]
    | first | .source | split("/") | first' "${base}/.agents/skill-lock.json")"
new_fixture author-without-skills
edit_json .agents/skill-lock.json "
    .skills |= with_entries(select(.value.source | startswith(\"${author}/\") | not))"
expect_error "agents/skills/${author}: no skill has this author"

new_fixture plugin-without-marketplace
edit_json .agents/plugin-manifest.json \
    '.plugins["fixture-plugin"] = {claude: "fixture-plugin@fixture-market"}'
expect_error 'plugin "fixture-plugin" has no tree node: declare agents/plugins/fixture-market'

# Remove every plugin of the marketplace of the first Codex plugin.
marketplace="$(jq -r '.codexPlugins[0] | split("@") | last' \
    "${base}/.agents/plugin-manifest.json")"
new_fixture marketplace-without-plugins
edit_json .agents/plugin-manifest.json "
    .codexPlugins |= map(select(endswith(\"@${marketplace}\") | not))
    | .plugins |= with_entries(select(
        (.value.claude // \"\") | endswith(\"@${marketplace}\") | not))"
expect_error "agents/plugins/${marketplace}: no plugin has this marketplace"

server="$(jq -r 'keys | first' "${base}/.agents/mcp-servers.json")"
new_fixture mcp-without-branch
sed -i '/^\["agents\/mcp"\]$/,/^$/d' "${fixture}/config/install-tree.toml"
expect_error "MCP server \"${server}\" has no tree node"

new_fixture node-below-derived-branch
add_tree '["agents/mcp/ghost"]
label = "Ghost"'
expect_error 'agents/mcp/ghost: declare nothing below agents/mcp'

new_fixture two-mcp-branches
add_tree '["dev/mcp"]
label = "Ghost"
derive = "mcp"'
expect_error 'derive "mcp" has more than one branch: agents/mcp, dev/mcp'

new_fixture dependency-without-node
add_tree '["cli/utils/ghost"]
label = "Ghost"
tools = ["jq"]
requires = ["agents/harness/ghost"]'
expect_error 'cli/utils/ghost: requires "agents/harness/ghost", which is not a tree node'

new_fixture tool-with-two-nodes
add_tree '["cli/utils/ghost"]
label = "Ghost"
tools = ["jq"]'
expect_error 'tool "jq" has more than one tree node: cli/utils/jq, cli/utils/ghost'

new_fixture unknown-condition
add_tree '["cli/utils/ghost"]
label = "Ghost"
tools = ["fixture-tool"]
conditions = ["gpu"]'
expect_error 'cli/utils/ghost: unknown condition "gpu"'

new_fixture unknown-key
add_tree '["cli/utils/ghost"]
label = "Ghost"
tool = "jq"'
expect_error 'cli/utils/ghost: unknown key "tool"'

new_fixture parent-after-child
add_tree '["ghost/child"]
label = "Child"
tools = ["fixture-tool"]

["ghost"]
label = "Ghost"'
expect_error 'ghost/child: declare the parent "ghost" first'

echo "[OK] Install tree converts to JSON and matches the inventories."
