# Toolbox Selection

Tools are options, not mandatory dependencies. Add only what the target needs.

## Health Check Before New Dependencies

For new or niche dependencies, quickly check:

- recent releases or commits
- adoption and maintenance signal
- license fit
- Python/runtime compatibility
- whether the repo already has an equivalent dependency

Use Context7 for current library docs when unsure.

## Candidate Areas

- HTTP/TLS/fingerprints: `curl_cffi`, `rnet`, `hrequests`, `scraply`, stdlib `http.client`.
- Browser/stealth: `camoufox`, `nodriver`, `zendriver`, Playwright, Selenium.
- Parsing/extraction: `selectolax`, `extruct`, `web-poet`, `scrapy-poet`, `trafilatura`.
- Scrapy ecosystem: `scrapy-impersonate`, `scrapy-playwright`.
- Reliability/logging: `tenacity`, `stamina`, `structlog`.
- Recon: browser DevTools, saved HAR/network notes, `waybackurls`.
- Infra/proxy: proxy services, serverless, hosted schedulers, database/storage sinks.

## Selection Rule

Prefer the simplest reliable path that matches the production decision:

- direct API over browser when equivalent
- Scrapy over standalone for recurring production
- Crawlee when browser interaction is central
- saved evidence over repeated live requests

## Scrapling MCP

Use available Scrapling MCP tools for HTTP samples, selector checks,
pagination discovery, and API inspection before writing a scraper.
If unavailable, use existing HTTP/browser tools and report the missing integration.
Keep the production framework selected by `web-scraping-pipeline-design`.
MCP reconnaissance alone does not require a production dependency on Scrapling.

For ordinary HTTP sampling, set `impersonate=null` and `stealthy_headers=false`
on `make_request`; inspect the current tool schema first.
Browser fetchers use stealth defaults; follow the scout's escalation boundary
before invoking them or enabling impersonation.
Use an existing browser tool for ordinary rendering when stealth is unnecessary.
Inspect raw HTML/API responses when cleaned Markdown omits needed fields.
Save representative records, selectors, pagination evidence, and failed requests
for implementation and validation. Close sessions created for reconnaissance.

When project-local MCP setup is requested in a uv repository:

```bash
uv add --dev "scrapling[ai]"
```

For browser fetchers, install browser dependencies with `uv run scrapling install`.
Configure the agent's MCP client to launch `uv` with these arguments:

```text
["--directory", "<absolute-repo-path>", "run", "scrapling", "mcp"]
```

Use the client's supported configuration location and preserve existing servers.
Verify MCP tool discovery and a small HTTP sample before reporting setup complete.
If scraper code imports Scrapling, add it as a runtime dependency with `uv add scrapling`.
For Scrapy parsing integration, read
[`parsers.md`](../../web-scraping-scout/references/parsers.md#scrapling-optional-parsing).

Check the [official MCP guide](https://scrapling.readthedocs.io/en/latest/ai/mcp-server.html)
for current tools and installation requirements.
