# Feasibility PoC

Use for small proof projects that answer: can this target be scraped, how, with what risk, and what production path is recommended?

## Default Shape

Create a uv-based project, not a loose script:

```text
pyproject.toml
README.md
FEASIBILITY.md
src/<project>/
  __init__.py
  __main__.py
  scraper.py
  models.py
  audit.py
data/
  raw/
  failures/
  samples/
    output.jsonl
    audit.json
```

Optional files only when needed:

- `config.py`: target constants, headers, sample limits.
- `storage.py`: JSONL/parquet helpers once output logic grows.
- `browser_probe.py`: short-lived browser/XHR discovery proof.

## Required Code Pieces

- runnable entry point: `uv run python -m <project>`
- typed models with Pydantic
- scraper logic for the proven source path
- raw sample/failure saving
- parsed sample output
- basic audit logic
- small sample limit by default

## Feasibility Outputs

Write:

- `data/raw/`: representative HTML/API/browser payloads.
- `data/failures/`: blocked pages, bad responses, parser failures.
- `data/samples/output.jsonl`: parsed sample records.
- `data/samples/audit.json`: counts, required field fill rates, duplicates, validation errors, suspicious constants.
- `FEASIBILITY.md`: decision report.

## FEASIBILITY.md Sections

Include:

- Source: target URL/API, data source found, sample size.
- Data goal: records and fields attempted.
- Auth/session: none, required, or unknown.
- Pagination: page links, cursor, offset, infinite scroll, or absent.
- Browser need: none, discovery-only, render-required, interaction-required.
- Anti-bot/risk notes: login, captcha, rate limit, robots/ToS signals, cost.
- Sample extracted: output path and representative fields.
- Estimated throughput: rough requests/pages/records per minute from sample evidence.
- Recommended production path: Scrapy, Crawlee, standalone exception, or stop.
- Why/why-not alternatives: brief framework/source rationale.
- Open risks/questions: blockers before production.

## Approval Boundary

Feasibility can run without a production approval gate unless it sees:

- login/session reuse
- captcha or anti-bot escalation
- paid APIs/proxies
- high-rate crawling
- paywall or notable legal/ethical risk

When those appear, stop and ask before escalating.
