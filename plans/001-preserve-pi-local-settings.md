# Plan 001: Preserve Pi installation-local settings

> **Executor instructions**: Follow every step and verification gate. If a
> STOP condition occurs, report it instead of improvising. Update this plan's
> row in `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check**:
>
> ```bash
> git diff --stat deba8d0..HEAD -- \
>   sync-agents.sh scripts/smoke-install-dotfiles.sh README.md
> ```
> Compare the excerpts below if any in-scope file changed.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: bug, security
- **Planned at**: commit `deba8d0`, 2026-10-09

## Why this matters

Pi stores a stable installation UUID in global `settings.json`; its OAuth flow
requires that identifier. Pi may also store API keys there. Current sync
replaces the complete file with repository preferences and preserves only the
changelog version. A routine `just update` therefore deletes local identity
and may delete credentials.

The live installation already contains `deviceId`. An isolated public
`pi-install` reproduction removed a sentinel `deviceId`.

## Current state

- `sync-agents.sh:3223-3241` renders `$wanted[0]` and only adds
  `lastChangelogVersion` from the live file.
- `sync-agents.sh:3369-3388` uses that destructive render for drift checks.
- `scripts/smoke-install-dotfiles.sh:208-266` verifies changelog preservation
  but does not cover `deviceId`, `trackingId`, or `apiKeys`.
- `README.md:90-105` promises that Pi runtime state and credentials remain
  local.

Relevant current shape:

```sh
# sync-agents.sh:3227
.lastChangelogVersion? as $last
| $wanted[0]
+ if $last == null then {} else {lastChangelogVersion: $last} end
```

Upstream Pi v1.0.0 defines `deviceId` as a stable global installation UUID.
It also supports `apiKeys` in global settings and treats `trackingId` and
`deviceId` as private report data.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Baseline | `just doctor` | Existing drift recorded |
| Targeted test | `bash scripts/smoke-install-dotfiles.sh` | Exit 0 |
| Full checks | `just check` | Every hook passes |
| Regression | `just doctor` | No new failure |

Use `.agents/skills/verify-dotfiles/SKILL.md` and retain its evidence.

## Scope

**In scope**:

- `sync-agents.sh`
- `scripts/smoke-install-dotfiles.sh`
- `README.md`, only if its Pi preservation statement needs precision

**Out of scope**:

- Live `~/.pi/agent/settings.json`
- Repository model or package choices
- Pi authentication, sessions, or OAuth files
- Exporting any local identifier or credential into the repository

## Git workflow

- Branch: `advisor/001-preserve-pi-local-settings`
- Conventional commit example: `fix(pi): preserve local settings state`
- Do not push unless requested.

## Steps

### Step 1: Add the failing regression

Extend the existing Pi fixture in
`scripts/smoke-install-dotfiles.sh:208-266`.

The fixture must place these sentinels in the live settings:

- `lastChangelogVersion`
- `deviceId`
- `trackingId`
- `apiKeys` with a fake, non-secret value

Drive the public `pi-install` path in an isolated HOME. Assert that repository
preferences converge while all four local fields remain byte-equivalent as
JSON values. Never print the fake API-key value.

Also assert `pi-check` accepts the converged merged result.

**Verify**: `bash scripts/smoke-install-dotfiles.sh` must fail on the new
preservation assertion before the implementation change.

### Step 2: Preserve only explicit installation-local fields

Change `render_pi_settings` to keep exactly these live keys:

- `lastChangelogVersion`
- `deviceId`
- `trackingId`
- `apiKeys`

Repository settings must still win for every key present in
`config/pi/settings.json`. Do not merge arbitrary unknown keys, because that
would make removed managed preferences silently permanent.

Reject any repository Pi template that declares an installation-local key.
This prevents a later edit from committing a device identifier or API key.
The error must name the key, never its value.

**Verify**: `bash scripts/smoke-install-dotfiles.sh` exits 0.

### Step 3: Prove export privacy and idempotence

Extend the existing export/settings fixture only if current coverage does not
already prove this boundary. A Pi export candidate must omit all four local
keys, and a repeated `pi-install` must not rewrite a converged file.

**Verify**:

```bash
bash scripts/smoke-export.sh
bash scripts/smoke-install-dotfiles.sh
```

Both commands exit 0.

### Step 4: Run repository verification

Follow `verify-dotfiles`: targeted recipes, `just check`, then `just doctor`.
Compare doctor output with the baseline and investigate every new failure.

**Verify**: `just check` exits 0. Doctor has no new category or failure.

## Test plan

- Existing pattern: `smoke_pi_drift_check` in
  `scripts/smoke-install-dotfiles.sh`.
- New regression: public install preserves four explicit local fields.
- Managed drift still converges to repository values.
- Template inclusion of a local-only key fails without printing its value.
- Export excludes local-only keys.
- Repeated install is idempotent.

## Done criteria

- [ ] The pre-fix fixture fails for deleted `deviceId`.
- [ ] All four local fields survive `pi-install`.
- [ ] Managed Pi preferences still converge.
- [ ] No local field enters a repository export candidate.
- [ ] `just check` passes.
- [ ] Doctor has no new failure.
- [ ] Only in-scope files and `plans/README.md` changed.

## STOP conditions

- Upstream Pi no longer stores these fields in global settings.
- Preserving the fields requires reading or logging real credential values.
- The fix requires changing live Pi state during verification.
- A second unrelated settings owner appears in the same file.

## Maintenance notes

When Pi adds another installation-local or sensitive global setting, update
the explicit preservation list and privacy tests together. Reviewers should
reject a generic merge of all unknown keys.

