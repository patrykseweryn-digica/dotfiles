#!/usr/bin/env -S uv run --no-project --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Check prek's real selection against the smoke fixtures' repository inputs."""

import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from fnmatch import fnmatchcase
from pathlib import Path
from posixpath import normpath
from tempfile import TemporaryDirectory

# Audit the code the fixtures actually source, execute or inspect, including
# conditional branches. Do not derive this inventory from the files filters.
HOST = "scripts/host-tools.sh"
OPERATION = "scripts/operation.sh"
NODE = f"{OPERATION} bootstrap.d/07-node.sh config/mise/config.toml"
INSTALL = f"{OPERATION} install.sh bootstrap.d/*.sh scripts/managed-links.sh scripts/groups.sh"
AGENT_TOOLS = (
    f"{OPERATION} scripts/agent-tools.sh bootstrap.d/05-tools.sh scripts/groups.sh"
)
AGENT_DATA = """.agents/mcp-servers.json .agents/plugin-manifest.json
config/claude/settings.json config/codex/settings.toml config/opencode/opencode.json
config/pi/settings.json config/pi/models.json config/pi/billion-context.json"""
PI_RESOURCES = "config/pi/themes/* config/pi/extensions/*"
AGENT_LINKS = """.agents/AGENTS.md config/claude/CLAUDE.md config/codex/AGENTS.md
config/opencode/AGENTS.md config/pi/AGENTS.md"""
SYNC = f"{OPERATION} sync-agents.sh scripts/groups.sh {AGENT_LINKS}"
SYNC_TEMPLATES = (
    "config/codex/settings.toml config/opencode/opencode.json config/pi/settings.json"
)
LINKS = "config/managed-links.tsv .agents/AGENTS.md"
MANAGED_LINK_HOOKS = {"install-dotfiles-smoke", "doctor-smoke", "install-groups-smoke"}
PLANNERS = f"{NODE} justfile scripts/doctor.sh scripts/state-plan.sh scripts/managed-links.sh scripts/groups.sh"

INPUTS = {
    "tool-plan-smoke": f"""{HOST} {NODE} scripts/smoke-tool-plan.sh scripts/core-tools.sh
        bootstrap.d/*.sh scripts/groups.sh .agents/tool-versions.json Brewfile""",
    "zsh-plan-smoke": f"{HOST} scripts/smoke-zsh-plan.sh bootstrap.d/00-utils.sh bootstrap.d/02-zsh.sh",
    "zshrc-startup-smoke": "scripts/smoke-zshrc-startup.sh .zshrc",
    "agent-repo-layout-smoke": f"""scripts/smoke-agent-repo-layout.sh {AGENT_LINKS}
        AGENTS.md CLAUDE.md bin/committer scripts/committer
        .agents/mcp-servers.json .agents/plugin-manifest.json .agents/skill-lock.json
        .agents/skills/* config/codex/settings.toml config/codex/plugin-manifest.json config/claude/claude-manifest.json
        config/claude/mcp-servers.json config/claude/settings.local.json config/claude/skill-lock.json
        config/pi/settings.json""",
    "install-dotfiles-smoke": f"""{HOST} {INSTALL} {SYNC} {AGENT_DATA} {LINKS} {PI_RESOURCES}
        scripts/smoke-install-dotfiles.sh scripts/codex-toml.py scripts/no-mistakes-config.py
        scripts/herdr-config.py scripts/claude-herdr-hook.jq config/herdr/config.toml
        .agents/skill-lock.json config/firstmate/crew-dispatch.json bin/* scripts/committer justfile""",
    "firstmate-config-smoke": f"{HOST} {INSTALL} scripts/smoke-firstmate-config.sh config/firstmate/crew-dispatch.json",
    "git-sync-smoke": f"{HOST} {INSTALL} scripts/smoke-git-sync.sh",
    "node-smoke": f"{HOST} {NODE} scripts/smoke-node.sh",
    "herdr-hook-smoke": f"""{HOST} scripts/smoke-herdr-hook.sh bootstrap.d/05-tools.sh
        config/claude/settings.json scripts/claude-herdr-hook.jq""",
    "ssh-config-smoke": f"{HOST} scripts/smoke-ssh-config.sh ssh.sh config/ssh/config",
    "macos-apps-smoke": "scripts/smoke-macos-apps.sh bootstrap.d/10-macos-apps.sh Brewfile config/Code/extensions.txt",
    "codex-plugin-sync-smoke": f"""{HOST} {SYNC} {SYNC_TEMPLATES} scripts/smoke-codex-plugin-sync.sh
        .agents/mcp-servers.json .agents/plugin-manifest.json""",
    "plugin-install-smoke": f"""{HOST} {INSTALL} {SYNC} {AGENT_DATA} {PI_RESOURCES}
        scripts/smoke-plugin-install.sh scripts/codex-toml.py scripts/claude-herdr-hook.jq justfile""",
    "skill-install-smoke": f"""{HOST} {SYNC} {AGENT_DATA} {PI_RESOURCES}
        scripts/smoke-skill-install.sh scripts/sync-local.sh scripts/update-local.sh
        scripts/codex-toml.py scripts/claude-herdr-hook.jq justfile""",
    "skill-docs-smoke": f"""{HOST} {SYNC} {SYNC_TEMPLATES} scripts/smoke-skill-docs.sh
        .agents/mcp-servers.json .agents/plugin-manifest.json""",
    "treehouse-smoke": "scripts/smoke-treehouse.sh bootstrap.d/05-tools.sh",
    "codex-native-smoke": f"{HOST} {AGENT_TOOLS} scripts/smoke-codex-native.sh",
    "codex-settings-smoke": f"""{SYNC} scripts/smoke-codex-settings.py scripts/codex-toml.py
        config/opencode/opencode.json config/pi/settings.json""",
    "claude-plugin-sync-smoke": f"{HOST} {SYNC} {SYNC_TEMPLATES} scripts/smoke-claude-plugin-sync.sh",
    "doctor-smoke": f"""{HOST} {INSTALL} {SYNC} {PLANNERS} {LINKS} {PI_RESOURCES} {AGENT_TOOLS}
        scripts/sync-local.sh scripts/update-local.sh scripts/smoke-doctor.sh scripts/codex-toml.py scripts/claude-herdr-hook.jq .pre-commit-config.yaml
        .agents/skill-lock.json .agents/tool-versions.json .gitignore config/claude/settings.json
        config/codex/settings.toml config/opencode/opencode.json config/pi/*.json""",
    "operation-smoke": f"{OPERATION} scripts/smoke-operation.sh",
    "local-update-smoke": f"""{HOST} {NODE} scripts/smoke-update-local.sh justfile
        scripts/groups.sh scripts/sync-local.sh scripts/update-local.sh""",
    "install-groups-smoke": f"""{HOST} {INSTALL} {AGENT_TOOLS} {PLANNERS} {LINKS} sync-agents.sh
        Makefile scripts/smoke-groups.sh scripts/sync-local.sh scripts/update-local.sh .agents/tool-versions.json""",
    "transactional-export-smoke": f"""{HOST} {SYNC} {AGENT_TOOLS} {AGENT_DATA}
        scripts/smoke-export.sh scripts/codex-toml.py scripts/claude-herdr-hook.jq
        .agents/skill-lock.json .agents/tool-versions.json justfile""",
    "agent-sync-interface-smoke": f"{HOST} {SYNC} {SYNC_TEMPLATES} scripts/smoke-agent-sync-interface.sh scripts/codex-toml.py",
    "pi-config-check": f"{SYNC} {PI_RESOURCES} scripts/smoke-pi-*.mjs config/pi/*.json config/pi/*.mjs config/codex/settings.toml config/opencode/opencode.json .agents/mcp-servers.json .gitignore",
    "agent-tools-smoke": f"""{HOST} {AGENT_TOOLS} {NODE} scripts/smoke-agent-tools.sh
        scripts/claude-herdr-hook.jq sync-agents.sh .agents/tool-versions.json""",
    "hook-filters-smoke": "scripts/smoke-hook-filters.py .pre-commit-config.yaml justfile",
    "menu-smoke": "scripts/smoke-menu.sh justfile Makefile",
}


def run(*args, cwd=None, env=None):
    return subprocess.check_output(args, text=True, cwd=cwd, env=env)


def selected(*args, cwd=None, env=None):
    output = run(
        "prek",
        "run",
        "--dry-run",
        "--no-hide-status",
        "--color",
        "never",
        "--verbose",
        *args,
        cwd=cwd,
        env=env,
    )
    return set(re.findall(r"(?m)^.*\.{3,}Dry Run\n- hook id: (\S+)$", output))


def main():
    hooks = {
        hook["id"]
        for hook in json.loads(run("prek", "list", "--output-format", "json"))
    }
    # Match the repository's hook stanza layout; prek itself interprets the filters.
    parts = re.split(
        r"(?m)^      - id: (\S+)$", Path(".pre-commit-config.yaml").read_text()
    )
    stanzas = dict(zip(parts[1::2], parts[2::2], strict=True))
    filtered = {
        hook
        for hook, spec in stanzas.items()
        if re.search(r"(?m)^        files: +\S", spec)
    }
    # The freshness check runs regardless of staged paths.
    architecture = "architecture-map"
    errors = [
        f"{hook}: missing files filter" for hook in sorted(hooks - filtered - {architecture})
    ]
    if not re.search(r"(?m)^        always_run: true$", stanzas.get(architecture, "")):
        errors.append(f"{architecture}: must always run")
    for hook in sorted(INPUTS):
        if not re.search(r"(?m)^        include_deleted: true$", stanzas.get(hook, "")):
            errors.append(f"{hook}: must select deleted inputs")
    expected_hooks = {*INPUTS, "shellcheck", architecture}
    for hook in sorted(hooks ^ expected_hooks):
        errors.append(f"{hook}: hook config and dependency inventory disagree")
    for hook in sorted(expected_hooks - selected("--all-files")):
        errors.append(f"{hook}: skipped by --all-files")

    by_path = inputs_by_path(stanzas, errors)
    for path, expected in sorted(by_path.items()):
        for hook in sorted(expected - selected("--files", path)):
            errors.append(f"{hook}: files filter misses {path}")

    check_repo_layout_selection(errors)
    docs = selected("--files", "README.md", "docs/agents/domain.md")
    if docs != {architecture}:
        errors.append(
            f"Documentation must select only {architecture}; selected: {', '.join(sorted(docs)) or '(none)'}"
        )
    if errors:
        sys.exit("\n".join(errors))
    print("Hook filters select smoke inputs and skip documentation.")


def check_repo_layout_selection(errors):
    hook = "agent-repo-layout-smoke"
    # Forbidden paths should select the hook even before any have been tracked.
    # Use a separate Git index, including when running inside the commit hook.
    git_vars = set(run("git", "rev-parse", "--local-env-vars").splitlines())
    env = {key: value for key, value in os.environ.items() if key not in git_vars}
    with TemporaryDirectory() as scratch:
        root = Path(scratch)
        run("git", "init", "--quiet", cwd=root, env=env)
        config = Path(".pre-commit-config.yaml")
        (root / config).write_bytes(config.read_bytes())
        for path in (
            ".agents/skills/selection-probe/nested/payload.bin",
            ".agents/skills-custom",
            ".agents/skills-custom/selection-probe/payload.bin",
            "config/claude/skills-custom",
            "skills-lock.json",
            "skills-lock.json/selection-probe/payload.bin",
        ):
            probe = root / path
            probe.parent.mkdir(parents=True, exist_ok=True)
            if path == "config/claude/skills-custom":
                probe.symlink_to("../../.pre-commit-config.yaml")
            else:
                probe.touch()
            if hook not in selected(hook, "--files", path, cwd=root, env=env):
                errors.append(f"{hook}: files filter misses untracked {path}")
            run("git", "add", "-f", "--", path, cwd=root, env=env)
            if hook not in selected(hook, cwd=root, env=env):
                errors.append(f"{hook}: skips staged addition {path}")
            run("git", "rm", "--cached", "--quiet", "--", path, cwd=root, env=env)
            probe.unlink()


def shell_fixture_inputs(spec, tracked):
    # Use the hook's entry point, not the inventory, to find literal checkout
    # paths in shell fixtures and follow their ShellCheck source annotations.
    entry = re.search(r"(?m)^        entry: (?:\./|bash )(scripts/smoke-[\w-]+\.sh)$", spec)
    if not entry or entry[1] not in tracked:
        return
    fixture = Path(entry[1])
    references = re.findall(
        r"(?:\$DOTFILES_DIR|\$\{DOTFILES_DIR\})/([\w./-]+)(?=[\s\"'])",
        fixture.read_text(),
    )
    pending = [entry[1], *(tracked & set(references))]
    seen = set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        yield path
        if path.endswith(".sh"):
            for source in re.findall(r"(?m)^\s*# shellcheck source=(\S+)$", Path(path).read_text()):
                for candidate in (source, normpath(f"{Path(path).parent}/{source}")):
                    if candidate in tracked:
                        pending.append(candidate)
                        break


def inputs_by_path(stanzas, errors):
    tracked = set(run("git", "ls-files", "-z").split("\0")[:-1])
    by_path = defaultdict(set)
    for hook, patterns in INPUTS.items():
        for pattern in set(patterns.split()):
            paths = [path for path in tracked if fnmatchcase(path, pattern)]
            if not paths:
                errors.append(f"{hook}: no tracked input matches {pattern}")
            for path in paths:
                by_path[path].add(hook)
        for path in shell_fixture_inputs(stanzas.get(hook, ""), tracked):
            by_path[path].add(hook)
    # The link manifest is also the source of truth for linked directory trees.
    for line in Path("config/managed-links.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        source = line.split("|")[2]
        paths = [
            path for path in tracked if path == source or path.startswith(f"{source}/")
        ]
        if not paths:
            errors.append(
                f"config/managed-links.tsv: no tracked input matches {source}"
            )
        for path in paths:
            by_path[path].update(MANAGED_LINK_HOOKS)

    return by_path


if __name__ == "__main__":
    main()
