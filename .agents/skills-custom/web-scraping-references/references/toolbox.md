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
