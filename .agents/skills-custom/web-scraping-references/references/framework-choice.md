# Framework Choice

## Default Production Path

Use Scrapy as the default production framework, including API-only production cases, unless a stronger reason applies.

Scrapy fits:

- recurring or long-running crawls
- listing-detail navigation
- API/XHR pagination at production scale
- pipelines, middleware, throttling, retries, feeds, stats
- projects needing common operations and deployment shape

## Crawlee-Python Path

Use Crawlee-python when browser context is central, not merely available.

Crawlee fits:

- stateful SPA interaction, scroll/click flows, login-like UI flows
- browser-context-heavy targets where network-only extraction is not enough
- adaptive browser/HTTP behavior is the core tactic
- Playwright runtime cost is acceptable and explicit

Do not present Crawlee as the normal alternative for ordinary HTTP/API/listing-detail crawlers.

## Standalone Python Path

Use standalone Python for:

- feasibility reconnaissance and structured PoCs
- one-off small extracts
- rare production exceptions with explicit justification

Do not let standalone scripts become silent production defaults for recurring scrapers.

## Browser Decision

- Discoverable API or GraphQL: prefer direct HTTP extraction.
- SPA with discoverable API: use API for feasibility; production usually Scrapy.
- Occasional render inside otherwise Scrapy-suitable crawl: Scrapy plus browser integration if justified.
- Interaction-heavy SPA: production design should consider Crawlee.

## Required Rationale

Every production recommendation should include:

- chosen framework and why
- why not the main alternatives
- expected runtime/cost tradeoffs
- what would change the decision
