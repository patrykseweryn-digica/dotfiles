# Tool inventory and updates

List tools and update their latest releases without editing the inventory.

## Sub-features

- `report` shows installed and expected CLI versions.
- `update` updates Node and tools while preserving manifest contents.
- `failure` retains previous Node and stops when downloads fail.

## How to get to it (user POV)

- `just agent-versions` for the live version report.
- `just update-agent-tools` for an explicit update.
- `just install` for setup including latest tools.

## Driving it with Bash smoke scripts

Preconditions: working host Node/npm; no live update needed for verification.

- **Update and read back.** Run `bash scripts/smoke-agent-tools.sh`. Its
  public just update installs a real fixture npm CLI from a local tarball,
  reads its version, checks that inventory bytes did not change, and verifies
  repair after independently changing the installed package.
- **Node upgrade.** Run `bash scripts/smoke-node.sh`. It drives bootstrap
  with an isolated nvm provider, changes the upstream version, reads the
  selected Node and default alias, and verifies the previous runtime survives
  download/install failure. No global packages may be imported implicitly.
- **Live report.** Run `just agent-versions`; capture the exit code. This
  queries npm metadata but does not install tools. Native reports verify
  availability only; they cannot prove those tools match upstream latest.
- **Proof.** Capture transcripts and versions. Both smoke scripts exit zero.

## Gotchas

- Moving latest can introduce upstream regressions; passed fixtures do not
  prove every external package release works. Check real CLI startup after
  a requested live update and compare doctor results with the baseline.
- Pi extension packages and dependency locks have a separate update policy.
- A registry/network error is an incomplete check, not a missing tool.
