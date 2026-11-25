#!/usr/bin/env python3
"""Build the public architecture map without reading local machine state."""

import argparse
import json
import re
from collections import Counter
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {"Darwin": "macOS", "Linux": "Linux"}
COMMANDS = ("install", "sync", "machine", "export", "groups", "enable", "disable")


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def load(path):
    try:
        return json.loads(read(path))
    except (OSError, ValueError) as error:
        raise ValueError(f"Cannot read {path}: {error}") from error


def capture(pattern, text, source):
    match = re.search(pattern, text, re.MULTILINE)
    if not match or not match[1]:
        raise ValueError(f"Cannot resolve architecture from {source}: {pattern}")
    return match[1]


def command_entrypoints():
    justfile = read("justfile")
    default_sync = capture(
        r'^sync_agents := .*"(\./[^" ]+\.sh)"\)', justfile, "justfile"
    )
    commands = {
        command: [
            path.removeprefix("./")
            for path in re.findall(
                r"(?:\./)?[\w/-]+\.sh",
                capture(
                    rf"^{command}[^\n]*:\n((?:[ \t].*\n)+)", justfile, "justfile"
                ).replace("{{ sync_agents }}", default_sync),
            )
        ]
        for command in COMMANDS
    }
    for command, paths in commands.items():
        if not paths or any(not (ROOT / path).is_file() for path in paths):
            raise ValueError(f"Cannot resolve the just {command} entry point")
    return commands


def script_references(commands):
    # shortcut: literal references only; resolve variables if the map needs exact call sites.
    pending = {path for paths in commands.values() for path in paths}
    seen = set()
    references = []
    while pending:
        source = min(pending)
        pending.remove(source)
        seen.add(source)
        pattern = r"(?<![\w-])(?:(?:scripts|bootstrap\.d)/[\w-]+|install|sync-agents|ssh)\.sh\b"
        for target in sorted(set(re.findall(pattern, read(source)))):
            if target == source or not (ROOT / target).is_file():
                continue
            references.append({"from": source, "to": target})
            if target not in seen:
                pending.add(target)
    return references


def build_graph():
    tool_source = ".agents/tool-versions.json"
    skill_source = ".agents/skill-lock.json"
    mcp_source = ".agents/mcp-servers.json"
    plugin_source = ".agents/plugin-manifest.json"
    link_source = "config/managed-links.tsv"
    node_source = "config/mise/config.toml"
    group_source = "scripts/groups.sh"
    platform_source = "scripts/state-plan.sh"
    groups = capture(
        r'^DOTFILES_GROUP_NAMES="([^"]+)"', read(group_source), group_source
    ).split()
    system_cases = capture(
        r'case "\$os:\$arch" in\n\s*([^\n]+)\)', read(platform_source), platform_source
    )
    platforms = sorted(
        {PLATFORMS[item.strip().split(":")[0]] for item in system_cases.split("|")}
    )
    tools = sorted(
        (tool.get("name") or tool["command"], tool["group"])
        for tool in load(tool_source)["tools"]
    )
    links = [
        line.split("|")
        for line in read(link_source).splitlines()
        if line and not line.startswith("#")
    ]
    steps = {
        step: group
        for group, step in re.findall(
            r'^\s*run_group_step (\w+) (?:required|optional) "[^"]+" (\w+)',
            read("install.sh"),
            re.MULTILINE,
        )
    }
    node_group = steps["install_node"]
    app_group = steps["install_macos_apps"]
    graphics_group = steps["install_fonts"]
    for group in {
        node_group,
        app_group,
        graphics_group,
        *(group for _, group in tools),
        *(row[0] for row in links),
    }:
        if group not in groups:
            raise ValueError(f"Undeclared install group: {group}")
    skills = load(skill_source)["skills"]
    mcp = sorted(load(mcp_source))
    plugins = load(plugin_source)
    settings = sorted(
        {source for group, _, source, _ in links if group == graphics_group}
    )
    apps = sorted(re.findall(r'^cask "([^"]+)"', read("Brewfile"), re.MULTILINE))
    extensions_path = "config/Code/extensions.txt"
    extensions = sorted(
        line
        for line in read(extensions_path).splitlines()
        if line and not line.startswith("#")
    )
    node_policy = capture(r'^node\s*=\s*"([^"]+)"', read(node_source), node_source)
    guard = 'if [ "${IS_MACOS:-false}" != true ]; then\n        return 0\n    fi'
    if f"install_macos_apps() {{\n    {guard}" not in read(
        "bootstrap.d/10-macos-apps.sh"
    ):
        raise ValueError("Cannot resolve the platform guard for install_macos_apps")

    agents = read("sync-agents.sh")
    harnesses = re.findall(
        r"^(\w+)\|\$\w+_SKILLS_DIR$",
        capture(
            r"^skill_runtime_rows\(\) \{\n\s*cat <<EOF\n([\s\S]+?)\nEOF",
            agents,
            "sync-agents.sh",
        ),
        re.MULTILINE,
    )
    if not harnesses:
        raise ValueError("Cannot resolve the harnesses linked to shared skills")
    harnesses = ["Claude Code" if name == "Claude" else name for name in harnesses]

    modules = [
        {
            "id": "tools",
            "label": "Tools",
            "sources": [tool_source, node_source],
            "target": platforms,
            "inventory": {
                "tools_by_group": dict(
                    sorted(Counter(group for _, group in tools).items())
                ),
                "tools": [{"name": name, "group": group} for name, group in tools],
                "node": {
                    "policy": node_policy,
                    "install_group": node_group,
                    "installer": "mise",
                },
            },
        },
        {
            "id": "harnesses",
            "label": "Agent harnesses",
            "sources": [skill_source, mcp_source, plugin_source],
            "target": platforms,
            "inventory": {
                "shared_skill_consumers": harnesses,
                "skills_by_source": dict(
                    sorted(
                        Counter(skill["source"] for skill in skills.values()).items()
                    )
                ),
                "skill_count": len(skills),
                "mcp_servers": mcp,
                "plugins_by_harness": dict(
                    sorted(
                        Counter(
                            h for p in plugins["plugins"].values() for h in p
                        ).items()
                    )
                ),
            },
        },
        {
            "id": "graphical-settings",
            "label": "Graphical settings",
            "sources": [
                link_source,
                "bootstrap.d/06-fonts.sh",
                "bootstrap.d/08-terminal.sh",
            ],
            "target": platforms,
            "install_group": graphics_group,
            "inventory": {"managed_sources": settings},
        },
        {
            "id": "graphical-apps",
            "label": "Graphical applications",
            "sources": ["Brewfile", extensions_path],
            "target": ["macOS"],
            "install_group": app_group,
            "inventory": {"homebrew_casks": apps, "vscode_extensions": extensions},
        },
    ]
    commands = command_entrypoints()
    return {
        "platforms": platforms,
        "install_groups": groups,
        "commands": commands,
        "script_references": script_references(commands),
        "modules": modules,
        "module_dependencies": [
            {
                "from": "harnesses",
                "to": "tools",
                "via": "Node",
                "source": "scripts/agent-tools.sh",
            }
        ],
        "unresolved": [
            "Local group selection and command overrides",
            "Dynamic shell calls and dependency availability on live machines",
        ],
    }


def svg(graph):
    parts = [
        """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 870 500" role="img" aria-labelledby="title desc">
<title id="title">dotfiles architecture: declarations, modules and platforms</title>
<desc id="desc">Tools, harnesses and graphical settings span Linux and macOS. Only macOS installs graphical applications. Harness tooling uses Node through mise.</desc>
<!-- Generated by scripts/build-architecture.py. -->
<style>
text{font:13px system-ui,sans-serif;fill:#202b26}.head{font-weight:700;letter-spacing:1.2px;fill:#496458;font-size:12px}.main{font-weight:675;font-size:16px}.detail{fill:#4d6258}.box{fill:#fffefa;stroke:#b9c8bd}.edge{fill:none;stroke:#47735e;stroke-width:1.65}.lane{fill:#f0f5ef}.accent{fill:#e2f2e8;stroke:#8abc9e}.platform{fill:#edf4ff;stroke:#b5c7e1}
</style>
<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path fill="#47735e" d="M0 0L10 5L0 10Z"/></marker></defs>
<rect width="870" height="500" fill="#fbfcf8" rx="14"/>
<rect class="lane" x="12" y="12" width="218" height="452" rx="14"/>
<rect class="lane" x="282" y="12" width="307" height="452" rx="14"/>
<rect fill="#f1f5fc" x="677" y="12" width="181" height="452" rx="14"/>
<text class="head" x="32" y="42">1 · DECLARATIONS</text>
<text class="head" x="302" y="42">2 · MODULES</text>
<text class="head" x="697" y="42">3 · PLATFORMS</text>"""
    ]

    def box(key, x, y, width, css, title, detail):
        parts.append(
            f'<g id="{key}"><title>{escape(title)}: {escape(detail)}</title>'
            f'<rect class="{css}" x="{x}" y="{y}" width="{width}" height="67" rx="6"/>'
            f'<text class="main" x="{x + 14}" y="{y + 28}">{escape(title)}</text>'
            f'<text class="detail" x="{x + 14}" y="{y + 49}">{escape(detail)}</text></g>'
        )

    def edge(path, label, dash=False):
        dash_attr = ' stroke-dasharray="4 4"' if dash else ""
        parts.append(
            f'<path class="edge" d="{path}" marker-end="url(#arrow)"{dash_attr}><title>{escape(label)}</title></path>'
        )

    tools, harnesses, settings, apps = graph["modules"]
    node = tools["inventory"]["node"]
    labels = [
        (
            "Tool inventory",
            f"{len(tools['inventory']['tools'])} entries · Node policy",
            f"{node['installer']} · Node {node['policy'].upper()} via {node['install_group']}",
        ),
        (
            "Agent inventories",
            f"{harnesses['inventory']['skill_count']} skills · MCP · plugins",
            " · ".join(harnesses["inventory"]["shared_skill_consumers"]),
        ),
        (
            "Display settings",
            "Link table · font setup",
            f"{settings['install_group']} · VS Code · Ghostty",
        ),
        (
            "App inventories",
            "Brewfile · extensions.txt",
            f"{apps['install_group']} · {len(apps['inventory']['homebrew_casks'])} apps · {len(apps['inventory']['vscode_extensions'])} extensions",
        ),
    ]
    for index, (module, (source_title, source_detail, module_detail)) in enumerate(
        zip(graph["modules"], labels, strict=True)
    ):
        y = 65 + 101 * index
        midpoint = y + 34
        key = module["id"]
        box(f"source-{key}", 32, y, 178, "box", source_title, source_detail)
        box(
            key,
            302,
            y,
            267,
            "accent" if key == "tools" else "box",
            module["label"],
            module_detail,
        )
        edge(f"M210 {midpoint}H300", f"{source_title} drives {module['label']}")
    box(
        "shared-platforms",
        697,
        165,
        141,
        "platform",
        " + ".join(graph["platforms"]),
        "Shared modules",
    )
    box("macos-only", 697, 368, 141, "platform", "macOS only", "App installation")
    edge("M434 132V163", "Harness tooling uses Node", dash=True)
    edge("M569 99H638V199H694", "Tools run on both platforms")
    edge("M569 200H694", "Harnesses run on both platforms")
    edge("M569 301H638V200H694", "Graphical settings span both platforms")
    edge("M569 402H694", "The Brewfile installs apps only on macOS")
    parts.append(
        '<text class="detail" x="12" y="485">Current repository · Groups are selected locally · Dashed arrow: tool dependency</text>\n</svg>\n'
    )
    return "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="Fail if a checked-in artifact is stale"
    )
    args = parser.parse_args()
    try:
        graph = build_graph()
    except (KeyError, OSError, ValueError) as error:
        parser.exit(1, f"Architecture: {error}\n")
    outputs = {
        "docs/architecture.json": json.dumps(graph, indent=2, ensure_ascii=False)
        + "\n",
        "docs/architecture.svg": svg(graph),
    }
    stale = []
    for name, contents in outputs.items():
        path = ROOT / name
        if not args.check:
            path.write_text(contents, encoding="utf-8")
        elif not path.is_file() or path.read_text(encoding="utf-8") != contents:
            stale.append(name)
    if stale:
        parser.exit(
            1, f"Stale architecture map: {', '.join(stale)}. Run: just architecture\n"
        )


if __name__ == "__main__":
    main()
