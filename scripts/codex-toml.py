# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit==0.13.2"]
# ///
"""Codex settings: structural import, rendering and drift checks."""

import copy
import difflib
import json
import math
import os
import re
import sys
import tempfile
from importlib import import_module
from pathlib import Path
from pprint import pformat

START = "# dotfiles-managed-mcp-start"
END = "# dotfiles-managed-mcp-end"
MODEL_KEYS = ("model", "model_reasoning_effort")


def read_toml(path, loads):
    try:
        text = path.read_text()
        return text, loads(text)
    except (OSError, ValueError) as exc:
        raise ValueError(f"Cannot read TOML {path}: {exc}") from exc


def equal(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            equal(value, right[key]) for key, value in left.items()
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(map(equal, left, right))
    if isinstance(left, float) and math.isnan(left):
        return math.isnan(right)
    return left == right


def merge(local, managed):
    for key, value in managed.items():
        if isinstance(value, dict) and isinstance(local.get(key), dict):
            merge(local[key], value)
        else:
            local[key] = copy.deepcopy(value)
    return local


def select(live, managed):
    return {
        key: select(live[key], value)
        if isinstance(value, dict) and isinstance(live[key], dict)
        else live[key]
        for key, value in managed.items()
        if key in live
    }


def plan_settings(live_text, live, managed, inventory, loads):
    result = merge(copy.deepcopy(live), managed)
    servers = result.setdefault("mcp_servers", {})
    if not isinstance(servers, dict):
        raise TypeError("Codex mcp_servers must be a TOML table")

    # Keep recognizing old managed blocks so removed servers stay removed.
    lines = live_text.splitlines()
    if START in lines:
        start = lines.index(START)
        if END not in lines[start + 1 :]:
            raise ValueError("Unclosed Codex managed MCP block")
        end = lines.index(END, start + 1)
        old = loads("\n".join(lines[start + 1 : end]))
        for name in old.get("mcp_servers", {}):
            if name not in inventory:
                servers.pop(name, None)

    managed_servers = {}
    for name, server in inventory.items():
        wanted = (
            {"url": server["url"]}
            if server["type"] == "http"
            else {"command": server["command"], "args": server.get("args", [])}
        )
        if server.get("env"):
            wanted["env"] = {key: str(value) for key, value in server["env"].items()}
        local = servers.pop(name, {})
        if not isinstance(local, dict):
            raise TypeError(f"Codex MCP server {name!r} must be a TOML table")
        for key in ("command", "args") if "url" in wanted else ("url",):
            local.pop(key, None)
        managed_servers[name] = merge(local, wanted)
    if not servers:
        result.pop("mcp_servers")
    return result, managed_servers


def render(local, managed_servers, expected, loads, dumps):
    text = dumps(local)
    if managed_servers:
        text += "\n" + START + "\n"
        text += dumps({"mcp_servers": managed_servers})
        text += END + "\n"
    if not equal(loads(text), expected):
        raise ValueError("Codex TOML serialization changed the configuration")
    return text


def atomic_write(path, text, loads):
    # Parse before creating or replacing anything at the destination.
    loads(text)
    path = path.parent.resolve() / path.name
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            if path.exists():
                os.fchmod(stream.fileno(), path.stat().st_mode & 0o777)
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def check_settings(source, live, expected, *, quiet=False):
    for key in MODEL_KEYS:
        live.pop(key, None)
        expected.pop(key, None)
    if equal(live, expected):
        return 0
    if quiet:
        return 2
    print(f"[ERROR] Codex config drift detected: {source}", file=sys.stderr)
    print("Keep live: ./sync-agents.sh pull-codex-settings", file=sys.stderr)
    print("Keep repository: ./sync-agents.sh codex-install", file=sys.stderr)
    sys.stderr.writelines(
        difflib.unified_diff(
            (pformat(live) + "\n").splitlines(keepends=True),
            (pformat(expected) + "\n").splitlines(keepends=True),
            fromfile="live",
            tofile="repository",
        )
    )
    return 2


def mcp_state(config):
    servers = []
    for name, server in config.get("mcp_servers", {}).items():
        if server.get("enabled", True) is False:
            continue
        if isinstance(server.get("url"), str):
            transport = {"type": "http", "url": server["url"]}
        elif isinstance(server.get("command"), str):
            args = server.get("args", [])
            if not isinstance(args, list) or not all(isinstance(x, str) for x in args):
                raise ValueError("Invalid Codex MCP arguments")
            transport = {"type": "stdio", "command": server["command"], "args": args}
        else:
            raise ValueError("Invalid Codex MCP transport")
        servers.append({"name": name, "transport": transport})
    return servers


def marketplace_entries(root, name):
    for directory, filename in (
        (".agents/plugins", "marketplace.json"),
        (".agents/plugins", "api_marketplace.json"),
        (".claude-plugin", "marketplace.json"),
        (".cursor-plugin", "marketplace.json"),
    ):
        try:
            entries = json.loads((root / directory / filename).read_text())
            if entries["name"] != name or not isinstance(entries["plugins"], list):
                raise ValueError("Invalid manifest")
            return entries["plugins"]
        except FileNotFoundError:
            continue
    raise ValueError("Missing manifest")


def has_plugin_cache(root):
    try:
        return any(not p.is_symlink() and p.is_dir() for p in root.iterdir())
    except FileNotFoundError:
        return False


def git_plugin_state(config, home):
    # Codex stores Git marketplace snapshots here (installed_marketplaces.rs).
    cache = home / "plugins/cache"
    marketplaces, installed = [], []
    plugins = config.get("plugins", {})
    for name, market in config.get("marketplaces", {}).items():
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            raise ValueError("Invalid Codex marketplace name")
        kind, source = market["source_type"], market["source"]
        if kind not in ("git", "local") or not isinstance(source, str) or not source:
            raise ValueError(f"Invalid Codex marketplace: {name}")
        location = {"sourceType": kind, "source": source}
        # Local marketplaces still need provider validation, but do not export.
        marketplaces.append({"name": name, "marketplaceSource": location})
        if kind == "local":
            continue
        root = home / ".tmp/marketplaces" / name
        try:
            for entry in marketplace_entries(root, name):
                plugin = entry["name"]
                if not re.fullmatch(r"[A-Za-z0-9_.-]+", plugin) or plugin in (
                    ".",
                    "..",
                ):
                    raise ValueError("Invalid plugin name")
                plugin_id = f"{plugin}@{name}"
                if plugin_id not in plugins or not has_plugin_cache(
                    cache / name / plugin
                ):
                    continue
                enabled = plugins[plugin_id].get("enabled", True)
                if not isinstance(enabled, bool):
                    raise ValueError("Invalid plugin enabled flag")
                installed.append(
                    {
                        "pluginId": plugin_id,
                        "installed": True,
                        "enabled": enabled,
                        "marketplaceName": name,
                        "marketplaceSource": location,
                    }
                )
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            raise ValueError(
                f"Unreadable or invalid Codex marketplace snapshot: {name}"
            ) from exc
    return {"installed": installed, "marketplaces": marketplaces}


def plan_state(source, config, expected, home):
    result: dict[str, object] = {
        "settings": check_settings(source, config, expected, quiet=True),
    }
    try:
        result["mcp"] = mcp_state(config)
    except (ValueError, AttributeError):
        result["mcp"] = None
    try:
        result.update(git_plugin_state(config, home))
    except (ValueError, OSError, KeyError, TypeError, AttributeError) as exc:
        message = str(exc)
        result["pluginError"] = (
            message
            if message.startswith("Unreadable or invalid Codex marketplace snapshot: ")
            else "Invalid Codex marketplace configuration"
        )
    return result


def main():
    action, source, template, mcp, *output = sys.argv[1:]
    if action in ("check", "plan"):
        try:
            loads = import_module("tomllib").loads
        except ImportError:
            return 4  # The shell adapter reports the missing check environment.
        dumps = None
    else:
        import tomlkit

        def loads(text):
            return tomlkit.loads(text).unwrap()

        dumps = tomlkit.dumps

    source, template = Path(source), Path(template)
    template_text, managed = read_toml(template, loads)
    if action != "install" or source.exists():
        live_text, live = read_toml(source, loads)
    else:
        live_text, live = "", {}

    if action == "import" and dumps is not None:
        imported = select(live, managed)
        text = template_text if equal(imported, managed) else dumps(imported)
        atomic_write(Path(output[0]), text, loads)
        return 0

    try:
        inventory = json.loads(Path(mcp).read_text())
    except (OSError, ValueError) as exc:
        raise ValueError(f"Cannot read MCP inventory {mcp}: {exc}") from exc
    local, managed_servers = plan_settings(live_text, live, managed, inventory, loads)
    expected = copy.deepcopy(local)
    if managed_servers:
        expected.setdefault("mcp_servers", {}).update(managed_servers)
    if action == "install" and dumps is not None:
        text = render(local, managed_servers, expected, loads, dumps)
        if not source.exists() or not equal(live, expected):
            atomic_write(source, text, loads)
        return 0
    if action == "check":
        return check_settings(source, live, expected)
    if action == "plan":
        print(json.dumps(plan_state(source, live, expected, Path(output[0]))))
        return 0
    raise ValueError(f"Unknown Codex TOML action: {action}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"[ERROR] Codex configuration: {exc}", file=sys.stderr)
        sys.exit(1)
