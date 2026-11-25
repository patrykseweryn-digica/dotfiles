# Machine check

Build one offline, read-only plan without installing tools or copying
credentials. Every category reports `PASS`, `SKIP`, `UPDATE`, `EXPORT`, or
`FAIL`. `SKIP` records why no action applies. Only `FAIL` makes the command fail.

## Sub-features

- `baseline` identifies existing drift before changes.
- `regression` catches new missing links, config and required tools.
- `diagnostics` bounds output and omits raw config diffs.
- `skip` reports every constraint without failing machine or sync,
  including elements of unselected install groups ([groups](groups.md)).

## How to get to it (user POV)

- `just machine` for the current machine.

## Driving it with Bash smoke scripts

Preconditions: repository dependencies; retain before/after evidence.

- **Test statuses and failures.** Run `bash scripts/smoke-doctor.sh`. Its
  isolated public `just machine` drives the shared plan through matching,
  skip, update, export and failure states. The test checks every `SKIP` reason,
  broken links, missing tools, invalid Node, and disabled hooks. The real local
  adapters verify settings, MCP, skills, and plugins with fixture Codex state.
  External plugin CLI offline/read-only behavior is not proved by these fixtures.
  A secret sentinel in a raw planner failure must not appear.
- **Offline Codex settings.** The same smoke script runs real `just machine`
  and the shared sync plan with fixture settings, offline uv, and a new empty
  uv cache. Require `PASS` for matching TOML and `UPDATE` for managed drift;
  without a local Python 3.11 or newer, require a specific `FAIL` diagnostic.
  HOME, checkout and the empty cache must stay unchanged. To enforce no network
  at the OS boundary on Linux with user namespaces, first warm the mutation
  fixture with the normal smoke command, then run
  `UV_OFFLINE=1 unshare -Urn bash scripts/smoke-doctor.sh`.
- **Live baseline and result.** Run `just machine` before and after the
  change, with output paths from SKILL.md. Compare failed categories. For
  changed check code, run `cksum` on affected live files before and after;
  the checksums must match. Investigate every new failure.
- **Proof.** Retain both logs and exit codes. A nonzero live machine means
  unresolved drift; do not report the machine as fully verified.
  Zero alone is also insufficient: UPDATE and EXPORT intentionally return zero.
  Inspect category statuses rather than trusting the closing sentence.

## Gotchas

- Existing local config may intentionally differ from repository defaults.
  Review it before any apply command; do not erase it to make machine green.
- Doctor filters raw diffs; do not add an unredacted verbose log path.
- Native latest and upstream Node freshness are not checked by machine.
- The current closing sentence can claim agreement despite UPDATE or EXPORT
  (#61). Preserve the intended offline/read-only contract when reporting this bug.
