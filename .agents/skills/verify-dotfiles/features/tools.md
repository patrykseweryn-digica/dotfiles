# Tool inventory and updates

Plan and install core and developer tools from one inventory. Update moving
developer releases without editing that inventory.

## Sub-features

- `outdated` shows only tools with version drift or a missing command.
- `report` shows all installed and expected CLI versions for diagnostics.
- `plan` checks every platform-applicable inventory entry offline.
- `install` provisions portable core tools through mise.
- `update` resolves current stable releases without stored version numbers.
- `system` installs gnupg and xclip with the OS package manager. It reports
  `SKIP` with a reason when Linux has no sudo or macOS has no Homebrew.
- `brewfile` holds only desktop casks; gh, shellcheck and pnpm come from mise.
- `groups` installs and plans only tools of selected install groups;
  Bitwarden CLI is a native core tool ([groups](groups.md)).
- `failure` retains previous Node and stops when downloads fail.

## How to get to it (user POV)

- `just sync` for the full controlled local and upstream update.
- `just install` for setup including missing tools.

## Driving it with Bash smoke scripts

Preconditions: working host Node/npm; no live update needed for verification.

- **Install, update and read back.** Run `bash scripts/smoke-agent-tools.sh`.
  Install migrates npm CLI entries to independent mise tools. The test changes
  the selected LTS runtime and starts generated CLI fixtures without
  reinstalling them. The mise provider is simulated; real package startup
  and Node compatibility require separate live evidence.
  Update keeps `latest` without changing inventory bytes. Native tools use only
  their declared self-update commands. Treehouse uses the managed public
  release redirect and skips a current binary. Codex reruns OpenAI's
  installer, which skips a current release. Inside a Herdr pane, the Herdr
  update is skipped with an instruction and other updates continue.
- **Codex.** Run `bash scripts/smoke-codex-native.sh`. It drives the official
  installer path: fresh install, failed download, update, a foreign `codex`
  on PATH (stop before any change), mise npm migration, and the plan row.
- **Core install plan.** Run `bash scripts/smoke-tool-plan.sh`. It exercises
  the public core-tools interface. The test covers macOS arm64, Linux x86_64,
  Linux arm64, install, update, generated config, system-tool separation,
  Homebrew without sudo, required tool groups, and group skips.
- **Node upgrade.** Run `bash scripts/smoke-node.sh`. It drives bootstrap
  with an isolated mise provider, changes the resolved LTS version, reads the
  selected Node, and verifies the previous runtime survives download/install
  failure. The bootstrap must reject a non-LTS policy.
- **Treehouse update.** Run `bash scripts/smoke-treehouse.sh`. Check supported
  platform fixtures, successful upgrades, preservation after failed downloads,
  unchanged current binaries, and unsupported architecture rejection.
- **Live report.** Run `./scripts/agent-tools.sh outdated`; capture the exit
  code. This queries npm metadata but does not install tools. It omits current
  tools and reports only drift or missing commands. Claude native releases
  use npm metadata; other native updater versions remain unchecked.
  One bounded message reports that limitation.
- **Proof.** Capture transcripts and versions. All five smoke scripts exit zero.

## Gotchas

- Moving latest can introduce upstream regressions; passed fixtures do not
  prove every external package release works. Check real CLI startup after
  a requested live update and compare doctor results with the baseline.
- Pi extension packages and dependency locks have a separate update policy.
- A registry/network error is an incomplete check, not a missing tool.
