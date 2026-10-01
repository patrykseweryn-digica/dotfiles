---
name: verify-dotfiles
description: Verify dotfiles CLI setup, latest tool updates and live machine drift on macOS or Linux before applying configuration or committing changes.
---

# Verify dotfiles

Read [features/README.md](features/README.md), then drive every entry point
listed for the affected features. Use existing checks, not a new runner.

## Launch

Run from the dotfiles checkout. There is no server or persistent test process.
Required commands: bash, git, just, jq, node, npm, uv, pre-commit, zsh, rg.
Install development dependencies with:

```bash
npm --prefix config/pi ci --ignore-scripts
```

Create a retained evidence directory:

```bash
mkdir -p .agent-runs/verify-dotfiles
proof=$(mktemp -d "$PWD/.agent-runs/verify-dotfiles/run.XXXXXX")
```

Run each command below
in Bash with `set -o pipefail`; a successful tee must not hide a failed check.
The smoke scripts create and remove their own disposable HOME directories.
Never run full setup against the user's HOME just to test it.

## Doctor

Before changes or machine setup, run the read-only live check:

```bash
just doctor >"$proof/doctor-before.log" 2>&1
```

Record its exit code even when nonzero. Existing drift is a baseline to
investigate, not permission to erase local settings. Doctor omits raw diffs;
never save raw config or credential files as evidence. If sandbox permissions
block uv caches or network, rerun with the required access; do not weaken tests.

## Drive

For every change, run relevant feature recipes, then before a commit:

```bash
just check 2>&1 | tee "$proof/check.log"
just doctor >"$proof/doctor-after.log" 2>&1
```

Record both exit codes. `just verify` combines check and doctor for a single pass/fail command.
Commit-time pre-commit hooks remain mandatory.
Do not disable hooks or force a commit through a new failure. With existing
live drift, state exactly what passed and which checks still fail. Before
applying configuration, compare both sides and back up valuable local state.
A passing repository check does not authorize overwriting local preferences.

## Evidence

Capture commands, exit codes, platform (`uname -s` and `uname -m`) and
`git diff --stat` in `$proof/result.txt`, plus the transcripts above.
The install smoke scripts exercise public just recipes in disposable HOME;
external installers are stubbed at the network/package-manager boundary.
The tool smoke installs and updates a real local npm package through the
public update command, reads back its version, verifies unchanged inventory,
and tests download failure and a missing Node without touching live tools.
The sync tests check credentials/session preservation and repeated setup.

Record doctor failures before and after; investigate new failures. For changed
live-check code, checksum the affected live config before and after with
`cksum` and compare, without copying file contents. Tests on macOS include
simulated Linux scenarios. Claim actual Linux execution only after the Linux
CI job or a real Linux machine passes. Inspect existing CI results when
available; push only if requested.

## Cleanup

No daemon to stop. Smoke scripts remove their own scratch directories.
Remove only scratch state created by this run; keep `$proof` and its logs.
Confirm evidence still exists after all commands finish. Do not kill processes
by name or remove live configuration to make a test pass.

## Helpers

No new helper. Use the repository's existing scripts from the feature map.
Keep the map current with `/maintain-verification-skill` when behavior changes.
