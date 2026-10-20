# Plan 004: Make doctor genuinely read-only

> **Executor instructions**: Follow every step and verification gate. If a
> STOP condition occurs, report it instead of improvising. Update this plan's
> row in `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check**:
>
> ```bash
> git diff --stat deba8d0..HEAD -- scripts/agent-tools.sh \
>   scripts/smoke-agent-tools.sh scripts/smoke-doctor.sh README.md
> ```
> Compare the excerpts below if any in-scope file changed.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/003-installable-ubuntu-tools.md`
- **Category**: bug, dx
- **Planned at**: commit `deba8d0`, 2026-10-09

## Why this matters

`just doctor` promises an offline inspection without writes. Its agent-tool
plan executes every CLI with `--version`. Hermes acquires an installation lock
even for that command, so a read-only sandbox reports a false missing-tool
failure. Other CLIs can gain similar startup side effects later.

The separate `agent-versions` report is the correct place to execute version
commands. Doctor needs only inventory availability.

## Current state

- `README.md:8-15` promises doctor is offline and write-free.
- `scripts/state-plan.sh:51-53` delegates tool state to `agent-tools plan`.
- `scripts/agent-tools.sh:246-254` executes `<command> --version`.
- `scripts/agent-tools.sh:310-330` uses that function for every agent tool.
- `scripts/smoke-agent-tools.sh:120-147` expects versions in plan output but
  does not test a CLI whose version command writes.

Current behavior:

```sh
output=$("$command_name" --version 2>/dev/null) || return 1
```

In the sandbox, Hermes failed while attempting to write an install lock. The
same live doctor outside the sandbox reported Hermes available.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Baseline | `just doctor` | Existing drift recorded |
| Tool test | `bash scripts/smoke-agent-tools.sh` | Exit 0 |
| Doctor test | `bash scripts/smoke-doctor.sh` | Exit 0 |
| Full checks | `just check` | Every hook passes |

Use `.agents/skills/verify-dotfiles/SKILL.md` and retain its evidence.

## Scope

**In scope**:

- `scripts/agent-tools.sh`
- `scripts/smoke-agent-tools.sh`
- `scripts/smoke-doctor.sh`
- `README.md`, only if output semantics need clarification

**Out of scope**:

- Changing `agent-versions`; it should continue executing version commands
- Hermes-specific environment variables or a Hermes name special case
- Updating or reinstalling any live CLI
- Weakening missing-command detection

## Git workflow

- Branch: `advisor/004-read-only-doctor`
- Conventional commit example: `fix(doctor): avoid executing managed CLIs`
- Do not push unless requested.

## Steps

### Step 1: Add a side-effecting CLI fixture

Add an agent-tool stub that exists and is executable, but whose `--version`
attempts to write a sentinel and exits nonzero when writes are blocked.

Assert `agent-tools plan`:

- reports the command available;
- does not create the sentinel;
- performs no npm or network query.

Keep a separate `agent-versions` assertion proving the report still executes
the version command.

**Verify**: `bash scripts/smoke-agent-tools.sh` fails before the fix.

### Step 2: Separate availability planning from version reporting

Change `plan_tools` to use command discovery only for agent and core tools.
Do not call `installed_version` from the doctor plan. Report agent tools as
`<name> is available`; retain the existing tab-separated plan contract.

Keep `installed_version` for explicit report, install, and update flows.
Change failure text from `missing or not runnable` to `missing` if the plan no
longer executes a health probe.

Do not special-case Hermes. The contract must protect every present and future
CLI.

**Verify**: `bash scripts/smoke-agent-tools.sh` exits 0.

### Step 3: Prove doctor does not execute tool commands

Extend `scripts/smoke-doctor.sh` so its tool planner fixture fails the test if
any managed CLI is invoked. Preserve the existing bounded diagnostics and
network-blocking assertions.

**Verify**: `bash scripts/smoke-doctor.sh` exits 0.

### Step 4: Run live and full verification

Run `just doctor` in the ordinary sandbox and outside it. Hermes must have the
same status in both outputs. The only expected live hard failures are genuinely
missing commands.

Then run `just check` and compare doctor output with the baseline.

**Verify**: `just check` exits 0; sandbox and live Hermes status match.

## Test plan

- Plan checks command existence without execution.
- Missing command remains `FAIL` with action `update`.
- Explicit version report still parses semantic versions.
- No registry or network access occurs in plan mode.
- Doctor output stays bounded and contains no raw configuration.

## Done criteria

- [ ] No managed CLI executes during `agent-tools plan`.
- [ ] Hermes has identical doctor status inside and outside the sandbox.
- [ ] `agent-versions` still reports versions.
- [ ] Missing commands still fail doctor.
- [ ] Targeted tests and `just check` pass.
- [ ] Only in-scope files and `plans/README.md` changed.

## STOP conditions

- A caller depends on version text in state-plan output for control flow.
- Command discovery itself invokes the target on a supported shell.
- Fixing doctor requires changing explicit report or update semantics.

## Maintenance notes

Keep availability checks and version reports separate. Any future doctor probe
must be proven offline and write-free with an adversarial fixture.

