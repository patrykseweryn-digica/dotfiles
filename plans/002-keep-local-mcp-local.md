# Plan 002: Keep non-portable MCP servers local

> **Executor instructions**: Follow every step and verification gate. If a
> STOP condition occurs, report it instead of improvising. Update this plan's
> row in `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check**:
>
> ```bash
> git diff --stat deba8d0..HEAD -- sync-agents.sh \
>   scripts/smoke-export.sh scripts/smoke-doctor.sh \
>   scripts/smoke-agent-sync-interface.sh README.md
> ```
> Compare the excerpts below if any in-scope file changed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-preserve-pi-local-settings.md`
- **Category**: bug
- **Planned at**: commit `deba8d0`, 2026-10-09

## Why this matters

Codex exposes the bundled `cua_repl` MCP server with absolute paths under
`/usr/lib/chatgpt`. The state planner treats it as a portable local addition
and tells the user to run `just export`. Export then rejects the same server as
a local path before presenting any plan. This blocks every unrelated settings,
skills, plugin, and tool export in the transaction.

An EOF-driven public `just export` reproduction exits 1 with
`MCP export contains a local path or secret`.

## Current state

- `sync-agents.sh:475-517` imports every enabled Codex MCP server.
- `sync-agents.sh:637-671` builds one candidate from all runtimes.
- `sync-agents.sh:878-908` rejects absolute stdio commands and arguments.
- `sync-agents.sh:3439-3505` labels any live candidate addition `EXPORT`.
- `scripts/smoke-export.sh:437-449` expects one local path to abort export.
- `README.md:22-28` says local paths stay local.

The required invariant is:

```text
portable unmanaged addition -> export candidate
non-portable unmanaged addition -> retained locally, excluded from candidate
non-portable definition for a repository-managed server -> hard failure
```

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Baseline | `just doctor` | Existing drift recorded |
| Export E2E | `bash scripts/smoke-export.sh` | Exit 0 |
| Sync E2E | `bash scripts/smoke-agent-sync-interface.sh` | Exit 0 |
| Doctor E2E | `bash scripts/smoke-doctor.sh` | Exit 0 |
| Full checks | `just check` | Every hook passes |

Use `.agents/skills/verify-dotfiles/SKILL.md` and retain its evidence.

## Scope

**In scope**:

- `sync-agents.sh`
- `scripts/smoke-export.sh`
- `scripts/smoke-doctor.sh`
- `scripts/smoke-agent-sync-interface.sh`
- `README.md`, only for clarified behavior

**Out of scope**:

- Hardcoding the name `cua_repl`
- Persisting `/usr/lib/chatgpt` or another host path
- Changing live MCP configurations
- Weakening conflict detection for repository-managed servers
- Exporting environment values, headers, OAuth state, or secrets

## Git workflow

- Branch: `advisor/002-keep-local-mcp-local`
- Conventional commit example: `fix(export): ignore local-only MCP servers`
- Do not push unless requested.

## Steps

### Step 1: Add a real-shaped failing fixture

Extend the existing MCP fixtures with an enabled, Codex-only stdio server
whose command and first argument are absolute `/usr/lib/...` paths. Do not use
the literal server name as production logic; the fixture may call it
`runtime-bundled`.

Assert:

- state-plan does not label the category `EXPORT` solely for that server;
- export can still plan and apply unrelated portable additions;
- the local-only server remains untouched in the runtime;
- the server never enters `.agents/mcp-servers.json`.

Keep the existing managed-server conflict cases.

**Verify**: at least one targeted smoke command fails before the fix.

### Step 2: Centralize MCP portability classification

Create one jq-backed classification used by state-plan, pull, and export.
Reuse the existing path and secret rules from `validate_mcp_candidate`; do not
maintain two divergent regexes.

When building a candidate:

1. Keep all repository-managed server names for comparison.
2. Keep unmanaged servers only when their normalized definition is portable.
3. Record non-portable unmanaged names for bounded diagnostics, without
   printing commands, arguments, URLs, headers, or values.
4. Fail if a repository-managed name resolves to a non-portable definition.

The diagnostic may say a named server remains local. It must not recommend
`update` or `export` for that fact alone.

**Verify**:

```bash
bash scripts/smoke-agent-sync-interface.sh
bash scripts/smoke-doctor.sh
```

Both exit 0.

### Step 3: Align transactional export

Update export candidate construction to consume the filtered portable
candidate. Keep `validate_mcp_candidate` as a final trust-boundary assertion.
It must still reject any non-portable repository-managed definition that
reaches it.

Change the old Pi-only local-path test from "abort everything" to:

- local definition stays byte-equivalent;
- no local path enters the checkout;
- unrelated portable export targets can succeed.

**Verify**: `bash scripts/smoke-export.sh` exits 0.

### Step 4: Run the live read-only regression

With a clean worktree, run `just doctor` against the real machine. Confirm the
MCP category is no longer `EXPORT` solely because of `cua_repl`. Run
`just export </dev/null`; it may cancel at the prompt, but it must reach the
plan instead of failing local-path validation.

Do not answer yes and do not change live or repository state.

**Verify**: doctor has no MCP false export; EOF export reaches cancellation.

### Step 5: Run full verification

Follow `verify-dotfiles`, including the four public mutating smoke paths and
`just check`. Compare live doctor output with the baseline.

**Verify**: `just check` exits 0 and no new doctor failure appears.

## Test plan

- Codex-only absolute stdio server stays local.
- Portable extra server remains exportable.
- Managed server with a local path fails safely.
- Conflicting runtime definitions still fail.
- Secret-bearing and credential-bearing definitions never appear in output.
- Export of unrelated categories is no longer blocked.

## Done criteria

- [ ] The live `cua_repl` server causes no `EXPORT` recommendation.
- [ ] EOF `just export` reaches a reviewable plan or cancellation.
- [ ] No absolute path or secret enters the repository candidate.
- [ ] Managed MCP drift and conflicts remain detectable.
- [ ] All targeted smoke tests and `just check` pass.
- [ ] Only in-scope files and `plans/README.md` changed.

## STOP conditions

- Codex exposes no stable way to distinguish the managed server set.
- Filtering requires inspecting or printing credential values.
- A local-only server shares a name with a repository-managed server.
- The proposed change would silently accept a managed definition conflict.

## Maintenance notes

Portability is a property of normalized server data, not a server-name
blacklist. Reviewers should reject any `cua_repl` special case.

