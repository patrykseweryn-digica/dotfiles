# Checkpointing And Resume

## Goals

- avoid destructive reruns
- make failures replayable
- let long crawls resume safely
- make output trust decisions auditable

## Production Expectations

- Run IDs for every execution.
- Manifest entries for fetched URLs/endpoints and failures.
- Dedupe key or stable ID strategy.
- Retry policy with bounded attempts.
- Resume strategy for pagination/listing/detail queues.
- Output written to run-specific paths.
- Latest-good pointer only after audit passes.

## Feasibility Expectations

- Save enough raw samples/failures to explain parser assumptions.
- Record endpoint, payload, headers, pagination clues, and sample size.
- Avoid building a full checkpoint system unless needed to prove feasibility.
