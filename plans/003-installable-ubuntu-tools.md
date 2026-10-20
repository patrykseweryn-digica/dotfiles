# Plan 003: Make the Ubuntu tool inventory installable

> **Executor instructions**: Follow every step and verification gate. If a
> STOP condition occurs, report it instead of improvising. Update this plan's
> row in `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check**:
>
> ```bash
> git diff --stat deba8d0..HEAD -- .agents/tool-versions.json \
>   scripts/agent-tools.sh scripts/smoke-tool-plan.sh \
>   scripts/smoke-agent-tools.sh README.md
> ```
> Compare the excerpts below if any in-scope file changed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-keep-local-mcp-local.md`
- **Category**: bug, dx
- **Planned at**: commit `deba8d0`, 2026-10-09

## Why this matters

The manifest declares `hadolint` and `bitwarden-cli` for Linux, but neither
has an Ubuntu apt package or a Linux artifact in the inventory. On this
Ubuntu host, `just doctor` reports both missing and `just update` has no
supported installation source. The repository's convergence promise is false.

Hadolint publishes native Linux and macOS binaries. Bitwarden documents
`npm install -g @bitwarden/cli` as the preferred method when Node is already
present, which this repository guarantees before developer tools.

## Current state

- `.agents/tool-versions.json:246-269` declares both tools as core and defaults
  them to every supported platform.
- `scripts/agent-tools.sh:9-68` validates shapes but not that each supported
  Ubuntu target has an install source.
- `scripts/smoke-tool-plan.sh:192` discards the aggregate installer failure.
- `scripts/smoke-tool-plan.sh:195-206` omits Ubuntu assertions for these tools.
- Latest official Hadolint release inspected during planning: `v2.15.1`.
  Assets are `hadolint-linux-x86_64`, `hadolint-linux-arm64`,
  `hadolint-macos-x86_64`, and `hadolint-macos-arm64`.

Follow the established raw-binary artifact pattern used by `jq` and
`tealdeer`. Follow existing npm tool entries for Bitwarden.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Baseline | `just doctor` | Existing drift recorded |
| Core plan | `bash scripts/smoke-tool-plan.sh` | Exit 0 |
| Agent tools | `bash scripts/smoke-agent-tools.sh` | Exit 0 |
| Full checks | `just check` | Every hook passes |

Use `.agents/skills/verify-dotfiles/SKILL.md` and retain its evidence.

## Suggested executor toolkit

- Use Context7 for current Hadolint and Bitwarden installation docs.
- Use `gh-axi` for current GitHub release inspection. If it cannot expose
  assets, use read-only `gh release view --json assets`.

## Scope

**In scope**:

- `.agents/tool-versions.json`
- `scripts/agent-tools.sh`
- `scripts/smoke-tool-plan.sh`
- `scripts/smoke-agent-tools.sh`
- `README.md`, only for inventory policy changes

**Out of scope**:

- Installing tools on the live machine
- Adding a new package manager or installer framework
- Updating unrelated pinned tools
- Running `just update` against the user's HOME

## Git workflow

- Branch: `advisor/003-installable-ubuntu-tools`
- Conventional commit example: `fix(tools): support Ubuntu tool convergence`
- Do not push unless requested.

## Steps

### Step 1: Add manifest validation regressions

Add a fixture proving a core tool declared for `linux-x86_64` is invalid when
it has neither an apt package nor a matching GitHub artifact. Add the matching
Darwin invariant for brew or an artifact.

Keep dnf and pacman package fields supported, but do not let them stand in for
the Ubuntu target used by CI and documented Linux verification.

**Verify**: `bash scripts/smoke-agent-tools.sh` fails before validation is
strengthened.

### Step 2: Add portable Hadolint artifacts

Keep Hadolint as a core tool. Add the official `v2.15.1` GitHub release and
all four supported platform artifacts. Each raw asset is both `archive` and
`binary`; set `installedName` to `hadolint`.

Do not add a custom downloader. Existing `install_github_binary` already
handles raw files by finding the downloaded file and marking it executable.

Add targeted assertions for Ubuntu x86_64 and at least one ARM64 or macOS
artifact. The Ubuntu fixture must prove the GitHub fallback is selected when
apt has no package.

**Verify**: `bash scripts/smoke-tool-plan.sh` exits 0.

### Step 3: Manage Bitwarden through its official npm package

Convert Bitwarden CLI to the existing agent-tool schema:

```json
{
  "name": "Bitwarden CLI",
  "command": "bw",
  "package": "@bitwarden/cli",
  "installer": "npm",
  "channel": "latest"
}
```

This must use the existing Node/npm install, report, update, and export paths.
Do not introduce Snap, Flatpak, or a Bitwarden-specific installer.

Add a fixture proving missing `bw` schedules the npm package and a present
`bw` skips installation.

**Verify**: `bash scripts/smoke-agent-tools.sh` exits 0.

### Step 4: Strengthen the installer smoke contract

Remove the ability of the Ubuntu core-plan fixture to hide unsupported
declared tools with an unconditional aggregate `|| true`. If individual
failure adapters are intentionally stubbed, isolate them into focused
fixtures so the manifest-wide Ubuntu plan itself must succeed.

**Verify**:

```bash
bash scripts/smoke-tool-plan.sh
bash scripts/smoke-agent-tools.sh
```

Both exit 0.

### Step 5: Run full verification

Run the relevant recipes and `just check`. Do not install on the live machine.
The final live doctor may still report missing tools until the user explicitly
approves a live update.

**Verify**: `just check` exits 0; doctor has no new category or failure.

## Test plan

- Invalid Ubuntu core entry without apt/artifact is rejected.
- Hadolint raw binary selection covers Linux x86_64 and another platform.
- Bitwarden npm install and installed skip both work.
- A failed download leaves previous tools intact.
- Inventory export does not rediscover declared `@bitwarden/cli`.

## Done criteria

- [ ] Every Ubuntu-applicable core tool has apt or GitHub installation.
- [ ] Hadolint has official artifacts for all supported platforms.
- [ ] Bitwarden uses the existing npm tool lifecycle.
- [ ] Manifest-wide Ubuntu smoke no longer hides aggregate failure.
- [ ] Targeted tests and `just check` pass.
- [ ] No live tool was installed or changed.

## STOP conditions

- Official release asset names differ from those listed above.
- `bw --version` does not emit a parseable semantic version.
- The npm package requires unsupported post-install permissions.
- The fix requires adding a new installer abstraction.

## Maintenance notes

Hadolint is pinned like other artifact-backed core tools; future bumps must
update tag and asset tests together. Bitwarden follows npm `latest`, matching
the repository's developer-tool policy.

