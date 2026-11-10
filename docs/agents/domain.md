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
- `SKIP`: Plan result for an intentionally omitted action. The row states the
  reason. `SKIP` does not fail doctor or sync.
- `STEPS_COMMANDS`: Codex coding mode. It shows concrete commands and
  technical tool actions.
- `STEPS_PROSE`: Work mode. It uses general prose and hides some command
  details.
