#!/usr/bin/env -S uv run --no-project --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise the real sync interface in an isolated HOME, without Codex."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import tomllib


def main():
    sync = Path(__file__).resolve().parents[1] / "sync-agents.sh"
    cache = subprocess.check_output(["uv", "cache", "dir"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="codex-settings-") as temporary:
        home = Path(temporary)
        config = home / ".codex/config.toml"
        config.parent.mkdir()
        template = home / "settings.toml"
        mcp = home / "mcp.json"
        env = {
            **os.environ,
            "HOME": str(home),
            "CODEX_HOME": str(config.parent),
            "CODEX_CONFIG": str(config),
            "CODEX_SETTINGS_TEMPLATE": str(template),
            "MCP_SERVERS": str(mcp),
            "UV_CACHE_DIR": cache,
        }
        template.write_text("""model = "repo-model"
model_reasoning_effort = "medium"
service_tier = "default"
[tui]
status_line = ["model", "git-branch"]
[shell_environment_policy.set]
MANAGED = "repo"
[desktop]
enabled = true
""")
        mcp.write_text(
            json.dumps(
                {"remote.with.dot": {"type": "http", "url": "https://example.test/mcp"}}
            )
        )

        def run(command, answer="", success=True):
            result = subprocess.run(
                [str(sync), "--quiet", command],
                env=env,
                input=answer,
                capture_output=True,
                text=True,
                check=False,
            )
            assert (result.returncode == 0) == success, (
                command,
                result.returncode,
                result.stdout,
                result.stderr,
            )
            return result.stdout + result.stderr

        def read(path=config):
            return tomllib.loads(path.read_text())

        missing = run("codex-check", success=False)
        assert str(config) in missing and "codex-install" in missing
        assert not config.exists()
        run("codex-install")
        run("codex-check")

        target = home / "symlink-target.toml"
        target.write_text('sandbox_mode = "workspace-write"\n')
        target_before = target.read_bytes()
        config.unlink()
        config.symlink_to(target)
        run("codex-install")
        assert not config.is_symlink()
        assert target.read_bytes() == target_before
        assert read()["sandbox_mode"] == "workspace-write"

        config.write_text("""sandbox_mode = "workspace-write"
model = "local-model"
model_reasoning_effort = "high"
service_tier = "priority"
"quoted.root" = "keep"
[shell_environment_policy]
inherit = "all"
[shell_environment_policy.set]
MANAGED = "live"
LOCAL = "keep"
[tui]
status_line = ["git-branch", "model"]
local = true
[desktop]
enabled = false
local = "keep"
[desktop.local_nested]
keep = true
[projects."/tmp/project.with.dot"]
trust_level = "trusted"
[notice]
hide = true
[hooks]
approved_hookhash = "local-hash"
[mcp_servers.local]
command = "local-server"
[mcp_servers."remote.with.dot"]
url = "https://old.test/mcp"
bearer_token_env_var = "LOCAL_TOKEN"
""")
        before = config.read_bytes()
        original_template = template.read_bytes()
        run("pull-codex-settings", "n\n", success=False)
        assert template.read_bytes() == original_template
        run("pull-codex-settings", "y\n")
        imported = read(template)
        assert imported["model"] == "local-model"
        assert imported["service_tier"] == "priority"
        assert imported["tui"] == {"status_line": ["git-branch", "model"]}
        assert imported["shell_environment_policy"] == {"set": {"MANAGED": "live"}}
        assert imported["desktop"] == {"enabled": False}
        assert set(imported) == {
            "model",
            "model_reasoning_effort",
            "service_tier",
            "tui",
            "shell_environment_policy",
            "desktop",
        }
        assert config.read_bytes() == before
        run("codex-install")
        actual = read()
        assert actual["sandbox_mode"] == "workspace-write"
        assert "sandbox_mode" not in actual["desktop"]
        assert actual["quoted.root"] == "keep"
        assert actual["desktop"]["local_nested"] == {"keep": True}
        assert actual["shell_environment_policy"]["set"]["LOCAL"] == "keep"
        assert actual["projects"]["/tmp/project.with.dot"]["trust_level"] == "trusted"
        assert actual["hooks"]["approved_hookhash"] == "local-hash"
        assert actual["notice"] == {"hide": True}
        assert (
            actual["mcp_servers"]["remote.with.dot"]["bearer_token_env_var"]
            == "LOCAL_TOKEN"
        )
        run("codex-check")
        before = config.read_bytes()
        run("codex-install")
        assert config.read_bytes() == before

        text = (
            config.read_text()
            .replace(
                'model = "local-model"\nmodel_reasoning_effort = "high"',
                "model_reasoning_effort='low'\nmodel='interactive-model'",
            )
            .replace("[desktop]", "\n\n[desktop] # harmless formatting")
        )
        tier = 'service_tier = "priority"\n'
        text = tier + text.replace(tier, "")
        config.write_text(text)
        run("codex-check")
        before = config.read_bytes()
        run("codex-check")
        assert config.read_bytes() == before
        config.write_text(
            text.replace('service_tier = "priority"', 'service_tier = "default"')
        )
        assert "drift" in run("codex-check", success=False)
        run("codex-install")
        assert read()["service_tier"] == "priority"
        assert read()["model"] == "local-model"
        text = config.read_text()
        config.write_text(
            text.replace('["git-branch", "model"]', '["model", "git-branch"]')
        )
        run("codex-check", success=False)
        run("codex-install")

        # Old managed names disappear; unrelated servers remain local.
        mcp.write_text("{}")
        run("codex-install")
        assert read()["mcp_servers"] == {"local": {"command": "local-server"}}
        run("codex-check")

        valid_config = config.read_bytes()
        valid_template = template.read_bytes()
        for broken in (config, template):
            broken.write_text("[invalid\n")
            before_config, before_template = config.read_bytes(), template.read_bytes()
            for command in ("codex-install", "codex-check", "pull-codex-settings"):
                message = run(command, "y\n", success=False)
                assert "TOML" in message and str(broken) in message
                assert config.read_bytes() == before_config
                assert template.read_bytes() == before_template
            config.write_bytes(valid_config)
            template.write_bytes(valid_template)

        # Equivalent quoted/dotted syntax must retain its structural meaning.
        template.write_text('"desktop"."enabled" = false\n')
        run("codex-install")
        run("codex-check")
        before = template.read_bytes()
        run("pull-codex-settings")
        assert template.read_bytes() == before
    print("[INFO] Codex settings smoke test passed")


if __name__ == "__main__":
    main()
