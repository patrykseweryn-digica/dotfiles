# Tool inventory and updates

Plan and install core and developer tools from one inventory. Update moving
developer releases without editing that inventory.

## Sub-features

- `outdated` shows only tools with version drift or a missing command.
- `report` shows all installed and expected CLI versions for diagnostics.
- `plan` checks every platform-applicable inventory entry offline.
- `install` provisions portable core tools through mise and just through uv.
- `update` resolves current stable releases and preserves explicit release pins.
- `system` installs gnupg and xclip with the OS package manager. It reports
  `SKIP` with a reason when Linux has no sudo or macOS has no Homebrew.
- `brewfile` holds only desktop casks; gh, shellcheck and pnpm come from mise.
- `completions` writes the zsh completion of each mise tool that declares
  `zshCompletion` to `~/.zfunc/_<command>`. Plan reports missing or outdated
  files; a failed generator keeps the old file and fails the update.
- `groups` installs and plans only tools of selected install groups
  ([groups](groups.md)).
- The core tool refresh removes the retired Bitwarden CLI and its completion
  when the previous generated mise config still lists the tool.
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
  Update keeps release channels without changing inventory bytes. Fixtures
  cover pinned npm builds, uv tools, GitHub extensions, repeated install,
  release-preserving update, offline checks and installer failures.
  Native tools use only their declared self-update commands.
  Treehouse uses the managed public
  release redirect and skips a current binary. Codex upgrades its cask on
  macOS and reruns OpenAI's installer on Linux. Inside a Herdr pane, the Herdr
  update is skipped with an instruction and other updates continue.
- **Codex.** Run `bash scripts/smoke-codex-native.sh`. On Linux it drives
  OpenAI's installer: fresh install, failed download, update, a foreign
  `codex` on PATH (stop before any change), mise npm migration, plan row.
  On macOS it drives the Homebrew cask: install, upgrade, plan row, and a
  machine without Homebrew.
- **Core install plan.** Run `bash scripts/smoke-tool-plan.sh`. It exercises
  the public core-tools interface. The test covers macOS arm64, Linux x86_64,
  Linux arm64, install, update, generated config, system-tool separation,
  Homebrew without sudo, required tool groups, group skips, and zsh
  completions: written, outdated, missing, kept on generator failure,
  limited to selected groups, and rejected when declared invalid.
  Core-only install and update must install pinned rust-just through uv.
  The generated config must keep pre-commit and add prek.
  A failed uv install must fail core provisioning.
- **Retired core tool.** Run `just sync` in an isolated HOME with the previous
  generated mise config, installed aqua versions, and `~/.zfunc/_bw`. Require
  both versions and the completion to disappear. Verify that unrelated files
  stay and that a second sync succeeds. Use real mise for uninstall.
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
