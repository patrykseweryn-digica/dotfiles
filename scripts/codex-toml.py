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


def check_settings(source, live, expected):
    for key in MODEL_KEYS:
        live.pop(key, None)
        expected.pop(key, None)
    if equal(live, expected):
        return 0
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


def main():
    action, source, template, mcp, *output = sys.argv[1:]
    if action == "check":
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

    inventory = json.loads(Path(mcp).read_text())
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
    raise ValueError(f"Unknown Codex TOML action: {action}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"[ERROR] Codex configuration: {exc}", file=sys.stderr)
        sys.exit(1)
