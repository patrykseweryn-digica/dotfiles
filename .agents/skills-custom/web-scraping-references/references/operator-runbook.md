# Operator Runbook

Production scraper projects should include an operator README/runbook.

## Required Sections

- What it scrapes and known scope limits.
- How to run smoke/sample mode.
- How to run full mode.
- Where raw, parsed, curated, manifest, audit, and failure outputs are saved.
- How resume/checkpoint works.
- How to inspect audit output and decide whether a run is trusted.
- Required env vars and secrets.
- Optional alert setup.
- Common failures and first debug step.
- Retention policy.
- When not to trust output.

## Operations Defaults

- Prefer environment variables for secrets and deployment-specific settings.
- Keep sample mode cheap and safe.
- Make full mode explicit.
- Logs should identify run ID, source, counts, failures, and output paths.
- Alerts should be optional: if env vars are absent, the scraper still runs.
