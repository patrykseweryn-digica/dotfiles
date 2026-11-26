---
name: verify-dotfiles
description: Verify dotfiles CLI setup, latest tool updates and live machine drift on macOS or Linux before applying configuration or committing changes.
---

# Verify dotfiles

Read [features/README.md](features/README.md), then drive every entry point
listed for the affected features. Use existing checks, not a new runner.

## Launch

Run from the dotfiles checkout. There is no server or persistent test process.
`scripts/test.sh` lists the required commands and reports missing ones.
Without `just`, smoke tests drive the public recipes through `make`.
Smoke tests narrow PATH to stubs, a scratch link to the host jq, and
`/usr/bin:/bin`. The smoke tests require jq 1.7 or newer.
Ubuntu 22.04 ships jq 1.6 in `/usr/bin`, so the version check fails there.
If the check fails, install current jq with mise.
The `pi-config-check` hook installs Pi development dependencies itself.

Create a retained evidence directory:

```bash
mkdir -p .agent-runs/verify-dotfiles
proof=$(mktemp -d "$PWD/.agent-runs/verify-dotfiles/run.XXXXXX")
```

Run each command below
in Bash with `set -o pipefail`; a successful tee must not hide a failed check.
The smoke scripts create and remove their own disposable HOME directories.
Never run full setup against the user's HOME just to test it.

## Machine check

Before changes or machine setup, run the read-only live check:

```bash
just machine >"$proof/machine-before.log" 2>&1
```

Record its exit code even when nonzero. Existing drift is a baseline to
investigate, not permission to erase local settings. Doctor omits raw diffs;
never save raw config or credential files as evidence. If sandbox permissions
block uv caches or network, rerun with the required access; do not weaken tests.

## Drive

For every change, run relevant feature recipes, then before a commit:

```bash
just test 2>&1 | tee "$proof/test.log"
just machine >"$proof/machine-after.log" 2>&1
```

Record both exit codes.
`just test` runs every prek hook; hooks with one `priority` run in
parallel. Commit-time prek hooks remain mandatory.
Do not disable hooks or force a commit through a new failure. With existing
live drift, state exactly what passed and which checks still fail. Before
applying configuration, compare both sides and back up valuable local state.
A passing repository check does not authorize overwriting local preferences.

For changes to the daily workflow, drive all public mutating paths through
their isolated E2E tests:

```bash
bash scripts/smoke-install-dotfiles.sh
bash scripts/smoke-plugin-install.sh
bash scripts/smoke-update-local.sh
bash scripts/smoke-export.sh
bash scripts/smoke-groups.sh
```

These tests drive the public Just and GNU Make commands with disposable HOME
directories and checkouts. Never substitute
a live update or export for this proof.

## Evidence

Capture commands, exit codes, platform (`uname -s` and `uname -m`) and
`git diff --stat` in `$proof/result.txt`, plus the transcripts above.
The install smoke scripts exercise public commands in disposable HOME;
external installers are stubbed at the network/package-manager boundary.
The tool smoke uses a simulated mise provider and generated CLI fixtures.
It exercises the adapter and report, reads fixture versions, checks unchanged
inventory, and tests failures. It does not install real npm packages or prove
their compatibility with a new Node release.
The sync tests check credentials/session preservation and repeated setup.

Record machine failures before and after; investigate new failures. For changed
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
