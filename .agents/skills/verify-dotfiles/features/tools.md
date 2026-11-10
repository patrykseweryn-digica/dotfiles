# Tool inventory and updates

Plan and install core and developer tools from one inventory. Update moving
developer releases without editing that inventory.

## Sub-features

- `outdated` shows only tools with version drift or a missing command.
- `report` shows all installed and expected CLI versions for diagnostics.
- `plan` checks every platform-applicable inventory entry offline.
- `install` provisions portable core tools through mise.
- `update` resolves current stable releases without stored version numbers.
- `failure` retains previous Node and stops when downloads fail.

## How to get to it (user POV)

- `just sync` for the full controlled local and upstream update.
- `just install` for setup including missing tools.

## Driving it with Bash smoke scripts

Preconditions: working host Node/npm; no live update needed for verification.

- **Install, update and read back.** Run `bash scripts/smoke-agent-tools.sh`.
  Install migrates npm CLI entries to independent mise tools. The test changes
  the selected LTS runtime and starts every npm CLI without reinstalling it.
  Update keeps `latest` without changing inventory bytes. Native tools use only
  their declared self-update commands. Treehouse uses the managed public
  release redirect and skips a current binary. Inside a Herdr pane, the Herdr
  update is skipped with an instruction and other updates continue.
- **Core install plan.** Run `bash scripts/smoke-tool-plan.sh`. It exercises
  the public core-tools interface. The test covers macOS arm64, Linux x86_64,
  Linux arm64, install, update, generated config, and system-tool separation.
- **Node upgrade.** Run `bash scripts/smoke-node.sh`. It drives bootstrap
  with an isolated mise provider, changes the resolved LTS version, reads the
  selected Node, and verifies the previous runtime survives download/install
  failure. The bootstrap must reject a non-LTS policy.
- **Live report.** Run `./scripts/agent-tools.sh outdated`; capture the exit
  code. This queries npm metadata but does not install tools. It omits current
  tools and reports only drift or missing commands. Native latest versions
  remain unchecked. One bounded message reports that limitation.
- **Proof.** Capture transcripts and versions. All three smoke scripts exit zero.

## Gotchas

- Moving latest can introduce upstream regressions; passed fixtures do not
  prove every external package release works. Check real CLI startup after
  a requested live update and compare doctor results with the baseline.
- Pi extension packages and dependency locks have a separate update policy.
- A registry/network error is an incomplete check, not a missing tool.
