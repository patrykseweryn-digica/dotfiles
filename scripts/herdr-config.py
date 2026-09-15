# /// script
# requires-python = ">=3.10"
# dependencies = ["tomlkit==0.13.2"]
# ///
"""Show raw terminal titles in Herdr without replacing local preferences."""

import os
import stat
import tempfile
from pathlib import Path

import tomlkit


def main():
    source = Path(__file__).resolve().parent.parent / "config/herdr/config.toml"
    managed = tomlkit.loads(source.read_text())
    path = Path(
        os.environ.get("HERDR_CONFIG_PATH") or Path.home() / ".config/herdr/config.toml"
    ).resolve()
    original = path.read_text() if path.exists() else ""
    data = tomlkit.loads(original) if original else managed
    agents = (
        data.setdefault("ui", tomlkit.table())
        .setdefault("sidebar", tomlkit.table())
        .setdefault("agents", tomlkit.table())
    )
    if "rows" not in agents:
        agents["rows"] = managed.unwrap()["ui"]["sidebar"]["agents"]["rows"]
    rows = agents["rows"]
    if not isinstance(rows, list) or any(not isinstance(row, list) for row in rows):
        raise ValueError("Herdr Agents rows must be an array of arrays")
    if ["terminal_title"] not in rows:
        if len(rows) >= 16:
            raise ValueError("Cannot add terminal_title: Herdr allows at most 16 rows")
        rows.append(["terminal_title"])
    text = tomlkit.dumps(data)
    if text == original:
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.flush()
            if path.exists():
                temporary.chmod(stat.S_IMODE(path.stat().st_mode))
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
