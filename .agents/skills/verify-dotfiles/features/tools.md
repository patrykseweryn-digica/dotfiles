# Tool inventory and updates

Plan and install core and developer tools from one inventory. Update moving
developer releases without editing that inventory.

## Sub-features

- `outdated` shows only tools with version drift or a missing command.
- `report` shows all installed and expected CLI versions for diagnostics.
- `plan` checks every platform-applicable inventory entry offline.
- `install` skips available commands and uses only declared package names,
  adapters, or platform artifacts.
- `update` updates Node and tools while preserving manifest contents.
- `failure` retains previous Node and stops when downloads fail.

## How to get to it (user POV)

- `just outdated` for tools with a known newer version or missing command.
- `just update` for the full controlled local and upstream update.
- `just install` for setup including missing tools.

## Driving it with Bash smoke scripts

Preconditions: working host Node/npm; no live update needed for verification.

- **Install, update and read back.** Run `bash scripts/smoke-agent-tools.sh`.
  Install skips available tools without a registry query. The internal update
  path installs a real fixture npm CLI from a local tarball, reads its version,
  checks that inventory bytes did not change, and verifies repair after
  independently changing the installed package. Native tools use only their
  declared self-update commands.
- **Core install plan.** Run `bash scripts/smoke-tool-plan.sh`. It exercises
  package managers, explicit Darwin/Linux artifacts, installed-tool skips,
  and failure before network access for an undeclared architecture.
- **Node upgrade.** Run `bash scripts/smoke-node.sh`. It drives bootstrap
  with an isolated nvm provider, changes the upstream version, reads the
  selected Node and default alias, and verifies the previous runtime survives
  download/install failure. No global packages may be imported implicitly.
- **Live report.** Run `just outdated`; capture the exit code. This queries
  npm metadata but does not install tools. It omits current tools and reports
  only drift or missing commands. Native latest versions remain unchecked and
  appear only as one bounded informational message.
- **Proof.** Capture transcripts and versions. All three smoke scripts exit zero.

## Gotchas

- Moving latest can introduce upstream regressions; passed fixtures do not
  prove every external package release works. Check real CLI startup after
  a requested live update and compare doctor results with the baseline.
- Pi extension packages and dependency locks have a separate update policy.
- A registry/network error is an incomplete check, not a missing tool.
