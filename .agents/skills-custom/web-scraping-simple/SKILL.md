---
name: web-scraping-simple
description: "Build small standalone Python scraping proofs after scouting: structured feasibility PoCs, API/static HTML/embedded JSON/light browser paths, Pydantic models, sample output, and basic audit."
argument-hint: "[url] [fields]"
---

# Web Scraping Simple

Use after `web-scraping-scout` selects feasibility or a small standalone proof. Do not create Scrapy or Crawlee production projects here.

Default to a structured feasibility PoC when the user asks whether a target can be scraped, asks for a sample/proof, or the scout needs runnable evidence. Use a single file only for truly tiny one-off extracts.

## Choose Method

- API/XHR/GraphQL: read `../web-scraping-scout/references/api-scraping.md`.
- Static HTML, JSON-LD, `__NEXT_DATA__`, tables, articles: read `../web-scraping-scout/references/parsers.md`.
- 403/429, JS-only data, Cloudflare, login/session: read `../web-scraping-scout/references/browsers.md`; try API extraction after browser discovery.
- Lifecycle and feasibility artifact shape: read `../web-scraping-references/references/feasibility-poc.md`.
- Storage and basic audit expectations: read `../web-scraping-references/references/storage-policy.md` and `../web-scraping-references/references/quality-gates.md`.

## Build Feasibility PoC

1. Create a uv project with `pyproject.toml`, `src/<project>/`, `data/raw/`, `data/failures/`, and `data/samples/`.
2. Add Pydantic models, runnable entrypoint, scraper logic, raw/failure saving, parsed sample output, and basic audit logic.
3. Write `FEASIBILITY.md` with source, auth, pagination, browser need, anti-bot/risk notes, sample size, estimated throughput, production recommendation, why/why-not alternatives, and open risks.
4. Add HTTP/browser/parser details only as needed:
   - `../web-scraping-scout/references/http-clients.md`
   - `../web-scraping-scout/references/auth.md`
   - `../web-scraping-scout/references/proxy.md`
   - `../web-scraping-scout/references/pagination.md`
5. Default parsed sample output to JSONL.
6. Add `price-parser`, `dateparser`, and `ftfy` only when fields need them.

## Verify

- `ruff check`
- `ruff format`
- `pyright`
- small sample run writes raw/failure evidence, `data/samples/output.jsonl`, `data/samples/audit.json`, and `FEASIBILITY.md`

If feasibility recommends recurring production, route next to `web-scraping-pipeline-design`.
