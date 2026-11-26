# Install groups

A machine selects install groups: `core`, `agents`, `desktop`. `install` and
`sync` install and update only elements of selected groups. The plan reports
other elements as `SKIP ... skipped: group <name> is not selected`.

## Sub-features

- `setting` reads `DOTFILES_GROUPS` only from the local env file
  (`DOTFILES_ENV_FILE`, default `.env`). No setting selects core only.
- `commands`: `just groups` shows the selection. `just enable <group>`
  writes the group into the env file and runs install. `just disable <group>`
  removes the group and keeps its installed elements. Core cannot be disabled.
- `validation` rejects an unknown group or a list without `core` before
  any change: before install steps, the sync fetch, and machine planning.
- `install` skips install steps of unselected groups and names the group in
  the step summary.
- `plan` reports skipped tools, links, settings, MCP, skills, plugins, hooks
  and Node as `SKIP` with the group name. Sync and machine pass when only
  `SKIP` rows remain.
- `sync` skips refresh phases of unselected groups; core tools still update.
- `notice`: when managed links of an unselected group remain, the plan adds
  `SKIP groups: Group <name> is installed but not selected; ...` with
  `Run: just enable <name>`. Sync and machine still pass.

## How to get to it (user POV)

- Run `just groups`, `just enable agents` or `just disable desktop`.
- Run `just install`, `just sync` or `just machine`.
- With Make, use `make groups`, `make enable group=agents`, or
  `make disable group=desktop`.

## Driving it with Bash smoke scripts

Preconditions: dependencies from SKILL.md; run from the checkout root.

- **Public commands.** Run `bash scripts/smoke-groups.sh`. In disposable
  HOME directories it drives `make install`, `make machine` and `make sync`
  with no setting, core only, all groups, an unknown group and a list
  without core. No setting and core only must skip agent and desktop steps,
  links and phases, and pass. Doctor without a setting in a HOME with all
  groups installed must print one `groups` notice per group and pass.
  It also drives `make groups`, `make enable` and `make disable` on a
  fixture env file: in-place writes, canonical order, duplicate lines,
  and invalid commands that leave the file unchanged.
  Invalid settings must leave HOME, the checkout and the call log unchanged.
  The real planners run; external installers and core tools are simulated.
- **Tool groups.** Run `bash scripts/smoke-tool-plan.sh`. It rejects a tool
  without a group, skips a desktop-group core tool on a core-only machine,
  and requires `gh` in core.
- **Proof.** Capture stdout/stderr and exit codes; each script must exit zero.

## Gotchas

- `just disable` does not remove installed elements or links.
- A machine without a setting gets core only. Run `just enable agents` and
  `just enable desktop` there to keep updating those groups.
- The fixtures do not prove real downloads on a Raspberry Pi. Run
  `just sync` and `just machine` on the machine and record the result.
- Smoke scripts that call real planners must set `DOTFILES_ENV_FILE` to a
  fixture path; otherwise the machine's own groups change their results.
