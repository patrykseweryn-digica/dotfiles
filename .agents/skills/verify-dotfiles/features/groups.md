# Install groups

A machine selects install groups: `core`, `agents`, `desktop`. `install` and
`sync` install and update only elements of selected groups. The plan reports
other elements as `SKIP ... skipped: group <name> is not selected`.

## Sub-features

- `setting` reads `DOTFILES_GROUPS` only from the local env file
  (`DOTFILES_ENV_FILE`, default `.env`). No setting selects all groups.
- `validation` rejects an unknown group or a list without `core` before
  any change: before install steps, the sync fetch, and doctor planning.
- `install` skips install steps of unselected groups and names the group in
  the step summary.
- `plan` reports skipped tools, links, settings, MCP, skills, plugins, hooks
  and Node as `SKIP` with the group name. Sync and doctor pass when only
  `SKIP` rows remain.
- `sync` skips refresh phases of unselected groups; core tools still update.

## How to get to it (user POV)

- Set `DOTFILES_GROUPS=core` or `DOTFILES_GROUPS=core,agents` in `.env`.
- Run `just install`, `just sync` or `just doctor`.

## Driving it with Bash smoke scripts

Preconditions: dependencies from SKILL.md; run from the checkout root.

- **Public commands.** Run `bash scripts/smoke-groups.sh`. In disposable
  HOME directories it drives `just install`, `just doctor` and `just sync`
  with no setting, core only, an unknown group and a list without core.
  Core only must skip agent and desktop steps, links and phases, and pass.
  Invalid settings must leave HOME, the checkout and the call log unchanged.
  The real planners run; external installers and core tools are simulated.
- **Tool groups.** Run `bash scripts/smoke-tool-plan.sh`. It rejects a tool
  without a group, skips a desktop-group core tool on a core-only machine,
  and requires native Bitwarden CLI (`aqua:bitwarden/clients`) in core.
- **Proof.** Capture stdout/stderr and exit codes; each script must exit zero.

## Gotchas

- Switching off a group does not remove its installed elements or links.
- The fixtures do not prove real downloads on a Raspberry Pi. Run
  `just sync` and `just doctor` on the machine and record the result.
- Smoke scripts that call real planners must set `DOTFILES_ENV_FILE` to a
  fixture path; otherwise the machine's own groups change their results.
