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
  skip, update, export and failure states. Require the summary to report
  differences for `UPDATE` and `EXPORT`, without a nonzero exit. The test checks
  `SKIP` reasons, broken links, missing tools, invalid Node, and disabled hooks.
  The real adapters name MCP, skill, and plugin additions without printing
  marketplace URLs. An invalid skill lock must fail the plan. A secret sentinel
  in a raw planner failure must not appear.
- **Single reads.** The same smoke script counts file arguments to `jq`, `cmp`
  and `cat` during one real plan. Require one read per watched Claude, OpenCode,
  Pi, and skill inventory file. This counts command inputs, not system calls.
- **Offline Codex state.** The same smoke script runs real `just machine`
  and the shared sync plan with fixture settings, offline uv, and an empty uv
  cache. Require one Python lookup per plan and no Codex CLI call. Require
  `PASS` for matching TOML and `UPDATE` for managed drift. Require `EXPORT`
  for an enabled Git plugin and `FAIL` for a missing marketplace snapshot or
  Python 3.11 interpreter. HOME, checkout and cache must stay unchanged.
  The test covers the user config, not Codex project or organization policies.
  To deny network access at the OS boundary, warm the mutation fixture with
  the normal smoke command first. Then run one of these commands:
  - Linux: `UV_OFFLINE=1 unshare -Urn bash scripts/smoke-doctor.sh`
  - macOS: `sandbox-exec -p '(version 1) (allow default) (deny network*)' bash scripts/smoke-doctor.sh`
- **Live baseline and result.** Run `just machine` before and after the
  change, with output paths from SKILL.md. Compare failed categories. For
  changed check code, run `cksum` on affected live files before and after;
  the checksums must match. Investigate every new failure.
- **Proof.** Retain both logs and exit codes. A nonzero live machine means
  unresolved drift; do not report the machine as fully verified.
  `UPDATE` and `EXPORT` return zero but still report differences.
  Inspect the category statuses for the next step.

## Gotchas

- Existing local config may intentionally differ from repository defaults.
  Review it before any apply command; do not erase it to make machine green.
- Doctor filters raw diffs; do not add an unredacted verbose log path.
- Native latest and upstream Node freshness are not checked by machine.
