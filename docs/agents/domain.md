# Domain docs

Layout: single-context.

Before domain exploration:
- Read CONTEXT.md at the repository root if present.
- Read relevant ADRs under docs/adr/ if present.
- If absent, proceed silently; create domain docs only when resolving
  terminology or recording decisions through domain-modeling.

Use glossary terms in tickets, proposals, and tests.
Surface conflicts with existing ADRs explicitly.

## Vocabulary

- `CI runner`: Temporary machine assigned by the CI platform to execute a job.
  `queued` means no matching machine is available and the job has not started.
- `K3s`: Lightweight Kubernetes distribution that manages containerized
  applications across one or more Linux computers.
- `mise shim`: Small file in `~/.local/share/mise/shims` with the name of a
  tool command, for example `gh`. It links to the `mise` program. When a shell
  runs it, mise finds the configured tool version and starts the real program.
  One `PATH` entry for the shims directory makes all mise tools available,
  also in shells that do not read `.zshrc`.
- `NOT RUN`: Sync result for a phase whose prerequisite phase failed. The row
  states the failed prerequisite. The sync result is `FAIL`.
- `SKIP`: Plan result for an intentionally omitted action. The row states the
  reason. `SKIP` does not fail doctor or sync.
- `STEPS_COMMANDS`: Codex coding mode. It shows concrete commands and
  technical tool actions.
- `STEPS_PROSE`: Work mode. It uses general prose and hides some command
  details.
