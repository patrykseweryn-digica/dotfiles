# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Install tree: give bash scripts config/install-tree.toml as JSON.

  install-tree.py json   Print {"nodes": [...]} in tree order for jq.
  install-tree.py check  Compare the tree with the inventories.

Skill, plugin and MCP elements come from their inventories; see the header
of config/install-tree.toml. --root selects another checkout (tests).
"""

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

TREE = "config/install-tree.toml"
SKILLS = ".agents/skill-lock.json"
PLUGINS = ".agents/plugin-manifest.json"
MCP = ".agents/mcp-servers.json"
TOOLS = ".agents/tool-versions.json"
LINKS = "config/managed-links.tsv"
BREWFILE = "Brewfile"

REFERENCES = ("tools", "links", "casks", "files")
LISTS = ("conditions", "requires", *REFERENCES)


def read_json(root, name):
    return json.loads((root / name).read_text())


def skill_author(entry):
    """Author segment harness/<author>/..., else the GitHub account."""
    parts = entry["skillPath"].split("/")
    if parts[0] == "harness" and len(parts) > 2:
        return parts[1]
    return entry["source"].split("/")[0]


def plugin_marketplace(entry):
    """Marketplace of a plugin entry; Codex-only ids are OpenAI curated."""
    if "claude" in entry:
        return entry["claude"].rpartition("@")[2]
    return "openai-curated"


def derived_elements(root):
    """Map each derive kind to (branch segment, element) pairs.

    Skills sit under an author branch and plugins under a marketplace
    branch. MCP servers sit directly under the derive branch (None).
    """
    skills = [
        (skill_author(entry), name)
        for name, entry in read_json(root, SKILLS)["skills"].items()
    ]
    manifest = read_json(root, PLUGINS)
    plugins = [
        (plugin_marketplace(entry), name) for name, entry in manifest["plugins"].items()
    ]
    for spec in manifest.get("codexPlugins", []):
        name, _, marketplace = spec.rpartition("@")
        if (marketplace, name) not in plugins:
            plugins.append((marketplace, name))
    mcp = [(None, name) for name in read_json(root, MCP)]
    return {"skills": skills, "plugins": plugins, "mcp": mcp}


# Derive kind: the node key, the noun in errors, and the noun of the
# middle branch (None: elements sit directly under the derive branch).
DERIVED = {
    "skills": ("skill", "skill", "author"),
    "plugins": ("plugin", "plugin", "marketplace"),
    "mcp": ("mcp", "MCP server", None),
}


CONDITIONS = ("screen", "sudo", "darwin", "linux")
KEYS = {"label": str, "required": bool, "derive": str, "empty": bool}
KEYS.update(dict.fromkeys(LISTS, list))
SEGMENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def key_error(key, value):
    """Return why one node key is invalid, or None."""
    kind = KEYS.get(key)
    if kind is None:
        return f'unknown key "{key}"'
    if not isinstance(value, kind) or (
        kind is list and not all(isinstance(item, str) for item in value)
    ):
        return f'"{key}" must be a {kind.__name__}'
    return None


def validate(path, spec, declared_before):
    """Return errors in one declared node; unknown keys are not built."""
    errors = []
    parent = path.rpartition("/")[0]
    if not all(SEGMENT.fullmatch(segment) for segment in path.split("/")):
        errors.append(f"{path}: use letters, digits, '.', '_' or '-' between slashes")
    if parent and parent not in declared_before:
        errors.append(f'{path}: declare the parent "{parent}" first')
    if "label" not in spec:
        errors.append(f"{path}: add a label")
    errors += [
        f"{path}: {error}"
        for key, value in spec.items()
        if (error := key_error(key, value))
    ]
    if "derive" in spec and spec["derive"] not in DERIVED:
        errors.append(f'{path}: unknown derive "{spec["derive"]}"')
    for condition in spec.get("conditions", []):
        if condition not in CONDITIONS:
            errors.append(f'{path}: unknown condition "{condition}"')
    return errors


def make_node(path, label, **fields):
    parent = path.rpartition("/")[0] or None
    result = {"path": path, "parent": parent, "label": label}
    result["required"] = fields.pop("required", False)
    for key in LISTS:
        result[key] = fields.pop(key, [])
    result["derive"] = fields.pop("derive", None)
    result["branch"] = fields.pop("empty", False) or result["derive"] is not None
    for key, _, _ in DERIVED.values():
        result[key] = fields.pop(key, None)
    return result


def build(root):
    """Return the nodes in tree order and the errors in their declaration."""
    declared = tomllib.loads((root / TREE).read_text())
    elements = derived_elements(root)
    derive_branches = {
        path: spec["derive"] for path, spec in declared.items() if "derive" in spec
    }
    used = set()
    nodes, errors = [], []
    for kind in set(derive_branches.values()):
        duplicates = [path for path, other in derive_branches.items() if other == kind]
        if len(duplicates) > 1:
            errors.append(
                f'derive "{kind}" has more than one branch: {", ".join(duplicates)}'
            )

    def add_derived(kind, path, segment):
        """Append the derived elements below one branch; return their count."""
        key = DERIVED[kind][0]
        count = 0
        for middle, name in sorted(elements[kind], key=lambda pair: pair[1]):
            if middle == segment:
                used.add((kind, middle, name))
                nodes.append(make_node(f"{path}/{name}", name, **{key: name}))
                count += 1
        return count

    for path, spec in declared.items():
        errors += validate(path, spec, {other["path"] for other in nodes})
        # Build from the valid keys, so that children report their own errors.
        valid = {key: value for key, value in spec.items() if not key_error(key, value)}
        nodes.append(make_node(path, **{"label": path, **valid}))
        parent, _, segment = path.rpartition("/")
        grandparent = parent.rpartition("/")[0]
        kind = spec.get("derive")
        if kind in DERIVED and DERIVED[kind][2] is None:
            add_derived(kind, path, None)
        kind = derive_branches.get(parent)
        if kind in DERIVED and DERIVED[kind][2] is not None:
            # A middle branch: an author or a marketplace.
            nodes[-1]["branch"] = True
            _, noun, middle = DERIVED[kind]
            if not add_derived(kind, path, segment):
                errors.append(f"{path}: no {noun} has this {middle}")
        elif parent in derive_branches or grandparent in derive_branches:
            errors.append(f"{path}: declare nothing below {parent}")
    for kind, pairs in elements.items():
        noun = DERIVED[kind][1]
        home = next((p for p, k in derive_branches.items() if k == kind), None)
        for middle, name in pairs:
            if (kind, middle, name) in used:
                continue
            hint = f": declare {home}/{middle}" if home and middle else ""
            errors.append(f'{noun} "{name}" has no tree node{hint}')
    parents = {built["parent"] for built in nodes}
    for built in nodes:
        built["branch"] = built["branch"] or built["path"] in parents
    return nodes, errors


def inventories(root):
    """Map each node key to its noun and the names its inventory declares."""
    tools = [tool["name"] for tool in read_json(root, TOOLS)["tools"]]
    links = []
    for line in (root / LINKS).read_text().splitlines():
        if line and not line.startswith("#"):
            source = line.split("|")[2]
            if source not in links:
                links.append(source)
    casks = re.findall(r'(?m)^cask "([^"]+)"', (root / BREWFILE).read_text())
    return {
        "tools": ("tool", tools),
        "links": ("managed link", links),
        "casks": ("macOS application", casks),
    }


def check(root, nodes):
    """Return one error line per mismatch between tree and inventories."""
    errors = []
    paths = {built["path"] for built in nodes}
    references = (*REFERENCES, *(key for key, _, _ in DERIVED.values()))
    for built in nodes:
        path = built["path"]
        for other in built["requires"]:
            if other not in paths:
                errors.append(f'{path}: requires "{other}", which is not a tree node')
        for name in built["files"]:
            if not (root / name).is_file():
                errors.append(f'{path}: file "{name}" does not exist')
        if not built["branch"] and not any(built[key] for key in references):
            errors.append(f"{path}: element has no inventory entry")
    for key, (noun, names) in inventories(root).items():
        claimed = {}
        for built in nodes:
            for name in built[key]:
                claimed.setdefault(name, []).append(built["path"])
        for name in names:
            if name not in claimed:
                errors.append(f'{noun} "{name}" has no tree node')
        for name, owners in claimed.items():
            if name not in names:
                errors.extend(
                    f'{owner}: {noun} "{name}" has no inventory entry'
                    for owner in owners
                )
            elif len(owners) > 1:
                errors.append(
                    f'{noun} "{name}" has more than one tree node: {", ".join(owners)}'
                )
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("json", "check"))
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    nodes, errors = build(args.root)
    errors += check(args.root, nodes)
    if errors:
        sys.exit("\n".join(f"[ERROR] {TREE}: {error}" for error in errors))
    if args.command == "json":
        json.dump({"nodes": nodes}, sys.stdout, indent=2)
        print()


if __name__ == "__main__":
    main()
