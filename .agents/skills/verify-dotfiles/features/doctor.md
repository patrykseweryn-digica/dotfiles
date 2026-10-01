# Machine doctor

Check machine configuration without installing tools or copying credentials.

## Sub-features

- `baseline` identifies existing drift before changes.
- `regression` catches new missing links, config and required tools.
- `diagnostics` bounds output and omits raw config diffs.

## How to get to it (user POV)

- `just doctor` for the current machine.

## Driving it with Bash smoke scripts

Preconditions: repository dependencies; retain before/after evidence.

- **Test failures.** Run `bash scripts/smoke-doctor.sh`. Its isolated doctor
  checks matching state, then changed/missing config, broken links, missing
  tools, invalid Node and disabled hooks. Read-only checks must not recreate
  missing config. A secret sentinel in a raw diff must not appear in output;
  long diagnostics must be bounded.
- **Live baseline and result.** Run `just doctor` before and after the
  change, with output paths from SKILL.md. Compare failed categories. For
  changed check code, run `cksum` on affected live files before and after;
  the checksums must match. Investigate every new failure.
- **Proof.** Retain both logs and exit codes. A nonzero live doctor means
  unresolved drift; do not report the machine as fully verified.

## Gotchas

- Existing local config may intentionally differ from repository defaults.
  Review it before any apply command; do not erase it to make doctor green.
- Doctor filters raw diffs; do not add an unredacted verbose log path.
- Native latest and upstream Node freshness are not checked by doctor.
