# /// script
# requires-python = ">=3.10"
# dependencies = ["ruamel.yaml==0.18.10"]
# ///
"""Set the no-mistakes global agent without replacing local settings."""

import os
import stat
import tempfile
from collections.abc import MutableMapping
from pathlib import Path

from ruamel.yaml import YAML


def main():
    path = (Path.home() / ".no-mistakes/config.yaml").resolve()
    yaml = YAML()
    yaml.preserve_quotes = True
    data = yaml.load(path) if path.exists() else None
    if data is None:
        data = {}
    if not isinstance(data, MutableMapping):
        raise TypeError(f"Expected a YAML mapping in {path}")
    if data.get("agent") == "codex":
        return
    data["agent"] = "codex"

    path.parent.mkdir(parents=True, exist_ok=True)
    # Replace only after parsing and serialization succeed; retain permissions.
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            yaml.dump(data, stream)
            stream.flush()
            if path.exists():
                temporary.chmod(stat.S_IMODE(path.stat().st_mode))
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
