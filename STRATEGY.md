# dotfiles Strategy

## Vision
<!-- vision: author-approved 2026-11-25 -->

`dotfiles` lets its owner set up a consistent, declared development environment with one command.
It serves the owner's macOS and Linux machines, from a Raspberry Pi to a MacBook.
It supports Linux installation with and without `sudo`.
It owns one thing: the portable configuration of the owner's shell, developer tools, and agent harnesses.
An agent harness connects a model to tools and manages an agent session.

### The repository is the source of truth

`sync` applies the repository's declared state. Only `export` brings portable changes back.
If `sync` detects a portable local addition, it stops before making changes and names the next step.
`export` writes only reviewed changes from an allowlist. It never stages, commits, or pushes.
Each managed area has one authoritative declaration. Tests and scripts do not duplicate its membership.
The installation mechanism can change if it preserves these rules and the release policy below.

### Follow upstream without keeping copies

Tools, agent harnesses, skills, and plugins follow current upstream releases.
`mise` installs Node LTS only when a selected tool requires it.
`sync` makes agent CLI releases available on release day. An installer that delays them does not qualify.
A version pin is a reviewed exception recorded in the inventory, not a way to hide a failure.
Skills install from their declared upstream, including personal skills from `p-severin/skills`.
A fetch failure fails the phase. `sync` does not install a stale copy instead.
The repository reconciles upstream removals and renames before `sync` changes harness configuration.
`sync` removes retired tools installed by a previous managed configuration.

### Report the actual state

`machine`, `sync`, and `export` use one plan with five statuses: PASS, UPDATE, EXPORT, FAIL, and SKIP.
`machine` runs offline and does not write, including through tools it calls.
A machine is fully aligned only when all rows are PASS or SKIP.
Errors name the item, operation, cause, and next step. A failed optional step is still a failure.
Unreadable input stops the run instead of widening its scope.
`sync` does not kill existing processes or restart services, even through installers it calls.
If a service needs a restart, `sync` reports it and the owner restarts it manually.

### Keep secrets local

The repository contains no secrets, even encrypted ones. It declares only the names needed in the local environment.
`machine` can show those names but never their values.
OAuth state, environment values, HTTP headers, machine-specific paths, and session history stay local.
`export` takes a portable setting from the machine only if its key is declared in the template.
Diagnostics do not print raw configuration that might contain secrets.

### Support few harnesses and keep providers separate

`dotfiles` supports Claude Code, Codex, and Pi. Only the owner can approve another harness.
An additional harness costs installation time, verification time, and disk space.
Anthropic marketplaces belong to Claude Code. OpenAI marketplaces belong to Codex.
Checks and exports reject packages from the wrong provider instead of converting them.
Shared skills and global agent instructions have one source and link into each harness.

### Verify changes at a reasonable cost

Tests exercise public commands in an isolated home directory. Live checks compare `just machine` before and after a change.
CI checks Linux, including clean installations without `sudo` on amd64 and arm64.
CI runs on macOS only when a change affects macOS, including changes to shared code.
The macOS job checks only the affected scenarios. Pull requests name any checks that did not run.
A change to file removal in the macOS home directory needs a macOS test before merge. The test confirms that private files remain intact.
Only a run on the affected operating system verifies behavior on that system.
`sync` does not download or reinstall unchanged items. Each check queries each provider at most once.
The repository generates an architecture diagram from its code and declarations.
The SVG shows how declarations, modules, and supported platforms connect, with visible boundaries between them.
The machine-readable graph preserves those relationships, including commands and install groups.
The graph describes repository state. It does not name device models, query machines, or show their local settings.
CI checks that both outputs match the source. The graph marks dependencies it cannot resolve statically.

### Scope

A machine declares a `light` or `full` class. `light` selects fewer tools and simpler settings.
`full` defaults to `core`, `agents`, and `desktop`. An explicit group selection overrides the class defaults.
The `work` group contains employer tools and identity. No class enables it automatically.
The repository does not provide per-host configuration overlays.
Forks can set their own owner, remotes, personal skill source, and Git identities.
The main repository supports only the platforms and shells its owner uses. Forks maintain their own extensions, such as fish or WSL.
`dotfiles` does not manage secrets, orchestrate fleets, or set macOS preferences such as Dock or Finder settings.
The `desktop` group configures the graphical environment on Linux and macOS without installing applications.
Installing graphical applications on macOS requires a separate choice.
That choice installs the full declared VS Code extension list and leaves Rectangle shortcuts to the user.
Homelab provisioning stays out unless the owner can identify a concrete benefit.
The owner runs `sync` on each machine. Machines do not synchronize automatically.
The main commands are `just install`, `just sync`, `just export`, and `just machine`.
The group commands `just groups`, `just enable`, and `just disable` are also public.
Internal scripts are not a public interface.

A change aligns when it consolidates declarations, makes results clearer, or removes duplication, unneeded harnesses, or retired tools.
A faster `sync` aligns if it keeps all checks.
Resist changes that duplicate authority, import private state, hide upstream failures, or report full alignment despite UPDATE, EXPORT, or FAIL.
Resist changes that delay agent releases, mix provider packages, or expand support without the owner's approval.
